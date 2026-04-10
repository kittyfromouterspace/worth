# Migration Plan: PostgreSQL → libSQL

## Executive Summary

This document outlines a migration plan to replace PostgreSQL with libSQL (SQLite with native vector support) in the Worth application. The goal is to make installation easier for non-technical users while maintaining compatibility with PostgreSQL for users who prefer it.

**Key Benefits:**
- Zero-configuration database setup (no PostgreSQL installation required)
- Single file database - easy backup/restore
- Native vector search (built-in, no extensions needed)
- Better cross-platform support
- Lower resource footprint

---

## Current Architecture Analysis

### Dependencies

| Component | Current Database | PostgreSQL-Specific Features |
|-----------|-----------------|------------------------------|
| **Worth** | PostgreSQL + pgvector | `Worth.Repo` uses `Ecto.Adapters.Postgres`, Cloak encryption |
| **Mneme** | PostgreSQL + pgvector | `Pgvector.Ecto.Vector` type, HNSW indexes, recursive CTEs for graph |
| **AgentEx** | PostgreSQL (via mneme) | Depends on mneme for persistence |

### PostgreSQL-Specific Features in Use

1. **pgvector Extension** (Critical)
   - Vector column type: `Pgvector.Ecto.Vector`
   - HNSW indexes for approximate nearest neighbor search
   - Distance operators: `<=>` (cosine distance)
   
2. **Recursive CTEs** (Important)
   - Used in `Mneme.Graph.PostgresGraph` for graph traversal
   - PostgreSQL CTE syntax with `WITH RECURSIVE`
   
3. **UUID Type** (Standard)
   - Used extensively for IDs
   - SQLite/libSQL can use `BINARY(16)` or text UUIDs
   
4. **Array Types** (Not used)
   - No PostgreSQL arrays detected in Worth/mneme
   
5. **JSONB** (Not critical)
   - Mneme uses `:map` type which maps to JSONB in PostgreSQL
   - SQLite stores JSON as TEXT

---

## libSQL Compatibility Assessment

### ✅ Supported Features

| Feature | libSQL Support | Notes |
|---------|---------------|-------|
| Vector Storage | ✅ Native | `F32_BLOB(n)`, `F64_BLOB(n)` types |
| Vector Distance | ✅ Native | `vector_distance_cos()`, `vector_distance_l2()` |
| Vector Index | ✅ Native | `libsql_vector_idx()` using DiskANN |
| Recursive CTEs | ✅ Supported | `WITH RECURSIVE` (SQLite compatible) |
| Ecto Adapter | ✅ Available | `ecto_libsql` package (actively maintained) |
| Foreign Keys | ✅ Supported | Enforced by default |
| Transactions | ✅ Supported | Full ACID compliance |
| JSON | ✅ Supported | Stored as TEXT, functions available |
| UUID | ✅ Via TEXT/BLOB | Can store as text or binary |
| Full-Text Search | ✅ Native | FTS5 extension |

### ⚠️ Migration Challenges

| Challenge | Impact | Mitigation |
|-----------|--------|------------|
| **HNSW → DiskANN** | Medium | libSQL uses DiskANN instead of HNSW; similar performance characteristics |
| **Vector Type Mapping** | High | Need adapter layer for `Pgvector.Ecto.Vector` ↔ `F32_BLOB` |
| **UUID Handling** | Low | Convert from binary UUIDs to TEXT or BLOB(16) |
| **SQL Dialect Differences** | Medium | Some PostgreSQL-specific queries need adjustment |
| **Concurrent Writes** | Low | libSQL supports concurrent writes (unlike vanilla SQLite) |

### 📊 Feature Comparison: pgvector vs libSQL Vectors

```
┌─────────────────────┬──────────────────┬──────────────────┐
│ Feature             │ pgvector         │ libSQL           │
├─────────────────────┼──────────────────┼──────────────────┤
│ Type Definition     │ vector(n)        │ F32_BLOB(n)      │
│ Index Type          │ HNSW, IVFFlat    │ DiskANN          │
│ Distance Ops        │ <=>, <->, <#>    │ Functions        │
│ Cosine Distance     │ <=>              │ vector_distance_cos()│
│ L2 Distance         │ <->              │ vector_distance_l2()│
│ Insert Vectors      │ ARRAY literal    │ vector32(),vector64()│
│ Query Vectors       │ Direct compare   │ Functions        │
└─────────────────────┴──────────────────┴──────────────────┘
```

---

## Proposed Architecture

### Design Goals

1. **Modularity**: Mneme and AgentEx should work with both PostgreSQL and libSQL
2. **Backward Compatibility**: Existing PostgreSQL users can continue using it
3. **Default Simplicity**: Worth should default to libSQL for new users
4. **Migration Path**: Clear upgrade path for existing users

### Target Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Worth Application                                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Database Adapter (configured via :database_backend)      │   │
│  │  - :libsql (default)  → Ecto.Adapters.LibSQL            │   │
│  │  - :postgres          → Ecto.Adapters.Postgres          │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │                                      │
│           ┌───────────────┼───────────────┐                    │
│           ▼               ▼               ▼                    │
│  ┌─────────────────┐ ┌──────────────┐ ┌──────────────┐          │
│  │ Worth.Repo      │ │ Worth.Repo   │ │ Mneme        │          │
│  │ (libSQL mode)   │ │ (PG mode)    │ │ (via Worth)  │          │
│  └─────────────────┘ └──────────────┘ └──────────────┘          │
│                                                           │
└───────────────────────────────────────────────────────────┘
                              │
           ┌──────────────────┼──────────────────┐
           ▼                  ▼                  ▼
  ┌────────────────┐ ┌────────────────┐ ┌────────────────┐
  │ ecto_libsql    │ │ postgrex       │ │ Vector Adapter │
  │ (Rust NIFs)    │ │ (PostgreSQL)   │ │ (behaviour)    │
  └────────────────┘ └────────────────┘ └────────────────┘
                              │
           ┌──────────────────┴──────────────────┐
           ▼                                   ▼
  ┌────────────────┐                  ┌────────────────┐
  │ libSQL/SQLite  │                  │ PostgreSQL     │
  │ (single file)  │                  │ (server)       │
  └────────────────┘                  └────────────────┘
```

---

## Mneme Modularization

### 1. Database-Specific Adapters

Create adapter modules that encapsulate database-specific operations:

```elixir
# lib/mneme/database_adapter.ex
defmodule Mneme.DatabaseAdapter do
  @moduledoc """
  Behaviour for database-specific implementations.
  """
  
  @callback vector_type(dimensions :: integer()) :: String.t()
  @callback vector_index_sql(table :: atom(), column :: atom()) :: String.t()
  @callback vector_distance_sql(column :: String.t(), query :: String.t()) :: String.t()
  @callback create_vector_extension_sql() :: String.t() | nil
  @callback uuid_type() :: atom()
  @callback supports_recursive_ctes?() :: boolean()
  @callback supports_vector_index?() :: boolean()
end

# lib/mneme/database_adapter/postgres.ex
defmodule Mneme.DatabaseAdapter.Postgres do
  @behaviour Mneme.DatabaseAdapter
  
  def vector_type(dimensions), do: "vector(#{dimensions})"
  def vector_index_sql(table, column) do
    "CREATE INDEX #{table}_#{column}_idx ON #{table} USING hnsw (#{column} vector_cosine_ops)"
  end
  def vector_distance_sql(column, query), do: "#{column} <=> #{query}"
  def create_vector_extension_sql, do: "CREATE EXTENSION IF NOT EXISTS vector"
  def uuid_type, do: :uuid
  def supports_recursive_ctes?, do: true
  def supports_vector_index?, do: true
end

# lib/mneme/database_adapter/libsql.ex
defmodule Mneme.DatabaseAdapter.LibSQL do
  @behaviour Mneme.DatabaseAdapter
  
  def vector_type(dimensions), do: "F32_BLOB(#{dimensions})"
  def vector_index_sql(table, column) do
    "CREATE INDEX #{table}_#{column}_idx ON #{table} (libsql_vector_idx(#{column}))"
  end
  def vector_distance_sql(column, query), do: "vector_distance_cos(#{column}, #{query})"
  def create_vector_extension_sql, do: nil  # Built-in
  def uuid_type, do: :binary_id  # or :string for text UUIDs
  def supports_recursive_ctes?, do: true
  def supports_vector_index?, do: true
end
```

### 2. Migration Template System

Replace static migrations with adapter-aware templates:

```elixir
# lib/mneme/migration_generator.ex
defmodule Mneme.MigrationGenerator do
  @moduledoc """
  Generates database-specific migrations at compile time or runtime.
  """
  
  def generate_migration(adapter, dimensions) do
    """
    defmodule Mneme.Repo.Migrations.CreateMnemeTables do
      use Ecto.Migration
      
      def up do
        #{if sql = adapter.create_vector_extension_sql(), do: "execute(\"#{sql}\")", else: ""}
        
        create table(:mneme_entries, primary_key: false) do
          add(:id, :binary_id, primary_key: true)
          add(:scope_id, #{inspect(adapter.uuid_type())})
          add(:embedding, #{inspect(adapter.vector_type(dimensions))})
          # ... other fields
        end
        
        execute(\"#{adapter.vector_index_sql(:mneme_entries, :embedding)}\")
      end
    end
    """
  end
end
```

### 3. Runtime Adapter Selection

```elixir
# config/runtime.exs or config.exs
config :mneme,
  database_adapter: Mneme.DatabaseAdapter.LibSQL,  # or Postgres
  repo: Worth.Repo

# lib/mneme/config.ex - add adapter resolution
defmodule Mneme.Config do
  def adapter do
    Application.get_env(:mneme, :database_adapter, Mneme.DatabaseAdapter.LibSQL)
  end
end
```

---

## SQL Translation Guide

### Vector Operations

| Operation | PostgreSQL (pgvector) | libSQL |
|-----------|----------------------|--------|
| **Column Type** | `vector(768)` | `F32_BLOB(768)` |
| **Insert** | `ARRAY[0.1, 0.2]::vector` | `vector32('[0.1, 0.2]')` |
| **Cosine Distance** | `embedding <=> query` | `vector_distance_cos(embedding, query)` |
| **Cosine Similarity** | `1 - (embedding <=> query)` | `1 - vector_distance_cos(embedding, query)` |
| **Order by Distance** | `ORDER BY embedding <=> query` | `ORDER BY vector_distance_cos(embedding, query)` |
| **Index Creation** | `USING hnsw (embedding vector_cosine_ops)` | `(libsql_vector_idx(embedding))` |
| **Top-K Search** | `ORDER BY ... LIMIT k` | `vector_top_k('index_name', query, k)` |

### Search Query Migration Example

**PostgreSQL Version:**
```sql
SELECT id, content,
  (1 - (embedding <=> $1::text::vector)) AS score
FROM mneme_entries
WHERE scope_id = $2
  AND embedding IS NOT NULL
  AND (1 - (embedding <=> $1::text::vector)) >= $3
ORDER BY embedding <=> $1::text::vector
LIMIT $4
```

**libSQL Version:**
```sql
SELECT id, content,
  (1 - vector_distance_cos(embedding, vector32($1))) AS score
FROM mneme_entries
WHERE scope_id = $2
  AND embedding IS NOT NULL
  AND (1 - vector_distance_cos(embedding, vector32($1))) >= $3
ORDER BY vector_distance_cos(embedding, vector32($1))
LIMIT $4
```

Note: For approximate search with index:
```sql
-- libSQL with vector index (more efficient)
SELECT e.id, e.content, v.distance
FROM vector_top_k('mneme_entries_embedding_idx', vector32($1), $4) AS v
JOIN mneme_entries e ON e.rowid = v.id
WHERE e.scope_id = $2
  AND (1 - v.distance) >= $3
```

### Recursive CTEs

PostgreSQL and libSQL both support recursive CTEs with similar syntax:

```sql
-- Works in both (with minor adjustments)
WITH RECURSIVE graph_walk AS (
  -- Base case
  SELECT to_entity_id AS entity_id, 1 AS depth
  FROM mneme_relations
  WHERE from_entity_id = ? AND owner_id = ?
  
  UNION ALL
  
  -- Recursive case
  SELECT r.to_entity_id, gw.depth + 1
  FROM graph_walk gw
  JOIN mneme_relations r ON r.from_entity_id = gw.entity_id
  WHERE gw.depth < ?
)
SELECT * FROM graph_walk;
```

### UUID Handling

**Option A: Text UUIDs (Recommended)**
```sql
-- Store as TEXT in both databases
add(:scope_id, :string)  -- Ecto type :string
-- Insert: "550e8400-e29b-41d4-a716-446655440000"
```

**Option B: Binary UUIDs (Compact)**
```sql
-- PostgreSQL
add(:scope_id, :uuid)  -- 16 bytes

-- libSQL
add(:scope_id, :binary)  -- 16 bytes
-- Need manual conversion functions
```

---

## Implementation Phases

### Phase 1: Foundation (2-3 weeks)

**Goals:**
- Make mneme database-agnostic
- Create adapter behaviour and implementations
- Add configuration system

**Tasks:**
1. **Mneme Core Changes**
   - [ ] Create `Mneme.DatabaseAdapter` behaviour
   - [ ] Implement `Postgres` adapter (extract current code)
   - [ ] Implement `LibSQL` adapter with new SQL dialect
   - [ ] Update `Mneme.Config` to support adapter selection
   - [ ] Refactor `Mneme.Search.Vector` to use adapter for SQL generation
   - [ ] Refactor `Mneme.Graph.PostgresGraph` to use adapter (or create `LibSQLGraph`)

2. **Schema Updates**
   - [ ] Update all schemas to use adapter-provided types
   - [ ] Create migration template generator
   - [ ] Update `mix mneme.gen.migration` task to support both databases

3. **Testing**
   - [ ] Ensure all tests pass with PostgreSQL (regression test)
   - [ ] Add test suite for libSQL adapter
   - [ ] Create CI matrix for both databases

### Phase 2: Worth Migration (1-2 weeks)

**Goals:**
- Update Worth to support libSQL
- Make Worth depend on libSQL by default

**Tasks:**
1. **Configuration**
   - [ ] Update `config/config.exs` to use `ecto_libsql` adapter
   - [ ] Create database backend selection config
   - [ ] Update `Worth.Repo` to dynamically select adapter

2. **Dependencies**
   - [ ] Add `ecto_libsql` to Worth's `mix.exs`
   - [ ] Update `mneme` dependency to use modular version
   - [ ] Make `postgrex` optional dependency

3. **Schema Updates**
   - [ ] Update Worth migrations to support both databases
   - [ ] Ensure encrypted settings work with both backends (Cloak compatibility)

4. **Testing**
   - [ ] Verify Worth works with libSQL
   - [ ] Ensure backward compatibility with PostgreSQL

### Phase 3: AgentEx Updates (1 week)

**Goals:**
- Ensure AgentEx works with the updated mneme
- Make AgentEx database-agnostic

**Tasks:**
- [ ] Update AgentEx dependencies
- [ ] Test AgentEx with both database backends
- [ ] Update documentation

### Phase 4: Data Migration Tooling (1-2 weeks)

**Goals:**
- Provide migration path for existing users
- Create export/import tools

**Tasks:**
1. **Export Tool**
   - [ ] Create `Mneme.Export` module
   - [ ] Export all data to JSON/JSONL format
   - [ ] Handle vector embeddings properly

2. **Import Tool**
   - [ ] Create `Mneme.Import` module
   - [ ] Import from JSON/JSONL to any supported database
   - [ ] Re-embed if needed (model compatibility)

3. **Worth CLI Commands**
   - [ ] Add `/database export` command
   - [ ] Add `/database import` command
   - [ ] Add `/database migrate-to-libsql` command

### Phase 5: Documentation & Release (1 week)

**Tasks:**
- [ ] Update README with new installation instructions
- [ ] Create migration guide for existing users
- [ ] Document configuration options
- [ ] Create troubleshooting guide
- [ ] Update Docker/CI configurations
- [ ] Tag releases for mneme, agent_ex, and worth

---

## Configuration Examples

### Worth with libSQL (New Default)

```elixir
# config/runtime.exs
config :worth,
  database_backend: :libsql,  # or :postgres
  ecto_repos: [Worth.Repo]

config :worth, Worth.Repo,
  database: Path.join(System.user_home!(), ".worth/worth.db"),
  pool_size: 5

config :mneme,
  database_adapter: Mneme.DatabaseAdapter.LibSQL,
  repo: Worth.Repo,
  embedding: [
    provider: Worth.Memory.Embeddings.Adapter,
    dimensions: 1536
  ]
```

### Worth with PostgreSQL (Existing Users)

```elixir
# config/runtime.exs
config :worth,
  database_backend: :postgres

config :worth, Worth.Repo,
  username: System.get_env("DB_USER", "postgres"),
  password: System.get_env("DB_PASSWORD", "postgres"),
  database: System.get_env("DB_NAME", "worth_dev"),
  hostname: System.get_env("DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("DB_PORT", "5432")),
  pool_size: 10,
  types: Worth.PostgrexTypes

config :mneme,
  database_adapter: Mneme.DatabaseAdapter.Postgres,
  repo: Worth.Repo
```

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| **Performance regression** | Medium | High | Benchmark both databases; keep PostgreSQL as option |
| **Data migration errors** | Low | High | Thorough testing; backup/restore tools; reversible migration |
| **ecto_libsql bugs** | Medium | Medium | Active package maintenance; fallback to exqlite if needed |
| **Vector index differences** | Low | Medium | Test vector search quality; tune DiskANN parameters |
| **Breaking changes in libSQL** | Low | Low | Pin specific libSQL version; test before updates |
| **Concurrent write limits** | Low | Low | libSQL supports concurrent writes; monitor contention |

---

## Success Criteria

1. ✅ New Worth installations work without PostgreSQL setup
2. ✅ All existing tests pass with both database backends
3. ✅ Vector search quality is equivalent (measured by recall@k)
4. ✅ Performance is within 20% of PostgreSQL for common operations
5. ✅ Existing users can migrate their data without loss
6. ✅ Documentation is complete and clear

---

## Appendix A: Package Dependencies

### New Dependencies (Worth)

```elixir
# mix.exs
defp deps do
  [
    # Database adapters (one will be configured at runtime)
    {:ecto_libsql, "~> 0.9", optional: true},
    {:postgrex, "~> 0.19", optional: true},
    
    # Mneme (updated version with adapter support)
    {:mneme, path: "../mneme"},
    
    # ... rest of deps
  ]
end
```

### Mneme Changes

```elixir
# mneme/mix.exs
defp deps do
  [
    {:ecto_sql, "~> 3.12"},
    # Make database drivers optional - user chooses
    {:postgrex, "~> 0.19", optional: true},
    {:ecto_libsql, "~> 0.9", optional: true},
    # Remove hard pgvector dependency
    # {:pgvector, "~> 0.3", optional: true},
    # ... rest of deps
  ]
end
```

---

## Appendix B: Testing Strategy

### CI Matrix

```yaml
# .github/workflows/test.yml
strategy:
  matrix:
    database: [postgres, libsql]
    include:
      - database: postgres
        adapter: postgres
      - database: libsql
        adapter: libsql
```

### Local Testing

```bash
# Test with libSQL (default)
mix test

# Test with PostgreSQL
WORTH_DB_ADAPTER=postgres mix test

# Test both
mix test.all_databases
```

---

## Appendix C: Migration Commands

```bash
# For existing Worth users migrating to libSQL

# 1. Export current data
mix worth.export --output worth_backup.jsonl

# 2. Update configuration (set database_backend: :libsql)
# Edit config/runtime.exs

# 3. Setup new database
mix ecto.create
mix ecto.migrate

# 4. Import data
mix worth.import --input worth_backup.jsonl

# 5. Verify
mix worth.verify
```

---

**Document Version:** 1.0  
**Last Updated:** 2026-04-10  
**Status:** Ready for Implementation
