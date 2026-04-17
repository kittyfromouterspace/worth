# Configuration

## File Layout

```
~/.worth/
├── worth.db                          # Single PostgreSQL database (recollect tables)
├── config.exs                        # Global config
├── skills/                            # Global skill library
└── workspaces/
    └── ...
```

## Global Config Schema

```elixir
# ~/.worth/config.exs
config :worth,
  llm: [
    default_provider: :anthropic,
    providers: %{
      anthropic: [
        api_key: {:env, "ANTHROPIC_API_KEY"},
        default_model: "claude-sonnet-4-20250514"
      ],
      openai: [
        api_key: {:env, "OPENAI_API_KEY"},
        default_model: "gpt-4o"
      ],
      openrouter: [
        api_key: {:env, "OPENROUTER_API_KEY"},
        default_model: "anthropic/claude-sonnet-4"
      ]
    }
  ],
  memory: [
    enabled: true,
    extraction: :llm,       # :llm | :deterministic | :both
    auto_flush: true,
    decay_days: 90
  ],
  workspaces: [
    default: "personal",
    directory: "~/.worth/workspaces"
  ],
  ui: [
    theme: :dark,
    sidebar: :auto          # :auto | :always | :hidden
  ],
  cost_limit: 5.0,
  max_turns: 50,
  mcp: [
    servers: %{
      filesystem: %{
        type: :stdio,
        command: "npx",
        args: ["-y", "@anthropic/mcp-server-filesystem", "~"],
        env: %{},
        autoconnect: true
      }
    }
  ]
}
```

## Workspace Config

Each workspace can have identity files and override files:

- `IDENTITY.md` -- workspace personality (system prompt overlay)
- `AGENTS.md` -- project instructions (system prompt overlay)
- `.worth/skills.json` -- skill manifest (which global skills are active)
- `.worth/mcp.json` -- MCP server overrides (merge-style)

See [workspaces.md](workspaces.md) for details.
