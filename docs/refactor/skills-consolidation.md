# Skills Consolidation: Worth + agent_ex

## Problem

Skill handling is split across Worth and agent_ex with overlapping responsibilities,
dead code paths, and a non-functional evolution loop. Worth built higher-level
features (evaluate, refine, promote, version) on top of its CRUD — but never wired
them together. The usage tracking that feeds refinement and promotion was never
called, so the entire evolution loop was inert.

## Architecture Decision: Two Parsers, Intentional

agent_ex's parser returns `%{meta: ..., body: ..., raw: ...}` with fields for
the agent runtime (type, core, parameters, source). Worth's parser returns a
flat map with Worth-specific fields (evolution, trust_level, provenance,
allowed_tools). These are different concerns — Worth's parser is not a duplicate
but a superset. Both parsers stay.

## Ownership Boundaries

| Concern | Owner | Rationale |
|---------|-------|-----------|
| SKILL.md format & parsing (runtime) | **agent_ex** | Format is agent_ex's spec |
| SKILL.md parsing (evolution/trust) | **Worth** | Worth-specific fields |
| Basic CRUD (install/remove/list/read) | **Both** | agent_ex for agent tools, Worth for UI/management |
| Model tier analysis | **agent_ex** | Tied to LLM dispatch |
| In-memory registry + boot cache | **Worth** | Worth-specific app lifecycle |
| Usage tracking & success rates | **Worth** | Worth owns sessions, sees outcomes |
| Evaluation & promotion eligibility | **Worth** | Host-app policy decisions |
| Refinement (LLM-driven) | **Worth** | Needs Worth's LLM routing + context |
| Versioning & rollback | **Worth** | Persistence is Worth's domain |
| Trust levels & promotion paths | **Worth** | Policy layer, not agent concern |
| Content validation gates | **Worth** | Quality enforcement on install/create |

## Implementation Status

### Phase 1: Wire up usage tracking -- DONE

**Files changed:** `lib/worth/brain.ex`

- Fixed event shape mismatch: Brain was matching on `{:tool_result, %{name:, success:}}`
  which never matched agent_ex's actual `{:tool_trace, name, input, output, is_error, ws}` events.
  The old refinement trigger was dead code due to this shape mismatch.
- Added `track_skill_tool_usage/3` in the `execute_external_tool` callback — tracks
  usage when `skill_read` is called, recording the actual skill name from the args.
- Usage recording happens async via `Task.Supervisor` to avoid blocking tool execution.
- After recording usage, checks for promotion eligibility via `maybe_suggest_promotion/1`.

### Phase 2: Wire up validation gates -- DONE

**Files changed:** `lib/worth/skills/service.ex`, `lib/worth/skills/refiner.ex`

- `Service.install(%{type: :content, ...})` now validates the skill map via
  `Validator.validate/1` before writing to disk.
- `Refiner.resolve_and_save/2` validates refined skills before saving.
- Invalid skills return `{:error, "Validation failed: ..."}` with specific reasons.

### Phase 3: Parser/CRUD consolidation -- KEPT SEPARATE

After analysis, the parsers serve different purposes:
- **agent_ex parser**: Runtime fields (type, core, parameters, source)
- **Worth parser**: Evolution fields (usage_count, success_count, trust_level, provenance)

Delegating would require adapter code more complex than the current implementation.
Both parsers stay, with clear ownership boundaries.

### Phase 4: Fix the Refiner -- DONE

**Files changed:** `lib/worth/skills/evaluator.ex`, `lib/worth/skills/refiner.ex`

- Aligned `Evaluator.should_refine?/1` threshold with Refiner's internal check:
  both now require `usage_count >= 5` (was `> 0` in Evaluator).
- Added named constants `@min_usage_for_refinement` and `@refinement_threshold`.
- `reactive_refine/3` kept as-is — useful for explicit user-triggered refinement
  (different from statistical `refine/2`).
- Added validation gate to `Refiner.resolve_and_save/2`.

### Phase 5: Wire up lifecycle and promotion -- DONE

**Files changed:** `lib/worth/brain.ex`, `lib/worth/skills/lifecycle.ex`,
`lib/worth/skills/evaluator.ex`

- `Evaluator.should_promote?/1` now returns `{:promote, target_level}` when a
  skill meets criteria, not just `true/false`.
- `Lifecycle.execute_promotion/2` added — actually performs the promotion by
  updating trust_level, saving a version, and refreshing the registry.
- `Brain.skill_promote/1` added as a public API for the UI.
- `Brain.maybe_suggest_promotion/1` broadcasts `{:skill_promotion_available, name, target}`
  via PubSub when a skill becomes promotion-eligible.
- Promotion check runs after every `record_usage` call.

### Phase 6: Consolidate skill path resolution -- DONE

**New file:** `lib/worth/skills/paths.ex`

**Files changed:** `lib/worth/skills/service.ex`, `lib/worth/skills/refiner.ex`,
`lib/worth/skills/versioner.ex`

- Created `Worth.Skill.Paths` with `resolve/1`, `core_dir/0`, `user_dir/0`,
  `learned_dir/0`, `core?/1`.
- Replaced 3 duplicate `resolve_skill_path`/`resolve_skill_dir` implementations.
- Versioner no longer falls back to `/tmp` — returns `{:error, :skill_not_found}`.
- Fixed pre-existing test failures in refiner_test.exs and versioner_test.exs
  where tests used `~/.worth/skills` instead of `Worth.Skill.Paths.user_dir()`.

### Phase 7: Fix numerical stability in record_usage -- DONE

**Files changed:** `lib/worth/skills/service.ex`, `lib/worth/skills/parser.ex`

- `evolution` map now includes `success_count` (integer) alongside `success_rate`.
- `record_usage/2` increments `success_count` directly instead of reconstructing
  it from `success_rate * (usage_count - 1)`.
- Parser reads/writes `success_count` from SKILL.md frontmatter.
- `to_frontmatter_string/1` includes `success_count` in output.

## Remaining Work

- **`Lifecycle.create_from_experience/3`**: Still uncalled. Needs a UI trigger
  (e.g. `/skill learn` command) or agent-initiated flow.
- **`Evaluator.performance_summary/1`**: Useful for UI display — should be wired
  into the skills sidebar tab.
- **`Trust.can_use_tool?/2`**: Tool access control per trust level — not wired
  into agent_ex's tool permission system yet.
- **Promotion UI**: PubSub event is broadcast but no UI handler listens for
  `{:skill_promotion_available, ...}` yet.

## Files Changed

| File | Change |
|------|--------|
| `lib/worth/brain.ex` | Usage tracking in callbacks, promotion flow, event shape fix |
| `lib/worth/skills/service.ex` | Use Paths module, validation gate, success_count tracking |
| `lib/worth/skills/evaluator.ex` | Aligned thresholds, improved should_promote? return |
| `lib/worth/skills/lifecycle.ex` | Added execute_promotion/2 |
| `lib/worth/skills/validator.ex` | No changes (already correct, now called) |
| `lib/worth/skills/refiner.ex` | Use Paths module, validation gate |
| `lib/worth/skills/versioner.ex` | Use Paths module, error instead of /tmp fallback |
| `lib/worth/skills/parser.ex` | Added success_count to evolution |
| `lib/worth/skills/trust.ex` | No changes (functions now called via Evaluator/Lifecycle) |
| `lib/worth/skills/registry.ex` | No changes |
| **New:** `lib/worth/skills/paths.ex` | Shared path resolution |
| `test/worth/skills/versioner_test.exs` | Fixed path to use Paths.user_dir() |
| `test/worth/skills/refiner_test.exs` | Fixed path to use Paths.user_dir() |
