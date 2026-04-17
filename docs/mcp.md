# MCP Integration

MCP (Model Context Protocol) is worth's primary extensibility mechanism for connecting to external tools, data sources, and services. Skills teach the agent *how* to use tools; MCP provides the tools themselves.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Worth Brain                             │
│  ┌────────────────────────────────────────────────────────┐  │
│  │              ToolGateway (lazy discovery)              │  │
│  │                                                        │  │
│  │  Builtin Tools          MCP Tools                      │  │
│  │  ┌──────────────┐      ┌──────────────────────────┐   │  │
│  │  │ read_file    │      │ github:search_repos       │   │  │
│  │  │ write_file   │      │ github:create_pr          │   │  │
│  │  │ edit_file    │      │ brave:web_search          │   │  │
│  │  │ bash         │      │ postgres:query            │   │  │
│  │  │ list_files   │      │ fetch:get_content         │   │  │
│  │  │ skill_*      │      │ slack:send_message        │   │  │
│  │  │ memory_*     │      │ ...                       │   │  │
│  │  │ search_tools │      │                            │   │  │
│  │  │ use_tool     │      │                            │   │  │
│  │  └──────────────┘      └──────────────────────────┘   │  │
│  └─────────────────────────┬──────────────────────────────┘  │
│                            │                                 │
│                   ┌────────▼────────┐                        │
│                   │   McpBroker     │                        │
│                   │ (DynamicSup)   │                        │
│                   └────────┬────────┘                        │
│                            │                                 │
│          ┌─────────────────┼──────────────────┐              │
│          │                 │                  │              │
│    ┌─────▼─────┐   ┌──────▼──────┐  ┌───────▼───────┐    │
│    │ GitHub    │   │ Brave       │  │ PostgreSQL    │    │
│    │ (stdio)   │   │ (HTTP)      │  │ (stdio)       │    │
│    └───────────┘   └─────────────┘  └───────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## Library: hermes_mcp

Worth uses hermes_mcp (~> 0.14.1), the same library used by homunculus. It's already a transitive dependency through agentic.

Capabilities:
- Protocol versions: `2024-11-05`, `2025-03-26`, `2025-06-18` (auto-negotiation)
- Transports: stdio (subprocess via Erlang ports), Streamable HTTP (via Finch), WebSocket (via :gun), SSE (deprecated)
- Client: `use Hermes.Client` macro generates full client
- Server: `use Hermes.Server` macro with component system
- JSON-RPC 2.0: full message handling, request timeout/cancellation, progress notifications

## McpBroker

DynamicSupervisor managing all MCP server connections:

```elixir
defmodule Worth.Mcp.Broker do
  use DynamicSupervisor
  def init(_opts), do: DynamicSupervisor.init(strategy: :one_for_one)
end
```

Connection lifecycle:
1. Build transport from config (stdio or Streamable HTTP)
2. Start HermesClient as child (registered via Worth.McpRegistry)
3. Send `initialize` to negotiate protocol version and capabilities
4. Discover tools: `Hermes.Client.Base.list_tools/2`
5. Register tools in Worth.Mcp.ToolIndex + Worth.Mcp.Gateway
6. Start Worth.Mcp.ConnectionMonitor for health checks

## Tool Execution Flow

```
Agent calls use_tool("github:search_repos", %{"query" => "elixir"})
    → Mcp.Gateway.execute
    → Mcp.ToolIndex.find_server → :github
    → Mcp.Registry.lookup_client → client_pid
    → Hermes.Client.Base.call_tool(client_pid, "github:search_repos", args)
    → Transport sends JSON-RPC to MCP server process
    → MCP server executes, returns result
    → Response decoded and returned to agent
```

Tool names are namespaced: `server_name:tool_name` to prevent collisions.

## McpConnectionMonitor

- 30s health check interval (ping)
- Exponential backoff reconnection: 1s → 2s → 4s → ... → 30s max
- Max 10 reconnect attempts before marking :failed
- PubSub broadcasts: `:connected`, `:reconnecting`, `:failed`

## MCP Resources & Prompts

**Resources**: indexed by URI, available via read or system prompt injection. `notifications/resources/list_changed` triggers re-indexing.

**Prompts**: registered as `/mcp:server:prompt_name` slash commands. `notifications/prompts/list_changed` triggers re-registration.

## Configuration

### Global (always active)

```elixir
# ~/.worth/config.exs
config :worth,
  mcp: [
    servers: %{
      filesystem: %{
        type: :stdio,
        command: "npx",
        args: ["-y", "@anthropic/mcp-server-filesystem", "/home/user/projects"],
        env: %{},
        autoconnect: true
      },
      github: %{
        type: :stdio,
        command: "npx",
        args: ["-y", "@anthropic/mcp-server-github"],
        env: %{"GITHUB_PERSONAL_ACCESS_TOKEN" => {:env, "GITHUB_TOKEN"}},
        autoconnect: true
      }
    }
  ]
```

### Workspace Overrides (merge-style)

```json
{
  "mcpServers": {
    "postgres": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-server-postgres", "postgresql://localhost/myapp"],
      "autoconnect": true
    }
  }
}
```

Workspace config wins for conflicting server names. Everything else stays global.

## MCP Tools Exposed to Agent

| Tool | Purpose |
|------|---------|
| `setup_mcp_server` | Connect to a new MCP server at runtime |
| `search_tools` | Discover available tools by query |
| `use_tool` | Execute any tool (builtin or MCP) |
| `get_tool_schema` | Get full JSON Schema for a tool |
| `activate_tool` | Promote discovered tool into LLM context |
| `deactivate_tool` | Remove tool from LLM context |
| `mcp_list_servers` | List all connected MCP servers |
| `mcp_server_status` | Detailed server status |

## Worth as MCP Server

Worth can expose itself as an MCP server, enabling other MCP clients (Claude Desktop, VS Code, Cursor) to use worth's capabilities.

```elixir
defmodule Worth.Mcp.Server do
  use Hermes.Server

  @impl true
  def handle_list_tools(_params) do
    {:ok, [
      %{name: "worth_chat", description: "Send a message to worth and get a response", inputSchema: %{...}},
      %{name: "worth_memory_query", description: "Search worth's global knowledge store", inputSchema: %{...}},
      %{name: "worth_memory_write", description: "Store a fact in worth's knowledge store", inputSchema: %{...}},
      %{name: "worth_skill_list", description: "List all installed and learned skills", inputSchema: %{...}}
    ]}
  end

  @impl true
  def handle_call_tool("worth_chat", %{"message" => msg}, _ctx) do
    {:ok, Worth.Brain.external_call(msg)}
  end
end
```

The server runs on Streamable HTTP (configurable port) and stdio (for CLI piping). Worth exposes its memory and skill capabilities as MCP tools so other agents can query worth's knowledge.

## Recommended Servers

| Server | Package | Auto-connect |
|--------|---------|-------------|
| filesystem | `@anthropic/mcp-server-filesystem` | Yes |
| fetch | `@anthropic/mcp-server-fetch` | Yes |
| sequential-thinking | `@anthropic/mcp-server-sequential-thinking` | Yes |
| git | `@anthropic/mcp-server-git` | No |
| github | `@anthropic/mcp-server-github` | No |
| brave-search | `@anthropic/mcp-server-brave-search` | No |
| postgres | `@anthropic/mcp-server-postgres` | No |
| slack | `@anthropic/mcp-server-slack` | No |

## Slash Commands

| Command | Action |
|---------|--------|
| `/mcp list` | List all servers with connection status |
| `/mcp add <name>` | Add server interactively |
| `/mcp remove <name>` | Remove server |
| `/mcp connect <name>` | Connect a disconnected server |
| `/mcp disconnect <name>` | Disconnect a server |
| `/mcp tools <name>` | List tools from a server |
| `/mcp status <name>` | Detailed server status |
