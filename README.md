<p align="center">
  <!-- TODO: Add a screenshot or banner of the Worth desktop app here -->
  <!-- <img src="path/to/screenshot.png" width="720" alt="Worth Desktop App"> -->
  <br/>
  <img src="rel/desktop/src-tauri/icons/128x128.png" width="128" alt="Worth Logo">
</p>

<h1 align="center">Worth</h1>

<p align="center">
  A powerful personal AI agent &amp; a research petri dish for memory systems and agent loop design.
  <br/>
  Built on Elixir/BEAM. Runs as a native desktop app on macOS, Windows, and Linux.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-BSD--3--Clause-blue.svg" alt="License"></a>
  <a href="https://elixir-lang.org"><img src="https://img.shields.io/badge/Elixir-1.19+-purple.svg" alt="Elixir"></a>
  <a href="https://www.erlang.org"><img src="https://img.shields.io/badge/BEAM-OTP%2026+-red.svg" alt="BEAM"></a>
</p>

---

## What is Worth?

Worth is two things in one.

**A powerful AI agent for everyone.** Write code, research topics, manage git repos, browse the web, and connect to external services — all from a single desktop application. Worth gives you a persistent AI assistant with a global memory that learns your preferences across everything you do.

**A research petri dish for agent enthusiasts.** Worth is built on [Agentic](https://github.com/kittyfromouterspace/agentic) (the agent loop engine) and [Recollect](https://github.com/kittyfromouterspace/recollect) (the memory engine) — two standalone libraries you can study, modify, and experiment with. Worth is the living organism that shows what these building blocks can do when composed together.

### Understanding Agents Through Worth

If you want to understand how AI agents actually work — not just use them — Worth is the project for you. Every subsystem is a small, readable Elixir module:

- **Agent loop** — See how an LLM turns into an autonomous agent via `Agentic.run/1`. The loop iterates LLM calls and tool executions until the task is complete. You can inspect the stages, modify tool permissions, and switch autonomy modes.
- **Memory** — Explore how persistent memory works through Recollect's three-tier system: working memory (per-session), knowledge graph (facts and relationships), and vector search (semantic retrieval). Watch how memories decay, how facts are extracted, and how the agent uses context from past conversations.
- **Skills** — See how agents can learn and self-improve. Skills follow the [agentskills.io](https://agentskills.io/) standard and go through a lifecycle: create, test, refine, promote. The system tracks success rates and auto-refines underperforming skills.
- **MCP integration** — Understand the Model Context Protocol by connecting Worth to external services (GitHub, databases, Slack) and watching how tool discovery and execution works in practice.

## Desktop App

Worth ships as a native desktop application built with [Tauri](https://tauri.app/), wrapping the Phoenix LiveView web UI in a lightweight native shell. It runs on all major platforms:

| Platform | Format |
|----------|--------|
| **macOS** | `.dmg` (10.15+) |
| **Windows** | `.exe` installer (NSIS, per-user) |
| **Linux** | `.deb` / `.AppImage` |

The app opens a 1200x800 window with the full Worth UI — chat, sidebar, workspace management, and slash commands. Everything runs locally on your machine. No cloud, no containers.

## Workspaces

Worth uses workspaces to separate projects and give the agent project-specific context.

A workspace is a named environment that provides:

- **Identity** — `IDENTITY.md` tells the agent what the project is about (read every turn)
- **Agent instructions** — `AGENTS.md` contains project-specific coding conventions and preferences
- **Local skills** — `.worth/skills.json` activates skills for this workspace
- **MCP overrides** — `.worth/mcp.json` connects project-specific external services

```
~/.worth/workspaces/
└── my-project/
    ├── IDENTITY.md          # What is this project?
    ├── AGENTS.md            # How should the agent behave here?
    └── .worth/
        ├── skills.json      # Active skills
        └── mcp.json         # MCP server config
```

Memory is **global** — not per-workspace. A pattern learned in one workspace (e.g., "user prefers conventional commits") is available everywhere. Workspaces are lenses, not silos.

Switch between workspaces with `/workspace switch <name>` in the chat, or launch directly into one:

```bash
worth --workspace my-project
```

## Security & Sandboxing

Worth treats agent filesystem access as a privileged operation and applies defense-in-depth isolation across three layers:

### 1. Path Validation (All Platforms)

All built-in file tools (`read_file`, `write_file`, `edit_file`, `list_files`) enforce an **explicit allowlist of roots**:

- The active **workspace directory**
- The agent's **own config/cache directories** (e.g. `~/.claude`, `~/.opencode`)

This prevents:
- Absolute path injection
- `..` directory traversal
- Symlink escapes
- Access to sensitive system paths (`~/.ssh`, `/etc`, etc.)

Importantly, coding agents **never** receive access to Worth's internal data directory (where your SQLite database, vault, and settings live).

### 2. Shell Command Sandboxing

The `bash` tool does not run raw shell commands with full user privileges. Instead, Worth wraps every command in an OS-specific sandbox:

| Platform | Sandbox Mechanism |
|----------|-------------------|
| **Linux** | [bubblewrap](https://github.com/containers/bubblewrap) (`bwrap`) — namespace isolation with read-only system mounts and writable workspace/agent directories only |
| **macOS** | [App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-app-sandbox) inheritance — child processes automatically inherit the sandbox of the signed parent app |
| **Windows + WSL2** | `wsl.exe bwrap ...` — Linux sandboxing runs inside WSL2 for full filesystem isolation |
| **Windows (no WSL2)** | Restricted token + Job Object fallback. Because this is weaker than namespace isolation, Worth emits a **visible warning** at startup and when spawning agents |

Sandbox selection is based on the **operating system** (`:os.type/0`), not on the presence of a binary in `$PATH`. This avoids silent failures (e.g. `bwrap` installed on macOS via Homebrew but unable to provide meaningful macOS isolation).

### 3. Coding Agent CLI Sandboxing

External coding agents such as **Claude Code** and **OpenCode** are spawned through the same sandbox runner as the `bash` tool. Even if the agent's internal tool system requests a file outside the allowed roots, the OS-level sandbox blocks the access.

On Linux release builds, Worth attempts to use a **bundled static `bwrap` binary** so the sandbox works even on minimal distros that do not ship bubblewrap by default.

### Agent Directory Discovery

Worth maintains an ACP registry that tracks the per-OS config, log, and cache directories for every supported coding agent. When you switch to a coding agent, Worth automatically grants it access to its own home directories while keeping everything else locked down.

## Quick Start

### Desktop App

Download the latest release for your platform from the [releases page](../../releases), install, and launch. The app will guide you through initial setup on first run.

### From Source

```bash
git clone https://github.com/kittyfromouterspace/worth.git
cd worth

# Worth requires two sibling libraries
git clone https://github.com/kittyfromouterspace/agentic.git ../agentic
git clone https://github.com/kittyfromouterspace/recollect.git ../recollect

mix deps.get
mix setup                  # deps + database + assets
export ANTHROPIC_API_KEY="sk-ant-..."
mix worth                  # launches the web UI (opens browser)
```

Open http://localhost:4000 in your browser, or build the desktop app:

```bash
# Build the Tauri desktop app
cd rel/desktop/src-tauri && cargo tauri build
```

## Core Concepts

### The Brain

`Worth.Brain` is a GenServer that orchestrates the agent loop. It holds the session state and delegates to specialized subsystems:

```elixir
{:ok, response} = Worth.Brain.send_message("Write a test for auth.ex")
```

The brain exposes these integration points:
- `send_message/2` — Send user input, get agent response
- `approve_tool/2` — Approve a pending tool call
- `switch_workspace/2` — Change context
- `switch_mode/2` — Change agent autonomy (`:code`, `:research`, `:planned`, `:turn_by_turn`)

### Memory System (Recollect)

Worth uses [Recollect](https://github.com/kittyfromouterspace/recollect) for persistent memory — a three-tier system:

1. **Working memory** — Per-session context, flushed to global memory on workspace switch
2. **Knowledge graph** — Structured facts extracted from conversations (entities, relationships)
3. **Vector search** — Semantic retrieval over past knowledge using embeddings

```elixir
# Store a fact (global, shared across all workspaces)
Worth.Memory.Manager.write(%{
  content: "User prefers conventional commits",
  entry_type: "preference",
  metadata: %{workspace: "my-project"}
})

# Search global knowledge
{:ok, results} = Worth.Memory.Manager.search("commit conventions")
```

Memory decays over time — older facts fade unless reinforced. This keeps the knowledge base relevant and prevents stale information from polluting context.

### Skills System

Skills teach the agent *how* to use tools effectively. They follow the [agentskills.io](https://agentskills.io/) standard and go through a lifecycle:

- **Create** — Agent or user writes a skill as a `SKILL.md` file
- **Test** — Skill is used in real tasks; success rate is tracked
- **Refine** — Underperforming skills are automatically refined by the LLM
- **Promote** — Proven skills graduate to higher trust levels

Trust levels: `core` (shipped with Worth), `installed` (user-added), `learned` (agent-created).

### MCP Integration

Worth connects to external services via the [Model Context Protocol](https://modelcontextprotocol.org/). Tools are namespaced as `server:tool_name` to avoid collisions.

```elixir
# Configure in ~/.worth/config.exs
%{
  mcp: %{
    servers: %{
      github: %{
        type: "stdio",
        command: "npx",
        args: ["-y", "@modelcontextprotocol/server-github"],
        env: %{"GITHUB_TOKEN" => {:env, "GITHUB_TOKEN"}},
        autoconnect: true
      }
    }
  }
}
```

Worth can also expose itself as an MCP server (`worth serve`), letting other agents query its memory, skills, and workspace status.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    Worth (BEAM Node)                      │
│                                                          │
│  ┌──────────────┐    ┌──────────────┐                   │
│  │  Tauri Shell │    │  Brain       │                   │
│  │  + LiveView  │◄──►│  (GenServer) │                   │
│  │              │    │              │                    │
│  │  - Chat UI   │    │  - Agentic   │                    │
│  │  - Sidebar   │    │    .run/1    │                    │
│  │  - Commands  │    │  - Recollect     │                    │
│  └──────────────┘    │  - Skills    │                    │
│                      │  - MCP       │                    │
│                      └──────┬───────┘                    │
│                             │                            │
│                      ┌──────▼───────┐                    │
│                      │  Agentic     │                    │
│                      │  Loop Engine │                    │
│                      │              │                    │
│                      │  Stages:     │                    │
│                      │  ContextGuard│                    │
│                      │  LLMCall     │                    │
│                      │  ToolExecutor│                    │
│                      │  CommitGate  │                    │
│                      └──────┬───────┘                    │
│                             │                            │
│        ┌─────────────┬──────┼──────┬─────────────┐      │
│        │             │      │      │             │      │
│ ┌──────▼──┐  ┌──────▼──┐  ┌──▼──┐  ┌──────▼──┐  ┌─▼───┐│
│ │ Recollect   │  │ File    │  │Tool │  │ Skills  │  │ MCP ││
│ │ Memory  │  │ Tools   │  │Index│  │ System  │  │Srvrs││
│ └──────┬──┘  └─────────┘  └─────┘  └─────────┘  └─────┘│
│        │                                               │
│ ┌──────▼──┐                                            │
│ │Database │                                            │
│ │(libSQL/ │                                            │
│ │ pg)     │                                            │
│ └─────────┘                                            │
└──────────────────────────────────────────────────────────┘
```

### Supervision Tree

```
Worth.Application
├── Worth.Repo (Ecto + libSQL/PostgreSQL)
├── Worth.Config (Agent)
├── Phoenix.PubSub + Worth.Registry
├── Worth.TaskSupervisor
├── Worth.Telemetry
├── Worth.Mcp.Broker (DynamicSupervisor)
├── Worth.Mcp.ConnectionMonitor
├── Worth.Brain.Supervisor
│   └── Worth.Brain (GenServer)
└── WorthWeb.Endpoint (Bandit HTTP server → LiveView)
```

Every subsystem has its own supervisor. A crashed MCP connection restarts without killing the agent. A memory flush failure doesn't kill the brain. This is the BEAM's fault tolerance at work.

### Key Modules

| Module | Responsibility |
|--------|----------------|
| `Worth.Brain` | Central GenServer, coordinates agent loop |
| `WorthWeb.ChatLive` | Phoenix LiveView chat interface |
| `Worth.Memory.Manager` | Global memory orchestration via Recollect |
| `Worth.Skill.Service` | Skill CRUD, lifecycle management |
| `Worth.Mcp.Broker` | DynamicSupervisor for MCP connections |
| `Worth.Mcp.Gateway` | Lazy tool discovery and execution |
| `Worth.LLM.Router` | Multi-provider model routing |

## Configuration

Worth reads from `~/.worth/config.exs` (auto-created on first run):

```elixir
%{
  llm: %{
    default_provider: :anthropic,
    cost_limit: 5.0,
    providers: %{
      anthropic: %{
        api_key: {:env, "ANTHROPIC_API_KEY"},
        default_model: "claude-sonnet-4-20250514"
      },
      openrouter: %{
        api_key: {:env, "OPENROUTER_API_KEY"},
        default_model: "anthropic/claude-3.5-sonnet"
      }
    }
  },
  theme: :standard
}
```

## Slash Commands

| Command | Description |
|---------|-------------|
| `/help` | Show all commands |
| `/mode <mode>` | Switch mode: code, research, planned, turn_by_turn |
| `/workspace switch <name>` | Switch to a workspace |
| `/memory query <query>` | Search global memory |
| `/skill list` | List all skills |
| `/session resume <id>` | Resume a past session |
| `/mcp list` | List connected MCP servers |
| `/usage` | Show provider quota and session cost |

## Themes

| Theme | Description |
|-------|-------------|
| `standard` | Catppuccin Mocha (default) — soft dark theme |
| `cyberdeck` | Tactical HUD aesthetic — neon cyber command |
| `fifth_element` | Industrial retro-futuristic — Moebius sci-fi |

Set in `~/.worth/config.exs`:

```elixir
%{theme: :fifth_element}
```

## Why Elixir/BEAM?

Worth runs on the BEAM virtual machine — the same platform powering WhatsApp, Discord, and Heroku.

- **Process isolation** — Each MCP server, tool execution, and agent turn runs in its own lightweight process. Failures are contained.
- **Supervision trees** — Built-in fault tolerance. A crashed connection restarts without killing the agent.
- **Hot code upgrades** — Reload modules without restarting. Worth can evolve while running.
- **Real-time concurrency** — Streaming LLM responses, tool execution, and UI updates happen concurrently.

## Prerequisites

- **Elixir** 1.19+ (for building from source)
- **LLM API key** — Anthropic, OpenAI, or OpenRouter
- **Rust** (for building the desktop app)

## Development

```bash
mix deps.get        # Install dependencies
mix setup           # Full setup (deps + DB + assets)
mix test            # Run tests
mix credo           # Linting
mix dialyzer        # Type checking
```

## Documentation

Full design docs in `docs/`:

| Document | Description |
|----------|-------------|
| [vision.md](docs/vision.md) | What Worth is and why it exists |
| [architecture.md](docs/architecture.md) | System architecture and dependencies |
| [brain.md](docs/brain.md) | Brain GenServer and callback system |
| [memory.md](docs/memory.md) | Global memory: vector search + knowledge graph |
| [skills.md](docs/skills.md) | Skill system, trust levels, self-learning |
| [mcp.md](docs/mcp.md) | MCP client/server integration |
| [tools.md](docs/tools.md) | Available tools and extensions |
| [theme-system.md](docs/theme-system.md) | Theme system and customization |

## Dependencies

| Library | Purpose |
|---------|---------|
| `agentic` (path) | Agent loop engine with stages, profiles, and tool system |
| `recollect` (path) | Vector search + knowledge graph for memory |
| `phoenix` + `phoenix_live_view` | Web UI framework |
| `hermes_mcp` | MCP client/server (JSON-RPC 2.0) |
| `bandit` | HTTP server for LiveView |
| `ash` + `ash_postgres` | Domain modeling and persistence |
| `req` | HTTP client for LLM APIs |

## License

BSD-3-Clause. See [LICENSE](LICENSE) for details.
