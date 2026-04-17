# Project Structure

```
worth/
├── mix.exs
├── config/
│   ├── config.exs
│   ├── dev.exs
│   └── test.exs
├── lib/
│   ├── worth.ex                    # Main entry point, CLI parsing
│   ├── worth/
│   │   ├── application.ex          # OTP Application
│   │   ├── brain.ex                # Central brain GenServer
│   │   ├── config.ex               # Config loading, validation, runtime cache
│   │   ├── repo.ex                 # Ecto Repo (for Recollect)
│   │   ├── pubsub.ex               # Phoenix.PubSub instance
│   │   ├── registry.ex             # Elixir Registry for process discovery
│   │   ├── telemetry.ex            # Telemetry handlers + metrics reporter
│   │   ├── error.ex                # Structured error type
│   │   │
│   │   ├── ui/                     # Command parser
│   │   │   └── commands.ex             # Pure slash command parser (used by LiveView)
│   │   │
│   │   ├── llm/                    # LLM dispatch layer
│   │   │   ├── adapter.ex          # Behaviour
│   │   │   ├── anthropic.ex
│   │   │   ├── openai.ex
│   │   │   ├── openrouter.ex
│   │   │   └── cost.ex             # Cost calculation
│   │   │
│   │   ├── tools/                  # Worth-specific tool extensions
│   │   │   ├── workspace.ex
│   │   │   ├── web.ex
│   │   │   ├── git.ex
│   │   │   └── mcp.ex             # MCP gateway tools
│   │   │
│   │   ├── mcp/                    # MCP integration
│   │   │   ├── broker.ex           # DynamicSupervisor
│   │   │   ├── registry.ex         # Elixir Registry for PIDs
│   │   │   ├── tool_index.ex       # tool_name → server_name mapping
│   │   │   ├── gateway.ex          # Lazy discovery + execution
│   │   │   ├── connection_monitor.ex  # Health checks + reconnection
│   │   │   ├── client.ex           # Hermes.Client wrapper
│   │   │   ├── server.ex           # Worth as MCP server
│   │   │   └── config.ex           # Config loading
│   │   │
│   │   ├── workspace/              # Workspace management
│   │   │   ├── service.ex          # Create, list, switch, scaffold
│   │   │   ├── context.ex          # System prompt assembly (global + overlay)
│   │   │   └── identity.ex         # Identity file management
│   │   │
│   │   ├── memory/                 # Memory integration
│   │   │   ├── manager.ex          # Global context retrieval orchestration
│   │   │   ├── extractor.ex        # Fact extraction bridge
│   │   │   └── working_memory.ex   # Per-workspace ETS-backed GenServer
│   │   │
│   │   ├── skills/                 # Skill management
│   │   │   ├── service.ex          # Install, list, read, remove
│   │   │   ├── parser.ex           # SKILL.md parser
│   │   │   ├── validator.ex        # Static validation
│   │   │   ├── registry.ex         # :persistent_term metadata cache + ETS index
│   │   │   ├── lifecycle.ex        # CREATE → TEST → REFINE → PROMOTE
│   │   │   ├── refiner.ex          # Reactive + proactive refinement
│   │   │   ├── evaluator.ex        # A/B testing, success rate
│   │   │   ├── versioner.ex        # Version management
│   │   │   └── trust.ex            # Provenance and trust levels
│   │   │
│   │   ├── kits/                   # JourneyKits integration
│   │   │   └── service.ex          # Search, install, publish kits
│   │   │
│   │   ├── persistence/            # Session persistence
│   │   │   └── transcript.ex       # JSONL transcript backend
│   │   │
│   │   │
│   │   ├── theme/                  # Theme system
│   │   │   ├── standard.ex             # Default theme
│   │   │   ├── cyberdeck.ex            # Cyberdeck theme
│   │   │   ├── fifth_element.ex        # Fifth Element theme
│   │   │   ├── registry.ex             # Theme registry
│   │   │   └── behaviour.ex            # Worth.Theme behaviour
│   │   │
│   │   ├── web/                    # Phoenix LiveView web UI
│   │   │   ├── endpoint.ex             # Phoenix Endpoint (Bandit)
│   │   │   ├── router.ex               # Routes / to ChatLive
│   │   │   ├── telemetry.ex            # Phoenix telemetry
│   │   │   ├── live/
│   │   │   │   ├── chat_live.ex            # Main LiveView
│   │   │   │   ├── chat_live.html.heex     # HEEx template
│   │   │   │   ├── command_handler.ex      # Slash command dispatcher
│   │   │   │   └── commands/               # Command handlers
│   │   │   ├── components/
│   │   │   │   ├── chat_components.ex      # Chat rendering
│   │   │   │   ├── core_components.ex      # Shared UI primitives
│   │   │   │   ├── layouts/
│   │   │   │   │   └── root.html.heex      # Root layout
│   │   │   │   ├── settings_components.ex  # Settings UI
│   │   │   │   └── theme_helper.ex         # color/1 helper
│   │   │   └── controllers/                # Error handlers
│   │   │
│   │   ├── commands/               # Slash command handlers
│   │   │   └── registry.ex
│   │   │
│   │   └── cli/                    # CLI interface (outside TUI)
│   │       └── runner.ex           # owl-based output for init, help, errors
│   │
│   │   └── config/
│   │       └── schema.ex           # nimble_options config schema
│
├── priv/
│   ├── prompts/                    # System prompt templates
│   │   └── system.md               # Core worth system prompt
│   ├── core_skills/                # Bundled skills
│   │   ├── agent-tools/SKILL.md
│   │   ├── human-agency/SKILL.md
│   │   └── tool-discovery/SKILL.md
│   ├── templates/                  # Workspace scaffolding templates
│   │   ├── IDENTITY.md
│   │   ├── AGENTS.md
│   │   └── skills.json
│   └── repo/migrations/            # Recollect tables
│       └── 20260101000000_create_worth_tables.exs
│
└── test/
    ├── worth_test.exs
    ├── worth/
    │   ├── brain_test.exs
    │   ├── workspace_test.exs
    │   ├── llm/
    │   │   └── adapter_test.exs
    │   └── memory/
    │       └── manager_test.exs
    ├── support/
    │   ├── data_case.ex
    │   └── brain_case.ex
    └── ui/
        └── root_test.exs
```
