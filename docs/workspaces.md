# Workspaces

## What is a Workspace

Workspaces are directories on disk. Each workspace represents a project or context boundary. They are **lenses** onto the global knowledge store, not memory silos.

## Directory Structure

```
~/.worth/
├── worth.db                          # Single PostgreSQL database (recollect tables)
├── config.exs                        # Global config
├── skills/                            # Global skill library
└── workspaces/
    ├── my-project/
    │   ├── IDENTITY.md               # Workspace personality (overlay)
    │   ├── AGENTS.md                 # Project-specific instructions (overlay)
    │   ├── .worth/
    │   │   ├── transcript.jsonl      # Session transcript
    │   │   ├── skills.json            # Skill manifest (which global skills are active)
    │   │   └── plans/                # Saved plans
    │   └── mcp.json                  # MCP server overrides (merge-style)
    ├── research/
    │   ├── IDENTITY.md
    │   ├── .worth/
    │   │   ├── transcript.jsonl
    │   │   └── skills.json
    │   └── mcp.json
    └── personal/
        ├── IDENTITY.md
        ├── .worth/
        │   ├── transcript.jsonl
        │   └── skills.json
        └── mcp.json
```

## Workspace Types

| Type | Profile | Purpose |
|------|---------|---------|
| **code** | `:agentic` | Default. Full tool access, file read/write/edit/bash |
| **research** | `:conversational` or `:agentic` | No file mutation by default, web access |
| **scratch** | `:agentic` | Temporary workspace, ephemeral |

## Workspace Lifecycle

1. `worth init my-project` -- scaffolds directory with templates
2. `worth` or `worth -w my-project` -- opens the UI, enters the workspace
3. Identity files loaded as system prompt overlay
4. Global skills activated per workspace manifest
5. On exit: ContextKeeper flushes to global recollect store

## Workspace Identity Files

### IDENTITY.md

Workspace personality and behavioral instructions. Loaded into every system prompt when this workspace is active:

```markdown
# My Project

This is a Phoenix web application using Elixir and LiveView.

## Code Style
- Use snake_case for function and variable names
- Prefer pipes over explicit variable bindings
- Always add @moduledoc to public modules

## Conventions
- Tests use ExUnit
- Migrations are always reversible
- Never commit secrets
```

### AGENTS.md

Project-specific instructions for the agent. More operational than IDENTITY.md:

```markdown
# Agent Instructions

## Testing
- Run tests with `mix test` before committing
- Use `mix test --trace` for debugging

## Database
- Migrations must be reversible
- Always test migrations on a copy of production data

## Deployment
- Deploy via `mix release`
- Health check at /health
```

## Skill Manifest (skills.json)

Specifies which global skills are active and any workspace overrides:

```json
{
  "active": ["git-workflow", "elixir-conventions", "tool-discovery"],
  "override": {
    "elixir-conventions": "my-project-conventions"
  }
}
```

## MCP Overrides (mcp.json)

Merge-style overrides for MCP servers. Workspace config wins for conflicting server names:

```json
{
  "mcpServers": {
    "postgres": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-server-postgres", "postgresql://localhost/myapp"]
    }
  }
}
```

## Switching Workspaces

When the user switches workspaces (`/workspace switch my-project`):

1. Flush ContextKeeper for current workspace → global recollect store
2. Load new workspace's identity files
3. Load new workspace's skill manifest
4. Merge MCP configs (global + workspace overrides)
5. Start new ContextKeeper for new workspace
6. Clear conversation history (or offer to carry over)

## Default Workspace

Configurable in `~/.worth/config.exs`:

```elixir
config :worth,
  workspaces: [
    default: "personal",
    directory: "~/.worth/workspaces"
  ]
```

Running `worth` without `-w` opens the default workspace.
