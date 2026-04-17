# UI Design (Phoenix LiveView)

## Layout

Worth's UI is a Phoenix LiveView web application served by Bandit HTTP server at
`http://localhost:4000` by default. The CLI opens the browser automatically on
startup.

The main view is `WorthWeb.ChatLive` (`lib/worth_web/live/chat_live.ex`).

## Component Architecture

```
WorthWeb.ChatLive                (main LiveView, ~1142 lines)
├── WorthWeb.ChatComponents       (chat message rendering, tool traces)
├── WorthWeb.CoreComponents       (shared UI primitives)
├── WorthWeb.Layouts.Root         (root HTML layout)
├── WorthWeb.CommandHandler       (slash command dispatcher)
├── WorthWeb.Commands.SystemCommands  (/help, /clear, /cost, /compact, /mode, /quit)
├── WorthWeb.Commands.WorkspaceCommands  (/workspace list, switch, new)
├── WorthWeb.Commands.SessionCommands   (/session list, resume)
├── WorthWeb.Commands.SkillCommands     (/skill list, read, remove, review, revert, export)
├── WorthWeb.Commands.KitCommands       (/kit search, install, list, info, publish)
├── WorthWeb.Commands.MemoryCommands    (/memory query, note, recent)
├── WorthWeb.Commands.McpCommands       (/mcp list, add, remove, connect, disconnect, tools, status)
└── WorthWeb.ThemeHelper         (color/1 function for theme system)
```

## Key UI Components

| Component | LiveView/Phoenix | Behavior |
|-----------|-----------------|----------|
| Chat area | `WorthWeb.ChatLive` | Message list, streaming responses, markdown |
| Input | `<.form>` + `phx-submit` | Text input with `/` command prefix |
| Sidebar | HEEx template sections | Workspace info, tools, status |
| Tool trace | Collapsible HEEx blocks | Expandable tool call/result blocks |
| Status display | Assigns + `assigns/3` | Cost tracking, turn counter, model name |

## Event Flow

```
User types message in browser
    │
    ▼
Phoenix LiveView `handle_event("send_message", ...)` → Worth.Brain.send_message(text, workspace)
    │
    ▼
Worth.Brain (GenServer) → Agentic.run/1
    │
    │  Agentic emits events via :on_event callback:
    │  - {:text_chunk, "I'll read..."}
    │  - {:tool_call, %{name: "read_file", input: %{...}}}
    │  - {:tool_result, %{name: "read_file", output: "..."}}
    │  - {:status, :idle | :running | :error}
    │  - {:done, %{text: "...", cost: 0.042, tokens: %{...}}}
    │
    ▼
Brain broadcasts to Worth.PubSub → ChatLive.handle_info({:agent_event, event})
    │
    ▼
LiveView updates assigns, Phoenix pushes diff to browser
```

Communication:
- **UI → Brain**: `GenServer.call(Worth.Brain.via(workspace), {:send_message, text})` (synchronous)
- **Brain → UI**: `Phoenix.PubSub.broadcast(Worth.PubSub, ...)` (async streaming via PubSub)

## Slash Commands

| Command | Action |
|---------|--------|
| `/help` | Show available commands |
| `/mode code\|research\|planned\|turn-by-turn` | Switch execution mode |
| `/workspace list` | List all workspaces |
| `/workspace switch <name>` | Switch workspace |
| `/workspace new <name>` | Create new workspace |
| `/model <name>` | Change LLM model |
| `/skill list` | List installed and learned skills |
| `/skill install <owner/repo>` | Install skill from GitHub |
| `/skill read <name>` | Read skill content |
| `/skill remove <name>` | Remove skill |
| `/skill review <name>` | Review and promote/demote |
| `/skill revert <name> [version]` | Roll back skill version |
| `/skill export <name>` | Export skill as archive |
| `/kit search <query>` | Search JourneyKits for workflows |
| `/kit install <owner/slug>` | Install a kit |
| `/kit list` | List installed kits |
| `/kit info <owner/slug>` | Show kit details |
| `/kit publish <dir>` | Publish a kit from directory |
| `/memory query <text>` | Search knowledge store |
| `/memory note <text>` | Store a note in working memory |
| `/clear` | Clear chat history |
| `/cost` | Show session cost summary |
| `/compact` | Force context compaction |
| `/mcp list` | List MCP servers |
| `/mcp add <name>` | Add MCP server |
| `/mcp remove <name>` | Remove MCP server |
| `/mcp connect <name>` | Connect MCP server |
| `/mcp disconnect <name>` | Disconnect MCP server |
| `/mcp tools <name>` | List MCP server tools |
| `/mcp status <name>` | MCP server status |
| `/quit` | Exit worth |
