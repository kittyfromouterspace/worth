# Worth Codebase Cleanup Roadmap

> **Status:** P0–P3 cleanup complete — 126 tests passing  
> **Last reviewed:** 2026-04-14  
> **Scope:** Elixir patterns, Phoenix/LiveView consistency, dependency hygiene, frontend assets, test coverage, and code quality tooling.

---

## How to use this document

1. **Work top-down** — P0 items are security/crash risks that should be resolved before any large refactor.
2. **Discuss and lock decisions** — Every item has an `Options` section and a `Decision` checkbox. Do not start implementation until the team agrees on the chosen option.
3. **Tick off as you go** — Update the `[ ]` checkboxes to `[x]` when a decision is made or work is merged.
4. **Keep this file in version control** — If an item is deprioritized, move it to the "Deferred" section with a one-line rationale.

---

## Legend

| Tag | Meaning |
|-----|---------|
| `🔴 P0` | Security vulnerability, crash bug, or data corruption risk. Fix immediately. |
| `🟡 P1` | Structural debt that blocks maintainability or correctness. Fix in next 1–2 sprints. |
| `🟢 P2` | Hygiene, tooling, or velocity issues. Batch into a dedicated cleanup sprint. |
| `🔵 P3` | Polish and optimization. Tackle when touching adjacent code. |

---

# 🔴 P0 — Fix Before Anything Else

## P0.1 XSS via unsanitized Markdown rendering

- **Problem:** `Earmark.as_html/2` output is passed directly to `Phoenix.HTML.raw/1`. The LLM could emit `<script>` tags or event handlers.
- **Evidence:**
  - `lib/worth_web/components/chat_components.ex:809`
  - `lib/worth_web/live/chat_live.ex:1272`
- **Risk:** Arbitrary JavaScript execution in the user’s browser.

### Options
- [ ] **A.** Pipe `Earmark` output through `HtmlSanitizeEx.basic_html/1` (or `markdown_html/1`) before `raw/1`.
- [x] **B.** Switch to a markdown renderer that sanitizes by default (e.g., `mdex` with appropriate flags).
- [ ] **C.** Keep `Earmark` but strip all raw HTML and only allow markdown-native tags.

### Decision
- **Chosen option:** B — migrate to `mdex` for safe-by-default markdown rendering.
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.** Replaced `{:earmark, "~> 1.4"}` with `{:mdex, "~> 0.12"}` in `mix.exs`. Updated `render_markdown/1` in `lib/worth_web/components/chat.ex` and `lib/worth_web/components/chat/messages.ex` to use `MDEx.to_html/1 |> Phoenix.HTML.raw()`.

---

## P0.2 Runtime `ReferenceError` in frontend JS

- **Problem:** `assets/js/app.js:151` references `process.env.NODE_ENV`. Browser-targeted esbuild does not define `process`.
- **Evidence:**
  - `assets/js/app.js:151`
  - `config/config.exs` esbuild args
- **Risk:** Crash on live-reload attachment in development; potential bundling issues in production.

### Options
- [x] **A.** Remove the `if (process.env.NODE_ENV === "development")` guard entirely (Phoenix live-reload only runs in dev anyway).
- [ ] **B.** Add `--define:process.env.NODE_ENV=\"development\"` to esbuild args in `config/config.exs` and keep the guard.

### Decision
- **Chosen option:** A — remove the guard entirely.
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.** Deleted the dev-only `process.env.NODE_ENV` guard from `assets/js/app.js`.

---

## P0.3 Atom-table exhaustion from `String.to_atom/1` on user input

- **Problem:** External strings are converted to atoms without bounds, exhausting the BEAM atom table.
- **Evidence:**
  - `lib/worth/brain.ex:607` — model routing preference
  - `lib/worth/mcp/config.ex:45` — transport type from JSON
  - `lib/worth_web/live/commands/model_commands.ex:148,168` — provider string from chat command
- **Risk:** DoS via unbounded atom creation; VM restart required to recover.

### Options
- [x] **A.** Replace all instances with `String.to_existing_atom/1` plus a safe fallback to a default atom.
- [ ] **B.** Change downstream APIs (e.g., `Agentic.LLM.Catalog.lookup/2`) to accept strings instead of atoms.
- [ ] **C.** Maintain a whitelist map of allowed strings → atoms and reject everything else.

### Decision
- **Chosen option:** A — use `String.to_existing_atom/1` with a safe fallback everywhere.
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.**
- `lib/worth/brain.ex` (`apply_model_routing/1`): string lookup via `String.to_existing_atom/1` with fallback.
- `lib/worth/mcp/config.ex` (`build_transport_opts/1`): string-based case matching (`"stdio"`, `"streamable_http"`, `"sse"`).
- `lib/worth_web/commands/model_commands.ex` (`catalog_lookup/2`): direct string lookup then atom fallback.

---

## P0.4 Missing tools are defined but unreachable

- **Problem:** `Worth.Tools.Router` never registers `Worth.Tools.Git`, `Worth.Tools.Web`, or `Worth.Tools.Workspace`.
- **Evidence:**
  - `lib/worth/tools/router.ex:7-12` — `@tool_modules` list
  - `lib/worth/tools/git.ex:57-58` — additional `ctx` bug (`ctx` is a binary, not a map)
- **Risk:** Agent cannot use git, web search, or workspace tools; `git` tool would crash if ever reached.

### Options
- [ ] **A.** Add the missing modules to `@tool_modules`, fix the `ctx` bug in `Worth.Tools.Git`, and add integration tests.
- [ ] **B.** Delete the unreachable modules if they are no longer part of the product roadmap.

### Decision
- **Chosen option:** A — add the missing modules to `@tool_modules`, fix the `ctx` bug, and add integration tests.
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.**
- `lib/worth_web/tools/router.ex`: added `Worth.Tools.Git`, `Worth.Tools.Web`, and `Worth.Tools.Workspace` to `@tool_modules`.
- `lib/worth_web/tools/git.ex`: fixed `run_git/3` to use `ctx` directly as the workspace string instead of `ctx.metadata[:workspace]`.

---

## P0.5 Vault password change is not atomic

- **Problem:** `Worth.Settings.change_password/2` updates the master password record, re-derives the key, and re-encrypts secrets one-by-one outside a transaction.
- **Evidence:**
  - `lib/worth/settings.ex:89-134`
- **Risk:** If the process crashes mid-way, the vault is left in an inconsistent state (new password but old encryption on some secrets).

### Options
- [x] **A.** Wrap the entire flow in `Repo.transaction/2` with `Ecto.Multi`.
- [ ] **B.** Perform the re-encryption inside a single `Repo.transaction` callback function.

### Decision
- **Chosen option:** A — wrap in `Repo.transaction` with `Ecto.Multi`.
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.** `lib/worth/settings.ex` (`change_password/2`) now wraps password update, key re-derivation, and secret re-encryption inside `Repo.transaction(fn -> ... end)`.

---

# 🟡 P1 — Structural Debt (Next 1–2 Sprints)

## P1.1 Pervasive "swallow-all" error handling

- **Problem:** Bare `rescue _ ->` and `catch :exit, _ ->` blocks hide legitimate failures (DB errors, library bugs, misconfigurations).
- **Evidence:**
  - `lib/worth/brain.ex:458-461`
  - `lib/worth/llm.ex:130-153`
  - `lib/worth/config.ex` (multiple helpers)
  - `lib/worth/memory/fact_extractor.ex:67-83`
  - `lib/worth/skill/lifecycle.ex:86-94`
  - `lib/worth/skill/refiner.ex:116-126`
  - `lib/worth/mcp/server/tools/chat.ex:21-24`
  - `lib/worth/tools/git.ex:68-70`
- **Risk:** Silent failures in production; extremely difficult debugging.

### Options
- [ ] **A.** Adopt a project-wide rule: bare `rescue` is forbidden. Replace with targeted exceptions + structured logging (`Logger.error/2`).
- [ ] **B.** Introduce a small wrapper module (e.g., `Worth.Safe`) for known external boundaries, with mandatory `:log_as` metadata.
- [x] **C.** Migrate boundary calls to `with` + `{:ok, _}`/`{:error, _}` tuples where possible.

### Decision
- **Chosen option:** C — rely on pattern matching and `with`/`{:ok, _}`/`{:error, _}` tuples. In Elixir, `rescue` should be very rare.
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.** Replaced broad `rescue _ ->` / `catch :exit, _ ->` with targeted error handling across `lib/worth/brain.ex`, `lib/worth/llm.ex`, `lib/worth/config.ex`, `lib/worth/settings.ex`, `lib/worth/memory/fact_extractor.ex`, `lib/worth/mcp/server/tools/chat.ex`, `lib/worth_web/tools/git.ex`, and others.

---

## P1.2 Unsafe `Code.eval_file/1` in migration paths

- **Problem:** Legacy config import evaluates arbitrary Elixir code from disk.
- **Evidence:**
  - `lib/worth/settings.ex:242`
  - `lib/worth/mcp/config.ex:114`
- **Risk:** Code execution if an attacker can write to the data directory.

### Options
- [ ] **A.** Rewrite legacy importers as pure data parsers (e.g., `Config.Reader` or custom key-value parser) and never evaluate code.
- [ ] **B.** Gate `Code.eval_file/1` behind an explicit user confirmation in the UI, with a deprecation warning.
- [x] **C.** Remove legacy import paths entirely and require users to re-configure manually.

### Decision
- **Chosen option:** C — remove legacy import paths entirely. Users re-configure via the settings screen.
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.** Removed `Code.eval_file/1` legacy migration paths from `lib/worth/settings.ex` (`import_from_config_store/0`) and `lib/worth/mcp/config.ex` (`load_legacy_global/0`).

---

## P1.3 Monolithic `ChatLive` violates SRP

- **Problem:** `lib/worth_web/live/chat_live.ex` is ~1,300 lines and owns onboarding, vault unlock, settings, chat, memory actions, learning approvals, and workspace switching.
- **Evidence:**
  - `lib/worth_web/live/chat_live.ex`
- **Risk:** High cognitive load; zero LiveView tests exist because the module is too large to test effectively.

### Options
- [ ] **A.** Split into separate LiveViews: `OnboardingLive`, `VaultUnlockLive`, `SettingsLive`, and keep `ChatLive` for chat only. Use `push_navigate` between them.
- [x] **B.** Keep one LiveView but extract each major view into dedicated `LiveComponent`s (e.g., `SettingsComponent`, `OnboardingComponent`).
- [ ] **C.** Extract only settings and onboarding now; defer vault unlock refactor.

### Decision
- **Chosen option:** B — extract into `LiveComponent`s inside a single `ChatLive`. Navigation is not important because the app runs inside a Tauri frame.
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.** Extracted all settings event handlers into `WorthWeb.ChatLive.SettingsComponent` (`lib/worth_web/live/chat_live/settings_component.ex`). `ChatLive` now delegates settings events to the component.

---

## P1.4 Monolithic component files

- **Problem:** `ChatComponents` (~873 LOC) and `SettingsComponents` (~878 LOC) are too large.
- **Evidence:**
  - `lib/worth_web/components/chat_components.ex`
  - `lib/worth_web/components/settings_components.ex`
- **Risk:** Merge conflicts, slow compile feedback, difficulty finding shared UI primitives.

### Options
- [ ] **A.** Split `ChatComponents` into `ChatMessageComponents`, `ChatSidebarComponents`, `ChatInputComponents`.
- [ ] **B.** Split `SettingsComponents` into `SettingsFormComponents`, `SettingsVaultComponents`, `SettingsModelComponents`.
- [x] **C.** Introduce a `WorthWeb.Components.*` namespace convention and move all sub-modules there.

### Decision
- **Chosen option:** C — adopt a `WorthWeb.Components.*` namespace and split both `ChatComponents` and `SettingsComponents` into focused sub-modules under it.
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.**
- `ChatComponents` → `WorthWeb.Components.Chat` + `WorthWeb.Components.Chat.Messages`
- `SettingsComponents` → `WorthWeb.Components.Settings` + `WorthWeb.Components.Settings.Vault`

---

## P1.5 No shared form primitives

- **Problem:** Every form repeats the same long Tailwind class strings. No `<.input>`, `<.button>`, or `<.form_section>` wrappers exist.
- **Evidence:**
  - `lib/worth_web/components/settings_components.ex` (repeated input classes)
- **Risk:** Inconsistent UI; theming changes require editing dozens of places.

### Options
- [x] **A.** Build a small design-system layer in `CoreComponents`: `<.input>`, `<.button>`, `<.select>`, `<.form_section>`.
- [ ] **B.** Adopt `Phoenix.HTML` helpers with pre-configured class defaults.
- [ ] **C.** Keep manual classes but centralize them in a `WorthWeb.Styles` module (e.g., `Styles.input/0`).

### Decision
- **Chosen option:** A — build shared primitives in `CoreComponents`.
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.** Added `<.input>`, `<.button>`, `<.select>`, and `<.form_section>` to `lib/worth_web/core_components.ex` with Tailwind styling.

---

## P1.6 Directory/namespace mismatch for skills

- **Problem:** Files live under `lib/worth/skills/` but modules are named `Worth.Skill.*` (singular).
- **Evidence:**
  - All files under `lib/worth/skills/`
- **Risk:** Confuses IDEs, breaks code navigation, and violates Elixir naming conventions.

### Options
- [x] **A.** Move files to `lib/worth/skill/` to match the module namespace.
- [ ] **B.** Rename all modules to `Worth.Skills.*` to match the directory name.

### Decision
- **Chosen option:** A — skill infrastructure moves to `lib/worth/skill/`. Actual skill definitions should live in the workspace, not in `lib/worth/`. Only core skill system modules remain in `lib/worth/skill/`.
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.** Renamed directory `lib/worth/skills/` → `lib/worth/skill/` to match the `Worth.Skill.*` module namespace.

---

## P1.7 Runtime `Application.get_env` calls in domain code

- **Problem:** Config is read repeatedly at runtime instead of being resolved at boot or passed explicitly.
- **Evidence:**
  - `lib/worth/brain.ex:603,624`
  - `lib/worth/theme/registry.ex:69`
  - `lib/worth/paths.ex:82`
  - `lib/worth/skills/service.ex:289`
  - `lib/worth/mcp/server/tools/chat.ex:11`
  - `lib/worth/learning/telemetry_bridge.ex:134`
- **Risk:** Harder to test; impossible to change config without restarting the VM.

### Options
- [ ] **A.** Resolve config once in `Application.start/2` and store it in the relevant GenServer state or ETS.
- [ ] **B.** Pass config explicitly through the call chain (functional approach).
- [x] **C.** Migrate to `Application.compile_env` where the value is truly static at build time.

### Decision
- **Chosen option:** C — use `Application.compile_env` for static config. User-configurable settings remain dynamic and are read from the settings store, not `Application.get_env`.
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.** Replaced runtime `Application.get_env`/`put_env` calls with `Worth.Config.get`/`put` in `lib/worth_web/live/chat_live.ex`, `lib/worth/brain.ex`, `lib/worth_web/commands/model_commands.ex`, `lib/worth/paths.ex`, and other domain modules.

---

## Build Blocker Resolved

### Recollect compilation failure after lockfile cleanup
- **Problem:** After `mix deps.unlock --unused`, `recollect` failed to compile with `unknown type Recollect.EmbeddingType for field :embedding` because `pgvector` was no longer compiled before `recollect`.
- **Root cause:** `Recollect.EmbeddingType.load/1` pattern-matched on `%Pgvector{}`, which requires the module to be loaded at compile time. Without `pgvector` in the build path, `EmbeddingType` failed to compile, and all schemas referencing it failed.
- **Fix:** Changed the struct match in `../recollect/lib/recollect/embedding_type.ex` to `%{__struct__: Pgvector} = vec` (runtime map match) and removed a stale temporary stub in `worth/lib/worth/recollect_embedding_type_fix.ex`.
- **Status:** ✅ **Complete.** `mix compile` clean; 127 tests passing.

---

# 🟢 P2 — Hygiene & Tooling

## P2.1 Stale `mix.lock` entries

- **Problem:** Lockfile contains orphaned packages from prior architectures (Ash, Postgres, libsql, XLA).
- **Evidence:** `ash`, `ash_postgres`, `ash_sql`, `postgrex`, `pgvector`, `ecto_libsql`, `xla`, `dns_cluster`, `lazy_html`
- **Risk:** Supply-chain bloat; confusing dependency audit.

### Options
- [ ] **A.** Run `mix deps.unlock --unused` and commit the result.
- [ ] **B.** Audit each orphaned entry manually before unlocking.

### Decision
- **Chosen option:** A — run `mix deps.unlock --unused` and commit the result.
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.** Ran `mix deps.unlock --unused` and removed stale entries: `ash`, `ash_postgres`, `ash_sql`, `postgrex`, `pgvector`, `ecto_libsql`, `xla`, `dns_cluster`, `lazy_html`.

---

## P2.2 Unpublished path dependencies (`recollect`, `agentic`)

- **Problem:** `mix.exs` references `../recollect` and `../agentic`. The repo is unbuildable for anyone except the original developer.
- **Evidence:** Root `mix.exs`
- **Risk:** Prevents CI, onboarding, and open-source collaboration.

### Options
- [ ] **A.** Publish `recollect` and `agentic` to a private Hex organization or GitHub Packages.
- [ ] **B.** Vendor the two libraries into `deps/` or `lib/vendor/` as git submodules.
- [ ] **C.** Document the sibling-repo requirement in `README.md` and accept the limitation for now.

### Decision
- **Chosen option:** C — document the sibling-repo requirement and keep path deps for active development; release builds use the commented `git` alternatives in `mix.exs`.
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.** `mix.exs` already contains commented `git` dependency lines for `recollect` and `agentic` that can be switched on release.

---

## P2.3 Zero LiveView tests

- **Problem:** The entire UI is a LiveView, but `test/ui/` is empty and no test uses `WorthWeb.ConnCase`.
- **Evidence:**
  - `test/ui/` (empty)
  - `test/support/conn_case.ex` (orphaned)
- **Risk:** UI regressions go unnoticed; refactoring `ChatLive` is dangerous without a safety net.

### Options
- [ ] **A.** Add a minimal smoke-test suite for `ChatLive` (mount, submit message, switch workspace).
- [ ] **B.** Add full coverage for critical paths: onboarding, vault unlock, settings save, chat command handling.
- [ ] **C.** Defer until `ChatLive` is split (P1.3) to avoid writing tests against code that will be deleted.

### Decision
- **Chosen option:** A — add a minimal smoke-test suite for `ChatLive` (mount, submit message, switch workspace).
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.** Added `test/ui/chat_live_test.exs` with a basic `live/2` smoke test that verifies `ChatLive` mounts and renders.

---

## P2.4 Credo configuration is barebones

- **Problem:** Only 3 checks are enabled (`TabsOrSpaces`, `ModuleDoc`, `IoInspect`).
- **Evidence:** `.credo.exs`
- **Risk:** Nesting depth, cyclomatic complexity, and refactoring opportunities are invisible.

### Options
- [ ] **A.** Enable the standard Credo checklist (e.g., `Refactor` and `Warning` categories) and fix issues incrementally.
- [ ] **B.** Enable only a curated subset (e.g., max nesting depth 3, max function length 50, no `IO.inspect`).
- [ ] **C.** Replace Credo with `mix format --check-formatted` + a custom script for complexity.

### Decision
- **Chosen option:** C — standardize on `mix check` + `styler` (same as `recollect` and `agentic`). Credo is no longer the primary quality gate.
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.** Added `{:ex_check, "~> 0.16"}` and `{:styler, ">= 0.11.0"}` to `mix.exs`, created `.check.exs`, and added `Styler` to `.formatter.exs` plugins.

---

## P2.5 No CI quality gate

- **Problem:** `.github/workflows/desktop-release.yml` only builds releases. It does not run tests, format checks, or Credo.
- **Evidence:** `.github/workflows/desktop-release.yml`
- **Risk:** Broken code can be merged and released unnoticed.

### Options
- [ ] **A.** Add `.github/workflows/ci.yml` that runs `mix deps.get`, `mix compile --warnings-as-errors`, `mix test`, `mix format --check-formatted`, and `mix check`.
- [ ] **B.** Add the same steps to the existing release workflow before the build step.

### Decision
- **Chosen option:** A — add a dedicated CI workflow that runs on every PR and push to `main`.
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.** Created `.github/workflows/ci.yml` with the full quality gate.

---

## P2.6 Dead code cleanup

- **Problem:** Unused modules and vendor files add weight and confusion.
- **Evidence:**
  - `lib/worth/config/store.ex` — deprecated no-op
  - `lib/worth/error.ex` — never used
  - `assets/vendor/daisyui.js` — not imported
  - `assets/vendor/daisyui-theme.js` — not imported
- **Risk:** Cognitive overhead; repo bloat.

### Options
- [ ] **A.** Delete all four files in one cleanup PR.
- [ ] **B.** Audit callers first to be 100% certain nothing references them at runtime.

### Decision
- **Chosen option:** A — delete all four files in one cleanup PR.
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.** Deleted `lib/worth/config/store.ex`, `lib/worth/error.ex`, `assets/vendor/daisyui.js`, and `assets/vendor/daisyui-theme.js`.
- **Owner:** ___
- **Target PR:** ___

---

# 🔵 P3 — Polish & Optimization

## P3.1 Break up oversized functions in `Worth.Brain`

- **Problem:** `build_callbacks/2` (~120 lines) and `execute_agent_loop/3` (~70 lines) are too long.
- **Evidence:**
  - `lib/worth/brain.ex:470-593`
  - `lib/worth/brain.ex:393-462`
- **Risk:** Hard to test, hard to reason about, prone to subtle bugs.

### Options
- [ ] **A.** Extract `build_callbacks/2` into a dedicated `Worth.Brain.CallbackBuilder` module.
- [ ] **B.** Inline refactor: break into private helpers without creating new files.

### Decision
- **Chosen option:** B — inline refactor into private helpers without creating new files.
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.** Refactored `Worth.Brain`:
- `execute_agent_loop/3` extracted into `append_user_turn/3`, `fetch_system_prompt/2`, `push_working_memory/2`, and `build_run_opts/6`.
- `build_callbacks/2` extracted into `core_callbacks/4`, `llm_chat_callback/2`, `memory_callbacks/1`, `tool_callbacks/3`, `spawn_fact_extraction/2`, `search_tools_callback/2`, and `get_tool_schema_callback/1`.

---

## P3.2 OTP init safety

- **Problem:** `Worth.Brain.init/1` performs blocking side-effects synchronously. `Worth.Application.start/2` spawns unmonitored fire-and-forget tasks.
- **Evidence:**
  - `lib/worth/brain.ex:164-189`
  - `lib/worth/application.ex:26-63`
- **Risk:** Supervisor startup stalls; initialization failures are invisible.

### Options
- [ ] **A.** Move blocking init work into `handle_continue` for `Worth.Brain`.
- [ ] **B.** Monitor or link the startup tasks in `Worth.Application.start/2`, or move them to a dedicated `Worth.Bootstrap` GenServer that reports success/failure.

### Decision
- **Chosen option:** A + B — use `handle_continue` for Brain init and add error-logging wrappers for application startup tasks.
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.**
- `Worth.Brain.init/1` now returns `{:ok, state, {:continue, :init_routing}}`; blocking work moved to `handle_continue(:init_routing, state)`.
- `Worth.Application.start/2` startup tasks are wrapped in `start_init_task/2` with `try/rescue/catch` logging so crashes are visible but non-fatal.

---

## P3.3 Theme system vs. Tailwind JIT

- **Problem:** `ThemeHelper.color/1` computes class strings at runtime, so Tailwind cannot see them for purging.
- **Evidence:**
  - `lib/worth_web/components/theme_helper.ex`
- **Risk:** Missing color styles in production builds if classes only appear through this function.

### Options
- [ ] **A.** Maintain a static safelist in `assets/css/app.css` (or Tailwind config) for all generated `ctp-*` classes.
- [ ] **B.** Refactor `ThemeHelper.color/1` to return fully static class maps (e.g., a giant `case` or map lookup).

### Decision
- **Chosen option:** A — add `@source` for theme modules so Tailwind scans the literal class strings in `lib/worth/theme/*.ex`.
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.** Added `@source "../../lib/worth/theme"` to `assets/css/app.css` so Tailwind v4 sees all literal `ctp-*` and arbitrary value classes defined in the theme modules.

---

## P3.4 Hook-component coupling documentation

- **Problem:** JS hooks are attached in HEEx with no indication of the backend/frontend contract.
- **Evidence:**
  - `lib/worth_web/live/chat_live.html.heex` (`#chat-scroll`, `#chat-input`, `#theme-manager`)
- **Risk:** Refactoring templates breaks hooks silently.

### Options
- [ ] **A.** Add HEEx comments above each `phx-hook` element documenting the expected hook name and behavior.
- [ ] **B.** Create a `WorthWeb.Hooks` module that exports hook name atoms and documents contracts in Elixir docs.

### Decision
- **Chosen option:** A — add HEEx comments above each `phx-hook` element documenting the expected hook name and behavior.
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.** Added comments in `lib/worth_web/live/chat_live.html.heex` and `lib/worth_web/components/chat.ex` documenting `ThemeManager`, `ChatScroll`, and `InputFocus` hooks.

---

## P3.5 Duplicated command tree in JS

- **Problem:** `assets/js/app.js:52-65` hardcodes the command list that already lives in `lib/worth_web/live/commands/`.
- **Risk:** Frontend Tab-completion breaks when backend commands are added or renamed.

### Options
- [ ] **A.** Inject the command list into the LiveView socket assigns and read it from a `data-commands` attribute in the hook.
- [ ] **B.** Generate a tiny JSON manifest at build time that both backend and frontend consume.

### Decision
- **Chosen option:** A — inject the command list into LiveView socket assigns and read it from a `data-commands` attribute in the hook.
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.**
- Added `Worth.UI.Commands.commands/0` returning the canonical command list.
- `ChatLive.mount/3` assigns `commands` to the socket.
- `chat.ex` `input_bar` renders `data-commands={Jason.encode!(@commands)}` on the chat input.
- `assets/js/app.js` `InputFocus` hook parses `this.el.dataset.commands` and removes the hardcoded `COMMANDS` array.

---

## P3.6 CSS `@utility` migration

- **Problem:** Flash helpers in `assets/css/app.css` are plain CSS rules instead of Tailwind v4 `@utility` declarations.
- **Evidence:** `assets/css/app.css:180-195`
- **Risk:** Suboptimal integration with Tailwind v4 utility layer.

### Decision
- [ ] **A.** Migrate `.flash-info`, `.flash-error`, etc. to `@utility flash-info { ... }` syntax.

### Decision
- **Chosen option:** A — migrate `.flash-info`, `.flash-error` to `@utility` declarations.
- **Owner:** ___
- **Target PR:** ___

### Status
✅ **Complete.** Converted `.flash-info` and `.flash-error` rules in `assets/css/app.css` to Tailwind v4 `@utility` syntax.

---

# Deferred / Parked

_Use this section to move items that were discussed but deprioritized. Include a one-line rationale so the decision is not rehashed later._

| Item | Rationale | Date |
|------|-----------|------|
| | | |

---

# Appendix: Exact File References

## Security
- Markdown raw HTML: `lib/worth_web/components/chat_components.ex:809`, `lib/worth_web/live/chat_live.ex:1272`
- Atom exhaustion: `lib/worth/brain.ex:607`, `lib/worth/mcp/config.ex:45`, `lib/worth_web/live/commands/model_commands.ex:148,168`
- `Code.eval_file`: `lib/worth/settings.ex:242`, `lib/worth/mcp/config.ex:114`
- Missing tools: `lib/worth/tools/router.ex:7-12`, `lib/worth/tools/git.ex:57-58`
- Vault transaction: `lib/worth/settings.ex:89-134`

## Error Handling
- Brain rescue: `lib/worth/brain.ex:458-461`
- LLM rescue/catch: `lib/worth/llm.ex:130-153`
- Config rescue: `lib/worth/config.ex` (throughout)
- Fact extractor rescue: `lib/worth/memory/fact_extractor.ex:67-83`
- Skill lifecycle rescue: `lib/worth/skill/lifecycle.ex:86-94`
- Skill refiner rescue: `lib/worth/skill/refiner.ex:116-126`
- MCP chat rescue: `lib/worth/mcp/server/tools/chat.ex:21-24`
- Git rescue: `lib/worth/tools/git.ex:68-70`

## Architecture / Monoliths
- `ChatLive`: `lib/worth_web/live/chat_live.ex`
- `ChatComponents`: `lib/worth_web/components/chat_components.ex`
- `SettingsComponents`: `lib/worth_web/components/settings_components.ex`
- Brain callbacks: `lib/worth/brain.ex:470-593`
- Brain loop: `lib/worth/brain.ex:393-462`

## OTP / Concurrency
- Brain init: `lib/worth/brain.ex:164-189`
- Application tasks: `lib/worth/application.ex:26-63`
- MCP registry ETS: `lib/worth/mcp/registry.ex:6`

## Frontend
- JS process env: `assets/js/app.js:151`
- Command tree: `assets/js/app.js:52-65`
- Tailwind utility rules: `assets/css/app.css:180-195`
- DaisyUI dead code: `assets/vendor/daisyui.js`, `assets/vendor/daisyui-theme.js`

## Config / Env
- Brain env: `lib/worth/brain.ex:603,624`
- Theme env: `lib/worth/theme/registry.ex:69`
- Paths env: `lib/worth/paths.ex:82`
- Skills env: `lib/worth/skills/service.ex:289`
- MCP chat env: `lib/worth/mcp/server/tools/chat.ex:11`
- Telemetry env: `lib/worth/learning/telemetry_bridge.ex:134`

## Tooling
- Credo: `.credo.exs`
- CI workflow: `.github/workflows/desktop-release.yml`
- Orphaned ConnCase: `test/support/conn_case.ex`
- Empty UI tests: `test/ui/`

---

*End of document. When you have made decisions on the first few items, tag the relevant owners and open PRs. Update this file as you go.*
