# Worth Desktop Distribution — Implementation Plan

**Status:** IN PROGRESS
**Source:** Revised from `tauri-desktop-app.md` proposal
**Last updated:** 2026-04-11

## Key Decisions

- **Git deps with tags** for `agent_ex` and `mneme` — keeps them in sync across all projects that use them
- **libSQL only** — PostgreSQL support removed from Worth (mneme retains Postgres for server deployments)
- **No ElixirKit** — direct TCP PubSub between Rust and Elixir (simpler, fewer deps)
- **Feature-flagged** via `WORTH_DESKTOP=1` env var — web/CLI path is untouched
- **Unused deps removed** — ash, ash_postgres, dns_cluster, owl, lazy_html all removed

---

## Phase 0: Prerequisites

### 0.1 Convert `agent_ex` and `mneme` to git dependencies
- [x] Verify git repos have tags (`agent_ex` → `v0.1.1`, `mneme` → `v0.2.0`)
- [x] Push tags to remote (`git push origin v0.x.x` in each repo)
- [x] Update `mix.exs` to use `git:` + `tag:` instead of `path:`
- [x] Add `override: true` on mneme dep (agent_ex also depends on mneme via path)
- [x] Verify `mix deps.get` and `mix compile` still work

### 0.2 Add release configuration
- [x] Add `:releases` key to `mix.exs` (worth + desktop release configs)
- [x] Create `rel/env.sh.eex` with desktop-specific env vars
- [x] Create `rel/vm.args.eex` (minimal, no distribution)
- [x] Move mneme anonymous function config to module capture (`&Worth.Memory.Embeddings.Adapter.credentials/0`)
- [x] Verify `MIX_ENV=prod mix release worth` produces artifact (92MB)

### 0.3 Desktop-specific runtime config
- [x] Rewrite `config/runtime.exs` with `WORTH_DESKTOP=1` branch
- [x] Desktop: bind to `127.0.0.1`, auto-generate `SECRET_KEY_BASE`, `server: true`
- [x] Server: existing `0.0.0.0` bind + required `SECRET_KEY_BASE` env var

### 0.4 Refactor CLI to separate server start from browser open
- [x] Create `lib/worth/boot.ex` — `Worth.Boot.run/1` starts app and returns URL
- [x] Add `--no-open` / `-n` flag to CLI
- [x] `Worth.CLI` calls `Worth.Boot` then conditionally opens browser

### 0.5 Auto-migrate on boot for libSQL
- [x] `Worth.Boot.run_migrations!/0` runs `Ecto.Migrator.run` when `WORTH_DESKTOP=1` or `WORTH_AUTO_MIGRATE=1`
- [x] Creates `~/.worth/` directory and DB file path on boot

### 0.6 Remove PostgreSQL from Worth
- [x] Removed postgrex, ash, ash_postgres as direct deps
- [x] Deleted `Worth.PostgrexTypes` and `Mix.Tasks.Worth.MigrateToLibSQL`
- [x] Simplified `Worth.Repo` to hardcoded libSQL adapter
- [x] Cleaned all config files of postgres conditional branches
- [x] pgvector stays as transitive dep (required by mneme schemas)

---

## Phase 1: OTP Release Validation
- [x] Build: `MIX_ENV=prod mix release worth --overwrite` succeeds
- [x] Release size: 92MB uncompressed
- [x] env.sh correctly generated with desktop mode branching
- [ ] Start release on clean machine / Docker (no Elixir, no PostgreSQL) — manual test needed

---

## Phase 2: Tauri Scaffold + Integration

### 2.1 Project structure
- [x] Create `rel/desktop/` directory
- [x] Create `rel/desktop/src-tauri/Cargo.toml` with deps
- [x] Create `rel/desktop/src-tauri/tauri.conf.json`
- [x] Create splash screen (`dist/index.html`) with spinner + branding
- [x] Create `rel/desktop/src-tauri/build.rs`
- [x] Create `rel/desktop/src-tauri/icons/` (hand-crafted SVG, all sizes)

### 2.2 Rust side (`src-tauri/src/`)
- [x] `main.rs` — entry point
- [x] `lib.rs` — OTP lifecycle: find port, spawn release, splash → main window, tray menu
- [x] System tray (Open / Quit) — single icon with menu
- [x] Single instance enforcement (`tauri-plugin-single-instance`)
- [x] Graceful shutdown (kill OTP child on exit)
- [x] TCP PubSub server (starts listener, passes `WORTH_PUBSUB` to OTP, receives `ready`/`shutdown` frames)
- [x] Crash reporter (show dialog on OTP crash or startup timeout)
- [x] Window close hides to tray (OTP keeps running)
- [x] App compiles and launches successfully — web UI loads in Tauri window
- [x] Auto-migrations run on first boot (libSQL)

### 2.3 Rust hardening
- [x] Replaced all `.unwrap()` with proper error handling (`let Ok(...) = ... else { ... }`)
- [x] Added `MAX_FRAME_SIZE` (1MB) to prevent memory exhaustion from malformed frames
- [x] URL parsing uses `match` with error dialog instead of `unwrap()`
- [x] Monitor interval reduced from 5s to 1s
- [x] CSP header set (restrict to self + localhost)
- [x] Fixed duplicate tray icon issue (removed `trayIcon` from tauri.conf.json)
- [x] `find_available_port()` returns `Result` instead of panicking

### 2.4 Elixir side (`lib/worth/desktop/`)
- [x] `bridge.ex` — TCP PubSub client (connects to `WORTH_PUBSUB` env var)
- [x] Broadcasts `ready:<url>` after endpoint starts
- [x] Listens for `quit` → `System.stop()`
- [x] Broadcasts `shutdown` on application stop
- [x] Hooked into supervision tree (only starts when `WORTH_DESKTOP=1`)
- [x] Connection retry loop (30 retries, 1s interval)
- [x] Frame buffering for partial TCP reads
- [x] Proper Logger usage (replaced IO.warn)
- [x] PubSub address validation (parse_pubsub_address/1)
- [x] Warning logged when messages dropped due to missing socket

### 2.5 UI integration
- [x] Quit button in header (top-right, desktop mode only, with confirmation)
- [x] `desktop_mode` assign in ChatLive

### 2.6 Build orchestration
- [x] Create `rel/desktop/tauri.sh` build script
- [x] Subcommands: `release`, `tauri`, `build`, `dev`
- [x] `tauri_build` copies OTP release into `src-tauri/rel/` for Tauri resource bundling
- [x] `tauri.conf.json` resources config bundles `rel/**/*`
- [x] End-to-end build tested successfully (Linux x86_64)

---

## Phase 3: Build Pipeline + CI
- [ ] GitHub Actions workflow for 4 platforms
- [ ] macOS ARM64 (`.dmg`, `.app`)
- [ ] macOS x86_64 (`.dmg`, `.app`)
- [ ] Linux x86_64 (`.AppImage`, `.deb`)
- [ ] Windows x86_64 (`.exe` NSIS installer)
- [ ] Upload artifacts to GitHub Releases
- [ ] No PostgreSQL needed in CI (libSQL is embedded)

---

## Phase 4: Polish
- [x] App icons: hand-crafted SVG with stylized W + blue-purple gradient, converted to `.icns` (290KB), `.ico` (335KB), `.png` (32/128/256/512)
- [x] Slogan: "Your ideas are WORTH more" — added to splash screen, empty chat state, CLI help
- [x] System tray menu (Open Worth, Quit) — Rust side done
- [x] Single instance enforcement (`tauri-plugin-single-instance`) — Rust side done
- [x] Window close → hide to tray, tray Quit → full shutdown
- [ ] Auto-update setup (`tauri-plugin-updater`, defer code signing)
- [ ] Deep linking (`worth://` URL scheme) — optional

---

## Phase 5: Distribution
- [ ] GitHub Releases with platform artifacts
- [ ] Linux install script (`curl | chmod`)
- [ ] Homebrew Cask (macOS) — later
- [ ] Windows installer signing — later

---

## Files Changed

| File | Action |
|------|--------|
| `mix.exs` | Updated: git deps, releases config, removed ash/postgrex/dns_cluster/owl/lazy_html |
| `config/config.exs` | Updated: libSQL-only, removed postgres branches |
| `config/runtime.exs` | Updated: removed dns_cluster_query |
| `config/dev.exs` | Updated: removed postgres comment |
| `rel/env.sh.eex` | Updated: removed WORTH_DATABASE_BACKEND logic |
| `lib/worth/boot.ex` | Created: server start logic extracted from CLI |
| `lib/worth/cli.ex` | Updated: uses Worth.Boot, added --no-open |
| `lib/worth/repo.ex` | Simplified: libSQL-only, no compile-time conditional |
| `lib/worth/postgrex_types.ex` | Deleted |
| `lib/mix/tasks/worth.migrate_to_libsql.ex` | Deleted |
| `lib/worth/desktop/bridge.ex` | Updated: Logger, address validation, error handling |
| `lib/worth/application.ex` | Updated: added Desktop.Bridge to children, ready broadcast |
| `lib/worth_web/live/chat_live.ex` | Updated: desktop_mode assign, quit_app event handler |
| `lib/worth_web/live/chat_live.html.heex` | Updated: pass desktop_mode to header |
| `lib/worth_web/components/chat_components.ex` | Updated: quit button in header |
| `rel/desktop/src-tauri/Cargo.toml` | Created |
| `rel/desktop/src-tauri/tauri.conf.json` | Updated: CSP set, trayIcon removed |
| `rel/desktop/src-tauri/src/main.rs` | Created |
| `rel/desktop/src-tauri/src/lib.rs` | Updated: error handling, frame limits, monitor interval |
| `rel/desktop/src-tauri/build.rs` | Created |
| `rel/desktop/src-tauri/dist/index.html` | Updated: splash screen with spinner + branding |
| `rel/desktop/src-tauri/icons/*` | Created: icon.svg, icon.png, icon.icns, icon.ico, 32/128/256 PNGs |
| `rel/desktop/tauri.sh` | Created |
| `.github/workflows/desktop-release.yml` | Created: CI for 4 platforms |
| `scripts/install.sh` | Created: Linux install script |

---

## Progress Log

| Date | Phase | What was done |
|------|-------|---------------|
| 2026-04-10 | 0.1-0.6 | Prerequisites: git deps, release config, runtime config, CLI refactor, auto-migrate |
| 2026-04-10 | 1 | OTP release validation (92MB, env.sh works) |
| 2026-04-10 | 2.1-2.4 | Tauri scaffold, Rust/Elixir bridge, build orchestration |
| 2026-04-10 | 4 | Icons, slogan, tray menu, single instance, hide-to-tray |
| 2026-04-11 | 2.2-2.4 | Rewrote Rust TCP PubSub, Elixir bridge retry/buffering, build pipeline fixes |
| 2026-04-11 | 2.3 | Rust hardening: error handling, frame limits, CSP, monitor interval, tray icon fix |
| 2026-04-11 | 2.4 | Bridge hardening: Logger, address validation, error logging |
| 2026-04-11 | 2.5 | Quit button in header (desktop mode only) |
| 2026-04-11 | 0.6 | Removed PostgreSQL: postgrex, ash, ash_postgres, PostgrexTypes, migration task |
| 2026-04-11 | — | Removed unused deps: dns_cluster, owl, lazy_html |
| 2026-04-11 | — | Updated splash screen with proper loading indicator |
