# Proposal: Worth Desktop App via Tauri 2

## Status: DRAFT

## Problem

Worth is a Phoenix LiveView web app currently launched via `mix worth` or `mix run --no-halt`, which starts the BEAM VM, boots the supervision tree, and opens a browser to `localhost:4000`. There is no way to distribute Worth as a self-contained desktop application. Users must have Elixir/OTP installed and clone the repo (plus sibling repos `mneme` and `agent_ex`).

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
│  │  (system     │  │  + Menu    │  │            │  │
│  │   webview)   │  │            │  │            │  │
│  └──────┬───────┘  └────────────┘  └────────────┘  │
│         │  loads http://127.0.0.1:<port>/           │
│         │                                           │
│  ┌──────┴───────────────────────────────────────┐   │
│  │  ElixirKit PubSub (TCP on random port)       │   │
│  │  coord: "ready:<url>", "open:<path>"        │   │
│  └──────┬───────────────────────────────────────┘   │
│         │  spawns as child process                  │
│  ┌──────┴───────────────────────────────────────┐   │
│  │  OTP Release (mix release)                    │   │
│  │  Worth.Bandit → localhost:<port>              │   │
│  │  WorthWeb.Endpoint → Phoenix LiveView         │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

This is the same pattern Livebook uses: **Rust owns the window lifecycle, Elixir owns the HTTP server**, coordinated via a TCP PubSub protocol.

## Implementation Strategy

### Phase 0: Prerequisites (1-2 days)

These must be resolved before any desktop packaging is possible.

#### 0.1 Resolve path dependencies

`mneme` and `agent_ex` are path deps (`../mneme`, `../agent_ex`). A release cannot include path deps outside the project. Options:

| Option | Effort | Tradeoff |
|--------|--------|----------|
| Convert to Hex packages | Medium | Requires publishing to private or public Hex. Clean separation. |
| Monorepo (move into `deps/` or subdirectories) | Low | Simplest. Mix supports `path: "deps/mneme"` but it's unusual. |
| Git deps with tagged releases | Low | Change `path:` to `git:` + `tag:`. Works with `mix release`. |

**Chosen:** Git deps with tags. When adding new functionality to `mneme` or `agent_ex`, a new git tag must be created so that Worth's `mix.exs` can reference a specific version. Hex packages later if needed.

#### 0.2 Add release configuration

No `rel/` directory or `:releases` key exists in `mix.exs`. Need:

- `rel/` directory with `env.sh.eex` and `vm.args.eex`
- Set `RELEASE_DISTRIBUTION=none` (no clustering for desktop app)
- Set `RELEASE_MODE=interactive`
- Pin OTP version requirement in `mix.exs`

#### 0.3 Bind to localhost in production

Currently `config/runtime.exs` binds to `{0, 0, 0, 0, 0, 0, 0, 0}` in prod. For a desktop app, bind to `127.0.0.1` only. The `force_ssl` exclusion for localhost in `prod.exs` is already correct.

#### 0.4 Strip the CLI browser opener

`Worth.CLI.start_worth/1` currently calls `open_browser(url)` and then `Process.sleep(:infinity)`. In the Tauri context, the Rust side manages the window. The Elixir side should:

- Start the HTTP server on a known port (or dynamically assigned)
- Signal readiness via the PubSub bridge (not by opening a browser)
- Accept a shutdown signal from the PubSub bridge

### Phase 1: Tauri Scaffold (2-3 days)

Create the Tauri wrapper project inside Worth.

#### 1.1 Project structure

```
worth/
  rel/
    desktop/                    # Tauri project root
      src-tauri/
        Cargo.toml              # Rust dependencies
        tauri.conf.json         # Tauri window/app config
        src/
          main.rs               # Entry point
          lib.rs                # OTP lifecycle management
        icons/                  # App icons (macOS .icns, Windows .ico, Linux .png)
        rel/                    # OTP release gets copied here at build time
      tauri.sh                  # Build orchestration script
  lib/
    worth/
      desktop/                  # Elixir-side bridge
        pubsub.ex               # ElixirKit PubSub client
        bridge.ex               # Coordinator: ready signal, URL broadcast
```

#### 1.2 Rust side (`src-tauri/src/lib.rs`)

Responsibilities:
1. Show splash screen window immediately (static HTML/CSS loading indicator)
2. Start ElixirKit PubSub TCP listener on random port (`127.0.0.1:0`)
3. Spawn OTP release as child process, passing `WORTH_PUBSUB=tcp://127.0.0.1:<port>`
4. Wait for `ready:http://127.0.0.1:<port>` message from Elixir
5. Replace splash screen with main webview window pointing to the received URL
6. Manage tray menu (Open, Quit, Settings)
7. On quit: terminate child process gracefully, then exit
8. On OTP crash: show error dialog on splash screen, exit

Debug mode: run `mix phx.server` instead of release.
Release mode: run `<rel_dir>/bin/worth start`.

#### 1.3 Elixir side (`lib/worth/desktop/`)

Responsibilities:
1. Connect to PubSub TCP port from `WORTH_PUBSUB` env var
2. After endpoint starts, broadcast `ready:http://127.0.0.1:<port>`
3. Listen for `open:<path>` messages (navigate webview, open external browser)
4. Listen for `quit` messages (call `System.stop()`)
5. Subscribe to OTP PubSub shutdown and signal Rust

#### 1.4 Tauri configuration (`tauri.conf.json`)

```json
{
  "productName": "Worth",
  "identifier": "ai.worth.app",
  "build": {
    "beforeBuildCommand": "",
    "beforeBundleCommand": "../tauri.sh bundle"
  },
  "app": {
    "withGlobalTauri": false,
    "windows": [
      {
        "label": "splash",
        "title": "Worth",
        "url": "splash.html",
        "width": 480,
        "height": 320,
        "resizable": false,
        "decorations": false,
        "center": true
      }
    ],
    "security": {
      "csp": null
    }
  },
  "bundle": {
    "active": true,
    "targets": ["dmg", "app", "nsis", "appimage", "deb"],
    "icon": ["icons/icon.png"],
    "resources": {}
  }
}
```

The splash screen is a minimal native window (no decorations, centered, fixed size) showing a static loading state. It is replaced by the main webview window once Elixir signals readiness. The splash HTML lives at `src-tauri/splash.html` and uses the app's icon + a simple CSS spinner.

### Phase 2: ElixirKit Integration (2-3 days)

Use the [ElixirKit](https://github.com/livebook-dev/elixirkit) library for the Rust↔Elixir bridge.

#### 2.1 Rust dependency (`Cargo.toml`)

```toml
[dependencies]
elixirkit = "0.1"
tauri = { version = "2", features = ["tray-icon"] }
tauri-plugin-single-instance = "2"
tauri-plugin-deep-link = "2"
tauri-plugin-updater = "2"
tauri-plugin-dialog = "2"
tauri-plugin-clipboard-manager = "2"
```

#### 2.2 Elixir dependency

```elixir
{:elixirkit, "~> 0.1"}
```

#### 2.3 PubSub protocol

The TCP protocol is simple (4-byte length-prefixed frames):

```
[4 bytes: frame length BE u32]
[1 byte: topic length]
[N bytes: topic]
[remaining: payload]
```

Key messages:
- **Elixir → Rust**: `ready:http://127.0.0.1:<port>` — server is up, create window
- **Rust → Elixir**: `open:<path>` — navigate webview to path or open external
- **Rust → Elixir**: `quit` — graceful shutdown

#### 2.4 Port discovery

Two options:

| Option | How | Pros | Cons |
|--------|-----|------|------|
| Fixed port | Hardcode `WORTH_PORT=45678` in env.sh.eex | Simple, predictable | Port conflicts possible |
| Dynamic port | Read port from Endpoint after start | No conflicts | Slightly more complex |

**Recommended:** Dynamic. Read the actual port from `WorthWeb.Endpoint` config after the supervision tree starts, then broadcast it.

### Phase 3: Build Pipeline (2-3 days)

#### 3.1 Build script (`rel/desktop/tauri.sh`)

Orchestration:

```bash
#!/usr/bin/env bash
set -euo pipefail

MIX_PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TAURI_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE_ROOT="$TAURI_DIR/src-tauri/rel"

# Step 1: Build OTP release
mix_release() {
  cd "$MIX_PROJECT_DIR"
  MIX_ENV=prod mix release worth --overwrite --path "$RELEASE_ROOT"
}

# Step 2: Build Tauri app
tauri_build() {
  cd "$TAURI_DIR/src-tauri"
  cargo tauri build
}

case "${1:-build}" in
  release) mix_release ;;
  tauri)   tauri_build ;;
  build)   mix_release && tauri_build ;;
  *)       echo "Usage: $0 {release|tauri|build}" ;;
esac
```

#### 3.2 Release env (`rel/env.sh.eex`)

```bash
export RELEASE_DISTRIBUTION=none
export RELEASE_MODE=interactive
export RELEASE_COOKIE=$(head -c 32 /dev/urandom | base64)
export WORTH_HOME="${HOME}/.worth"

# Dynamic port: let the OS assign one, Elixir reads it after bind
[ -z "$WORTH_PORT" ] && export WORTH_PORT=0

# Load user customizations
[ -f "${HOME}/.worthdesktop.sh" ] && source "${HOME}/.worthdesktop.sh"
```

#### 3.3 CI matrix

Build on each platform separately (no cross-compilation for Tauri):

| Platform | Runner | Output |
|----------|--------|--------|
| macOS (aarch64) | macOS ARM | `.dmg`, `.app` |
| macOS (x86_64) | macOS Intel | `.dmg`, `.app` |
| Linux (x86_64) | Ubuntu | `.AppImage`, `.deb` |
| Windows (x86_64) | Windows | `.exe` (NSIS) |

### Phase 4: Polish (2-4 days)

#### 4.1 App icons

Generate icon set from a single SVG source:
- macOS: `.icns` (1024x1024)
- Windows: `.ico` (256x256)
- Linux: `.png` (512x512)

#### 4.2 System tray

Menu items:
- **Open Worth** — show/focus the main window
- **Separator**
- **Quit** — graceful shutdown

#### 4.3 Single instance

Use `tauri-plugin-single-instance`. If a second instance is launched while one is already running, forward any arguments to the running instance.

#### 4.4 Auto-update

Use `tauri-plugin-updater` with GitHub Releases as the update source. Requires:
- Code signing certificate (macOS)
- Authenticode signing (Windows)
- GPG signing (Linux AppImage)

#### 4.5 Deep linking (optional)

Register `worth://` URL scheme for opening specific workspaces:
- `worth://workspace/personal`
- `worth://mode/research`

### Phase 5: Distribution (1 day)

#### 5.1 GitHub Releases

Upload platform artifacts to GitHub Releases. The Tauri updater plugin can check these automatically.

#### 5.2 Install script (Linux)

```bash
curl -sSL https://github.com/<org>/worth/releases/latest/download/worth-linux-amd64.AppImage -o /usr/local/bin/worth
chmod +x /usr/local/bin/worth
```

#### 5.3 Homebrew Cask (macOS, optional)

```ruby
cask "worth" do
  version "0.1.0"
  sha256 "..."
  url "https://github.com/<org>/worth/releases/download/v#{version}/Worth_#{version}_aarch64.dmg"
  name "Worth"
  homepage "https://github.com/<org>/worth"
end
```

## Effort Estimate

| Phase | Description | Days | Dependencies |
|-------|-------------|------|--------------|
| 0 | Prerequisites (path deps, release config, localhost bind) | 1-2 | None |
| 1 | Tauri scaffold (project structure, Rust entry point, Elixir bridge) | 2-3 | Phase 0 |
| 2 | ElixirKit integration (PubSub, port discovery, lifecycle) | 2-3 | Phase 1 |
| 3 | Build pipeline (tauri.sh, CI matrix, release env) | 2-3 | Phase 2 |
| 4 | Polish (icons, tray, single instance, auto-update) | 2-4 | Phase 3 |
| 5 | Distribution (GitHub Releases, install scripts) | 1 | Phase 4 |
| **Total** | | **10-16 days** | |

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Path deps (`mneme`, `agent_ex`) hard to externalize | Medium | Blocks Phase 0 | Start with git deps as a stopgap; plan for Hex packages |
| ElixirKit not a general-purpose library | Medium | Phase 2 slower | ElixirKit is small (~500 LOC each side); fork and adapt if needed |
| Port conflicts with other apps | Low | User sees blank window | Dynamic port assignment + retry logic |
| WebView rendering differences across platforms | Low | UI bugs | Worth's UI is LiveView + Tailwind — well-supported by modern WebViews |
| Large binary size (ERTS + BEAM + NIFs) | Medium | Slow download | ERTS is ~30MB compressed; acceptable for desktop app |
| Code signing cost and complexity | Medium | Blocks auto-update | Start without auto-update, add signing later |
| Tauri 2 API changes | Low | Build breaks | Pin Tauri version; update deliberately |

## What This Does NOT Change

- Worth's Phoenix web UI remains unchanged
- The supervision tree and Brain architecture are untouched
- Development workflow (`mix phx.server`, `mix test`) is unchanged
- The `mix worth` CLI continues to work as before
- All existing LiveView, PubSub, and WebSocket communication stays the same

The Tauri layer is purely a **wrapper** that replaces "open browser" with "open webview window."

## Alternatives Considered

| Alternative | Why rejected |
|-------------|-------------|
| Burrito (single binary) | No native window. Would still need a separate launcher. |
| Electron | Ships full Chromium (~150MB). Tauri uses system webview (~5MB). |
| Wails | Go-based; adds a second language/toolchain with no advantage over Tauri for a web app. |
| Keep current approach | No self-contained distribution. Users need Elixir/OTP installed. |
