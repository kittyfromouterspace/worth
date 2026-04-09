# Worth

An AI assistant built on Elixir/BEAM with a Phoenix LiveView web interface. Worth provides a modular, embeddable agent system with persistent memory, self-learning skills, and MCP integration.

[![License](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](LICENSE)
[![Elixir](https://img.shields.io/badge/Elixir-1.19+-grey.svg)](https://elixir-lang.org)
[![BEAM](https://img.shields.io/badge/BEAM-OTP-26+-grey.svg)](https://www.erlang.org)

## Why Elixir/BEAM?

Worth runs on the BEAM virtual machine—the same platform powering WhatsApp, Discord, and Heroku. BEAM provides:

- **Process isolation** — Each MCP server, tool execution, and agent turn runs in its own lightweight process. Failures are contained.
- **Supervision trees** — Built-in fault tolerance. A crashed MCP connection restarts without killing the agent.
- **Hot code upgrades** — Reload modules without restarting. Worth can evolve while running.
- **Real-time concurrency** — Streaming LLM responses, tool execution, and UI updates happen concurrently without callback hell.

## Quick Start

### As a Standalone Application

```bash
# Clone and setup
git clone https://github.com/kittyfromouterspace/worth.git
cd worth
mix setup

# Configure API keys
export ANTHROPIC_API_KEY="sk-ant-..."

# Start the web UI
mix phx.server
```

Open http://localhost:4000 in your browser.

Or use the CLI launcher (auto-opens browser):

```bash
mix worth
mix worth --workspace my-project --mode research
```

### As a Library

Add Worth to your `mix.exs`:

```elixir
def deps do
  [
    {:worth, "~> 0.1.0"},
    {:agent_ex, path: "../agent_ex"},
    {:mneme, path: "../mneme"}
  ]
end
```

## Core Concepts

### The Brain

`Worth.Brain` is a GenServer that orchestrates the agent loop. It owns the session state and delegates to specialized subsystems:

```elixir
# Send a message
{:ok, response} = Worth.Brain.send_message("Write a test for auth.ex")
```

The brain exposes these integration points:
- `send_message/1` — Send user input, get agent response
- `approve_tool/1` — Approve a pending tool call
- `switch_workspace/1` — Change context
- `switch_mode/1` — Change agent autonomy (`:code`, `:research`, `:planned`, `:turn_by_turn`)

### Memory System

Worth uses [Mneme](https://github.com/kittyfromouterspace/mneme) for vector search + knowledge graph:

```elixir
# Store a fact (global, not per-workspace)
Worth.Memory.Manager.write(%{
  content: "User prefers conventional commits",
  entry_type: "preference",
  metadata: %{workspace: "my-project"}
})

# Search global knowledge
{:ok, results} = Worth.Memory.Manager.search("commit conventions")
```

Memory is **global** by design. All workspaces share one knowledge store. Workspaces provide context overlays (project identity, local skills), not memory silos.

### Skills System

Skills follow the [agentskills.io](https://agentskills.io/) standard and teach the agent *how* to use tools:

```elixir
# List available skills
skills = Worth.Skill.Service.list()

# Read skill content
{:ok, skill} = Worth.Skill.Service.read("git-workflow")
```

Skills have trust levels: `core` (shipped), `installed` (user-added), `learned` (agent-created). The system tracks success rates and auto-refines underperforming skills.

### MCP Integration

Worth can connect to external MCP servers and expose its own capabilities as an MCP server.

**As an MCP Client:**

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

**As an MCP Server:**

```bash
mix worth serve
```

Exposed tools: `worth_chat`, `worth_memory_query`, `worth_skill_list`, `worth_workspace_status`

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    Worth (BEAM Node)                      │
│                                                          │
│  ┌──────────────┐    ┌──────────────┐                   │
│  │  Phoenix     │    │  Brain       │                   │
│  │  LiveView    │◄──►│  (GenServer) │                   │
│  │              │    │              │                    │
│  │  - Chat UI   │    │  - AgentEx   │                   │
│  │  - Sidebar   │    │  - Mneme     │                   │
│  │  - Commands  │    │  - Skills    │                   │
│  └──────────────┘    │  - MCP       │                   │
│                      └──────┬───────┘                   │
│                             │                           │
│                      ┌──────▼───────┐                   │
│                      │  AgentEx     │                   │
│                      │  Loop Engine │                   │
│                      └──────┬───────┘                   │
│                             │                           │
│        ┌─────────────┬──────┼──────┬─────────────┐     │
│        │             │      │      │             │     │
│ ┌──────▼──┐  ┌──────▼──┐  ┌──▼──┐  ┌──────▼──┐  ┌─▼───┐│
│ │ Mneme   │  │ File    │  │Tool │  │ Skills  │  │ MCP ││
│ │ Memory  │  │ Tools   │  │Index│  │ System  │  │Srvrs││
│ └──────┬──┘  └─────────┘  └─────┘  └─────────┘  └─────┘│
│        │                                               │
│ ┌──────▼──┐                                            │
│ │PostgreSQL│                                           │
│ │+ pgvector│                                           │
│ └─────────┘                                            │
└──────────────────────────────────────────────────────────┘
```

### Key Modules

| Module | Responsibility |
|--------|----------------|
| `Worth.Brain` | Central GenServer, coordinates agent loop |
| `WorthWeb.ChatLive` | Phoenix LiveView chat interface |
| `Worth.Memory.Manager` | Global memory orchestration |
| `Worth.Skill.Service` | Skill CRUD, lifecycle management |
| `Worth.Mcp.Broker` | DynamicSupervisor for MCP connections |
| `Worth.Mcp.Gateway` | Lazy tool discovery and execution |
| `Worth.Tools` | Builtin tool implementations |

### Supervision Tree

```
Worth.Application
├── Worth.Repo (Ecto/Postgres + pgvector)
├── Worth.Config (Agent)
├── Worth.LogBuffer
├── Phoenix.PubSub + Worth.Registry
├── Worth.TaskSupervisor
├── Worth.Telemetry + Worth.Metrics
├── Worth.Agent.Tracker
├── Worth.Mcp.Broker (DynamicSupervisor)
├── Worth.Mcp.ConnectionMonitor
├── Worth.Brain.Supervisor
│   └── Worth.Brain (GenServer)
├── WorthWeb.Telemetry
└── WorthWeb.Endpoint (Phoenix)
```

## Prerequisites

- **Elixir** 1.19+
- **PostgreSQL** 14+ with pgvector extension
- **LLM API key** (Anthropic, OpenAI, or OpenRouter)

### Database Setup

```bash
mix ecto.create
mix ecto.migrate
```

Or with Docker:

```bash
docker run -d \
  --name worth-db \
  -e POSTGRES_PASSWORD=worth \
  -e POSTGRES_DB=worth \
  -v pgdata:/var/lib/postgresql/data \
  -p 5432:5432 \
  pgvector/pgvector:pg16
```

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
  mcp: %{
    servers: %{
      filesystem: %{
        type: "stdio",
        command: "npx",
        args: ["-y", "@modelcontextprotocol/server-filesystem", "/home/user/projects"],
        autoconnect: true
      }
    }
  }
}
```

## Development

```bash
mix deps.get        # Install dependencies
mix setup           # Full setup (deps + DB + assets)
mix phx.server      # Start dev server with hot reload
mix test            # Run tests
mix credo           # Linting
mix dialyzer        # Type checking
```

### Running Tests

```bash
mix test                              # Full suite
mix test test/worth/brain_test.exs    # Single file
mix test test/worth/brain_test.exs:42 # Single test
```

## Slash Commands

These commands are available in the chat input:

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
| `/setup` | Show setup status |

## Workspaces

A workspace is a project directory with identity files:

```
my-project/
├── IDENTITY.md              # Project description (read each turn)
├── AGENTS.md                # Agent-specific instructions
└── .worth/
    ├── skills.json          # Active skills for this workspace
    └── mcp.json             # MCP server overrides
```

## Documentation

Full design docs in `docs/`:

| Document | Description |
|----------|-------------|
| [vision.md](docs/vision.md) | What worth is and why it exists |
| [architecture.md](docs/architecture.md) | System architecture and dependencies |
| [brain.md](docs/brain.md) | Brain GenServer and callback system |
| [memory.md](docs/memory.md) | Global memory: vector search + knowledge graph |
| [skills.md](docs/skills.md) | Skill system, trust levels, self-learning |
| [mcp.md](docs/mcp.md) | MCP client/server integration |
| [tools.md](docs/tools.md) | Available tools and extensions |

## Dependencies

Worth depends on two local libraries that must exist as siblings:

- **`../agent_ex`** — Agent loop engine with stages, profiles, and tool system
- **`../mneme`** — Vector search + knowledge graph for memory

Other key dependencies:

| Library | Purpose |
|---------|---------|
| `phoenix` + `phoenix_live_view` | Web UI framework |
| `hermes_mcp` | MCP client/server (JSON-RPC 2.0) |
| `ash` + `ash_postgres` | Domain modeling and persistence |
| `phoenix_pubsub` | Event broadcasting |
| `req` | HTTP client for LLM APIs |
| `earmark` | Markdown rendering |

## License

BSD-3-Clause. See [LICENSE](LICENSE) for details.

## Contributing

Contributions welcome. Please ensure:
- `mix credo` passes (linting)
- `mix dialyzer` passes (types)
- Tests pass (`mix test`)
