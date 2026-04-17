# Proposal: Worth Desktop App via Tauri 2

## Status: IMPLEMENTED (see desktop-distribution-plan.md for details)

## Problem

Worth is a Phoenix LiveView web app currently launched via `mix worth` or `mix run --no-halt`, which starts the BEAM VM, boots the supervision tree, and opens a browser to `localhost:4000`. There is no way to distribute Worth as a self-contained desktop application. Users must have Elixir/OTP installed and clone the repo (plus sibling repos `recollect` and `agentic`).

## Goal

Ship Worth as a native desktop application (`Worth.app` / `worth.exe` / `worth.AppImage`) that:

- Opens a native window with the Phoenix web UI inside a system webview
- Requires no Elixir/OTP installation on the target machine
- Supports macOS, Linux, and Windows
- Includes auto-update, system tray, and single-instance enforcement

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Tauri (Rust)                                       │
│  ┌──────────────┐  ┌────────────┐  ┌────────────┐  │
│  │  Webview     │  │ System Tray│  │  Updater   │  │
│  │  (system     │  │  + Menu    │  │  (future)  │  │
│  │   webview)   │  │            │  │            │  │
│  └──────┬───────┘  └────────────┘  └────────────┘  │
│         │  loads http://127.0.0.1:<port>/           │
│         │                                           │
│  ┌──────┴───────────────────────────────────────┐   │
│  │  Direct TCP PubSub (custom binary protocol)  │   │
│  │  coord: "ready:<url>", "open:<path>"         │   │
│  └──────┬───────────────────────────────────────┘   │
│         │  spawns as child process                  │
│  ┌──────┴───────────────────────────────────────┐   │
│  │  OTP Release (mix release desktop)            │   │
│  │  Worth.Bandit → localhost:<port>              │   │
│  │  WorthWeb.Endpoint → Phoenix LiveView         │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

**Note:** The original proposal suggested using ElixirKit for the Rust↔Elixir bridge. The implementation uses a simpler direct TCP protocol instead — fewer dependencies, same functionality.

## Implementation Decisions

### Resolved differently from proposal

| Proposal | Actual | Why |
|----------|--------|-----|
| ElixirKit for PubSub | Direct TCP (custom binary protocol) | Simpler, fewer deps, full control |
| PostgreSQL support kept for server deployments | PostgreSQL removed entirely | Worth is desktop-first; recollect retains Postgres for its own server use |
| `"csp": null` | CSP set to restrict to self + localhost | Security hardening |
| Tray: Open, Quit, Settings | Tray: Open, Quit | Settings accessible from web UI |
| `tauri-plugin-deep-link` | Not yet added | Deferred to future |
| `tauri-plugin-updater` | Not yet added | Deferred to future |

### Database

Worth uses **libSQL (SQLite) exclusively**. No PostgreSQL server needed. The database lives at `~/.worth/worth.db` and auto-migrates on desktop boot. The `pgvector` dependency remains as a transitive dep required by recollect schemas.

## Implementation Status

See `desktop-distribution-plan.md` for detailed checklist. Summary:

- **Phase 0 (Prerequisites):** Complete
- **Phase 1 (OTP Release):** Complete
- **Phase 2 (Tauri + Integration):** Complete including hardening
- **Phase 3 (CI):** In progress
- **Phase 4 (Polish):** Mostly complete (auto-update and deep linking deferred)
- **Phase 5 (Distribution):** In progress

## Effort Estimate (revised)

| Phase | Description | Days | Status |
|-------|-------------|------|--------|
| 0 | Prerequisites | 1-2 | Done |
| 1 | Tauri scaffold + integration | 2-3 | Done |
| 2 | Build pipeline + CI | 1-2 | In progress |
| 3 | Polish (icons, tray, etc.) | 1-2 | Mostly done |
| 4 | Distribution (releases, scripts) | 1 | In progress |
| **Total** | | **6-10 days** | |

## What This Does NOT Change

- Worth's Phoenix web UI remains unchanged
- The supervision tree and Brain architecture are untouched
- Development workflow (`mix phx.server`, `mix test`) is unchanged
- The `mix worth` CLI continues to work as before
- All existing LiveView, PubSub, and WebSocket communication stays the same

The Tauri layer is purely a **wrapper** that replaces "open browser" with "open webview window."
