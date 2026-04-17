# Tools

## Core File Tools (from agentic)

| Tool | Purpose |
|------|---------|
| `read_file` | Read file with line numbers, offset/limit |
| `write_file` | Create/overwrite file |
| `edit_file` | Surgical text replacement |
| `bash` | Shell command execution |
| `list_files` | Glob file listing |

## Memory Tools (from agentic)

| Tool | Purpose |
|------|---------|
| `memory_query` | Search global knowledge store |
| `memory_write` | Store in global knowledge store |
| `memory_note` | Store in ContextKeeper working set (session-local) |
| `memory_recall` | Retrieve from ContextKeeper (session-local) |

## Skill Tools (from agentic)

| Tool | Purpose |
|------|---------|
| `skill_list` | List all skills with metadata |
| `skill_read` | Read full SKILL.md content |
| `skill_search` | Search for skills on GitHub |
| `skill_install` | Install skill from GitHub |
| `skill_remove` | Remove skill |
| `skill_analyze` | Analyze skill requirements |

## Kit Tools

| Tool | Purpose |
|------|---------|
| `kit_search` | Search JourneyKits for workflows |
| `kit_install` | Install a kit (skills + files) |
| `kit_list` | List installed kits |
| `kit_info` | Get kit details and dependencies |
| `kit_publish` | Package and publish a workflow as a kit |

## Gateway Tools (from agentic)

| Tool | Purpose |
|------|---------|
| `search_tools` | Discover available tools by query |
| `use_tool` | Execute any tool (builtin or MCP) by name |
| `get_tool_schema` | Get full JSON Schema for a tool |
| `activate_tool` | Promote discovered tool into LLM context |
| `deactivate_tool` | Remove tool from LLM context |

## Worth-Specific Extensions

Registered as agentic extension modules:

```elixir
Agentic.Tools.register_extension(Worth.Tools.Workspace)
Agentic.Tools.register_extension(Worth.Tools.Web)
Agentic.Tools.register_extension(Worth.Tools.Git)
Agentic.Tools.register_extension(Worth.Tools.Mcp)
```

| Tool | Module | Purpose |
|------|--------|---------|
| `workspace_status` | `Worth.Tools.Workspace` | Current workspace info |
| `workspace_switch` | `Worth.Tools.Workspace` | Switch to different workspace |
| `workspace_list` | `Worth.Tools.Workspace` | List all workspaces |
| `web_fetch` | `Worth.Tools.Web` | Fetch and parse URL content |
| `web_search` | `Worth.Tools.Web` | Search the web (via API) |
| `git_diff` | `Worth.Tools.Git` | Show git diff |
| `git_log` | `Worth.Tools.Git` | Show git history |
| `git_status` | `Worth.Tools.Git` | Show working tree status |
| `mcp_list_servers` | `Worth.Tools.Mcp` | List connected MCP servers |
| `mcp_server_status` | `Worth.Tools.Mcp` | Detailed MCP server status |
| `setup_mcp_server` | `Worth.Tools.Mcp` | Connect to MCP server at runtime |

## MCP Tool Execution

MCP tools are namespaced with `server_name:tool_name` and routed through the McpBroker:

```
use_tool("github:search_repos", %{"query" => "elixir"})
    → Mcp.Gateway.execute
    → Mcp.ToolIndex.find_server → :github
    → Mcp.Registry.lookup_client → client_pid
    → Hermes.Client.Base.call_tool(client_pid, "github:search_repos", args)
    → MCP server execution
    → Result returned to agent
```
