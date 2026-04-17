# Database Layer: Ash + AshPostgres Analysis

## The Question

Should worth adopt Ash Framework (with AshPostgres) as its data layer, replacing or coexisting with the raw Ecto approach used by recollect?

## Current State

Worth owns `Worth.Repo` (Ecto.Repo), which recollect uses via `config :recollect, repo: Worth.Repo`. Recollect has 8 Ecto schemas and 12 tables, but **most queries are raw SQL** (`repo.query/2`) -- especially pgvector similarity search, recursive CTEs for graph traversal, bulk operations, and 4 tables that have no schemas at all.

```
recollect database usage:
├── Ecto.Query DSL        → simple CRUD (create, update, delete_by)
├── repo.query/2 (raw)    → pgvector search, CTEs, bulk ops, non-schema tables
├── Ecto associations     → declared but never traversed via preload/join
├── Ecto.Multi            → not used (3 Repo.transaction calls, all raw SQL inside)
└── fragment()            → not used
```

## What Ash Would Own

Ash resources would model **worth's domain data**, not recollect's internals. Recollect continues to use raw Ecto against the same Repo -- Ash and Ecto coexist on the same database.

### Worth's Own Data (candidates for Ash resources)

| Resource | Table | Why Ash Helps |
|----------|-------|---------------|
| `Worth.Data.Skill` | `worth_skills` | CRUD + lifecycle state machine + validation + code interface |
| `Worth.Data.SkillVersion` | `worth_skill_versions` | Version history, belongs_to skill |
| `Worth.Data.SkillEvaluation` | `worth_skill_evaluations` | A/B test results, success rates |
| `Worth.Data.Kit` | `worth_kits` | Installed kits, version tracking |
| `Worth.Data.Workspace` | `worth_workspaces` | Workspace metadata |
| `Worth.Data.Session` | `worth_sessions` | Session history (or keep as JSONL?) |
| `Worth.Data.CostRecord` | `worth_cost_records` | Per-turn cost tracking |

### Recollect's Data (stays raw Ecto)

| Table | Ash? | Reason |
|-------|------|--------|
| `recollect_entries` | No | pgvector similarity search, memory decay, complex raw SQL |
| `recollect_edges` | No | Graph CTEs, raw SQL |
| `recollect_chunks` | No | pgvector + raw embedding writes |
| `recollect_entities` | No | pgvector + extraction pipeline |
| `recollect_relations` | No | Graph CTEs |
| `recollect_collections` | No | Pipeline orchestration |
| `recollect_documents` | No | Pipeline orchestration |
| `recollect_pipeline_runs` | No | Pipeline status tracking |
| `recollect_conflicts` | No | No schema, raw SQL only |
| `recollect_consolidation_runs` | No | No schema, raw SQL only |
| `recollect_handoffs` | No | No schema, raw SQL only |
| `recollect_mipmaps` | No | No schema, raw SQL only |

## Why Ash Makes Sense Here

### 1. Skill Lifecycle is a State Machine

Ash's action system maps directly to the CREATE/TEST/REFINE/PROMOTE lifecycle:

```elixir
defmodule Worth.Data.Skill do
  use Ash.Resource,
    domain: Worth.Data,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "worth_skills"
    repo Worth.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string do
      allow_nil? false
      constraints [match: ~r/^[a-z0-9-]+$/]
    end
    attribute :description, :string
    attribute :trust_level, :atom do
      constraints [one_of: [:core, :installed, :learned, :unverified]]
      default :installed
    end
    attribute :provenance, :atom do
      constraints [one_of: [:human, :agent, :hybrid, :kit]]
    end
    attribute :state, :atom do
      constraints [one_of: [:draft, :testing, :refining, :production, :archived]]
      default :draft
    end
    attribute :success_rate, :float, default: 0.0
    attribute :usage_count, :integer, default: 0
    attribute :version, :integer, default: 1
    attribute :evolution_metadata, :map, default: %{}
    attribute :loading, :atom, default: :on_demand
    attribute :model_tier, :atom, default: :any
    attribute :kit_slug, :string
    attribute :kit_owner, :string
    attribute :kit_version, :string
  end

  actions do
    defaults [:read, :destroy]

    create :install do
      accept [:name, :description, :trust_level, :provenance, :loading, :model_tier,
              :kit_slug, :kit_owner, :kit_version]
      validate attribute_does_not_equal(:trust_level, :unverified) do
        message "Use :unverified_trust for unverified installs"
      end
    end

    update :begin_test do
      accept []
      change set_attribute(:state, :testing)
      validate attribute_does_not_equal(:state, :testing)
    end

    update :promote do
      accept [:trust_level]
      validate compare(:success_rate, greater_than: 0.79)
      validate compare(:usage_count, greater_than_or_equal_to: 10)
      change set_attribute(:state, :production)
    end

    update :demote do
      accept [:trust_level]
      change set_attribute(:state, :refining)
    end

    update :record_usage do
      accept []
      change atomic_update(:usage_count, expr(usage_count + 1))
    end

    update :update_success_rate do
      accept [:success_rate]
    end

    update :refine do
      accept [:description, :evolution_metadata]
      change atomic_update(:version, expr(version + 1))
      change set_attribute(:state, :refining)
    end

    update :archive do
      accept []
      change set_attribute(:state, :archived)
    end
  end

  calculations do
    calculate :eligible_for_promotion?, :boolean,
      expr(success_rate >= 0.8 and usage_count >= 10 and state == :testing)
  end
end
```

Without Ash, this is 200+ lines of boilerplate: schema, changesets, separate functions for each state transition, manual validation. With Ash, the state machine, validations, and transitions are declarative.

### 2. Code Interfaces Eliminate Boilerplate

Ash's code interface derives functions from actions:

```elixir
defmodule Worth.Data.Skill do
  # ... resource definition ...

  code_interface do
    define_for Worth.Data
    define :install, args: [:name, :opts]
    define :list_active, action: :read, args: [{:filter, []}]
    define :begin_test, args: [:id]
    define :promote, args: [:id], get?: true
    define :record_usage, args: [:id], get?: true
    define :eligible_for_promotion?, action: :read
  end
end
```

This generates:
- `Worth.Data.Skill.install!("git-workflow", trust_level: :core)`
- `Worth.Data.Skill.list_active!(filter: [state: :production])`
- `Worth.Data.Skill.begin_test!(id)`
- No need to write `Worth.Skills.Service.install/2`, `Worth.Skills.Service.promote/1`, etc.

### 3. Aggregates for Skill Analytics

```elixir
defmodule Worth.Data.Skill do
  aggregates do
    count :total_evaluations, :evaluations
    avg :avg_success_rate, :evaluations, field: :success_rate
  end
end

defmodule Worth.Data.SkillVersion do
  attributes do
    uuid_primary_key :id
    attribute :version, :integer
    attribute :content, :string
    belongs_to :skill, Worth.Data.Skill
  end
end

# Query: "Find all skills eligible for promotion, sorted by evaluation count"
Worth.Data.Skill
|> Ash.Query.filter(eligible_for_promotion? == true)
|> Ash.Query.sort(total_evaluations: :desc)
|> Ash.Query.load([:total_evaluations, :avg_success_rate])
|> Ash.read!()
```

### 4. Policies for Trust Levels

```elixir
defmodule Worth.Data.Skill do
  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy [action(:promote), action(:demote)] do
      authorize_if actor_attribute_equals(:role, :admin)
    end

    policy action(:install) do
      authorize_if always()
    end

    policy action(:refine) do
      authorize_if relates_to_actor_via(:provenance)
    end
  end
end
```

Trust level transitions become policy-enforced. Agent-created skills can self-refine but can't self-promote.

### 5. Atomic Updates

Ash's `atomic_update` avoids race conditions on counters:

```elixir
# Without Ash:
skill = Repo.get!(Skill, id)
Repo.update!(Skill.changeset(skill, %{usage_count: skill.usage_count + 1}))

# With Ash:
update :record_usage do
  change atomic_update(:usage_count, expr(usage_count + 1))
end
```

This generates `UPDATE worth_skills SET usage_count = usage_count + 1 WHERE id = $1` -- no read-modify-write race.

## Coexistence Strategy

Ash and Ecto coexist on the same database. AshPostgres.Repo wraps Ecto.Repo. Recollect calls `Config.repo()` (which is Worth.Repo) and does raw SQL as before.

```
┌─────────────────────────────────────────────┐
│              Worth.Repo                       │
│         (AshPostgres.Repo)                   │
│                                              │
│  ┌──────────────┐    ┌──────────────────┐    │
│  │  Ash Layer    │    │  Raw Ecto        │    │
│  │              │    │                  │    │
│  │ worth_skills │    │ recollect_entries    │    │
│  │ worth_kits   │    │ recollect_edges      │    │
│  │ worth_sessions│   │ recollect_chunks     │    │
│  │ worth_costs  │    │ recollect_entities   │    │
│  └──────┬───────┘    │ recollect_relations  │    │
│         │            │ recollect_* (raw)    │    │
│         │            └────────┬─────────┘    │
│         │                     │              │
├─────────┼─────────────────────┼──────────────┤
│         │    PostgreSQL + pgvector            │
│         │    (one database, shared)           │
└─────────┴─────────────────────┴──────────────┘
```

### Repo Setup

```elixir
defmodule Worth.Repo do
  use AshPostgres.Repo,
    otp_app: :worth

  def installed_extensions do
    ["ash-functions", "vector", "pg_trgm"]
  end
end
```

AshPostgres.Repo wraps Ecto.Repo. Recollect's `Config.repo()` returns `Worth.Repo`. No adapter conflict.

### Migration Strategy

Worth owns the migration directory. Recollect provides a Mix task to generate its migration:

```elixir
# Worth runs both its own migrations and recollect's:
# priv/repo/migrations/
#   ├── 20260101000000_create_recollect_tables.exs      (from recollect)
#   ├── 20260101000001_add_memory_enhancements.exs  (from recollect)
#   ├── ...
#   ├── 20260407000000_create_worth_tables.exs       (worth's own)
#   └── 20260407000001_create_skill_versions.exs    (worth's own)
```

Ash's `mix ash.codegen` generates migration snapshots and diffs. Worth uses Ash for its tables and runs recollect's migration generator separately.

## What Ash Does NOT Replace

### Recollect's Vector Search

Ash has no pgvector support. The 4 vector similarity queries stay as raw SQL:

```elixir
# This stays as-is in Recollect.Search.Vector:
repo.query("""
  SELECT me.id, me.content, me.summary, ...
    (1 - (me.embedding <=> $1::text::vector)) AS score
  FROM recollect_entries me
  WHERE me.scope_id = $2 AND me.embedding IS NOT NULL
  ORDER BY me.embedding <=> $1::text::vector LIMIT $4
""", [embedding, scope_id, threshold, limit])
```

### Recollect's Graph Traversal

Recursive CTEs stay raw:

```elixir
# This stays as-is in Recollect.Graph.PostgresGraph:
repo.query("""
  WITH RECURSIVE neighbors AS (
    SELECT e.id, e.name, 1 as depth
    FROM recollect_relations r
    JOIN recollect_entities e ON e.id = CASE ... END
    WHERE r.from_entity_id = $1
    UNION ALL
    SELECT e.id, e.name, n.depth + 1
    FROM recollect_relations r
    JOIN recollect_entities e ON ...
    JOIN neighbors n ON ...
    WHERE n.depth < $2
  )
  SELECT * FROM neighbors
""", [entity_id, max_hops])
```

### Agentic Callbacks

Agentic's callback system is runtime, not data-driven. It doesn't use the database. Ash doesn't touch this.

### Session Transcripts

JSONL files on disk. No database. No Ash.

## Cost-Benefit Analysis

### Benefits

| Benefit | Impact |
|---------|--------|
| Skill lifecycle state machine | Eliminates ~300 lines of boilerplate changeset/transition code |
| Code interfaces | Eliminates Service modules for CRUD |
| Atomic updates | Race-safe counter increments for usage_count, success_rate |
| Policies | Trust-level enforcement as data-layer authorization |
| Aggregates/Calculations | Skill analytics queries become one-liners |
| Migration generation | `mix ash.codegen` diffs schema changes automatically |
| Validation DSL | Consistent validation across all resources |
| Domain model | Clear separation: worth's domain (Ash) vs recollect's internals (raw Ecto) |

### Costs

| Cost | Mitigation |
|------|------------|
| Ash learning curve | The DSL is well-documented; skill resources are simple CRUD + state machine |
| Added dependency weight | ash (~7 packages), ash_postgres (~4 packages). Significant but not bloated. |
| Two paradigms in one codebase | Clear boundary: worth's tables use Ash, recollect's tables use raw Ecto. Never mix. |
| Ash compile-time overhead | Ash does significant compile-time validation. Adds ~1-2s to compilation. |
| Raw SQL escape hatches needed | For worth's own data if Ash can't express it, use `Worth.Repo.query/2` directly. Ash doesn't prevent this. |
| Recollect won't benefit | Recollect continues using raw Ecto. The vector search, CTEs, and bulk ops don't map to Ash resources. |

### Ash Package Dependencies

```
ash               (~> 3.23)
├── picosat_elixir  (or simple_sat)
├── ecto            (already have)
├── spark           (code formatting for DSL)
└── igniter         (code generation, optional)

ash_postgres       (~> 2.8)
├── ash             (above)
├── ecto_sql        (already have)
├── postgrex        (already have)
└── jason           (already have)
```

Net new dependencies: `ash`, `ash_postgres`, `picosat_elixir`, `spark`, `igniter`. All others are already transitive or direct deps.

## Recommendation

**Adopt Ash + AshPostgres for worth's domain data. Keep recollect on raw Ecto.**

The skill lifecycle is the strongest argument. It's a state machine with validation, authorization, and analytics -- exactly what Ash excels at. The kit tracking and workspace metadata are simpler but benefit from the same patterns.

Recollect's vector search, graph CTEs, and bulk operations don't map well to Ash resources. They stay as raw SQL. The two paradigms coexist cleanly because they operate on different tables.

### Implementation Order

Phase 1-2: No Ash. Use plain Ecto schemas for skills and workspaces (as currently planned). This keeps the initial skeleton simple.

Phase 4 (Skills): Introduce Ash. Convert skill schemas to Ash resources when the lifecycle state machine is implemented. This is the natural inflection point -- the CREATE/TEST/REFINE/PROMOTE lifecycle is where Ash provides the most value.

Phase 5-7: Expand Ash resources for kits, sessions, cost records.

### Migration Path

If you change your mind about Ash, converting back is straightforward:
- Ash resources are just Ecto schemas under the hood
- `mix ash_postgres.gen.resources` can be run in reverse
- The raw SQL queries for recollect are completely unaffected

The risk is low because Ash adoption is incremental and reversible.
