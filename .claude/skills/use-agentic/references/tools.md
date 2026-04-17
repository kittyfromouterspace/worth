# Tools Reference

## File Tools

Defined in `Agentic.Tools`. All paths are relative to the workspace root.

### `read_file`

```json
{
  "name": "read_file",
  "input_schema": {
    "type": "object",
    "properties": {
      "path": {"type": "string"},
      "offset": {"type": "integer", "description": "Starting line number (1-based)"},
      "limit": {"type": "integer", "description": "Number of lines to read"}
    },
    "required": ["path"]
  }
}
```

Returns file content with line numbers. Use `offset` and `limit` for large files.

### `write_file`

```json
{
  "name": "write_file",
  "input_schema": {
    "type": "object",
    "properties": {
      "path": {"type": "string"},
      "content": {"type": "string"}
    },
    "required": ["path", "content"]
  }
}
```

Creates or overwrites a file. Parent directories are created automatically.

### `edit_file`

```json
{
  "name": "edit_file",
  "input_schema": {
    "type": "object",
    "properties": {
      "path": {"type": "string"},
      "old_text": {"type": "string", "description": "Exact text to find and replace"},
      "new_text": {"type": "string", "description": "Replacement text"}
    },
    "required": ["path", "old_text", "new_text"]
  }
}
```

Surgical edit. `old_text` must match exactly (including whitespace). Errors if
`old_text` matches multiple locations — provide more context to make it unique.

### `list_files`

```json
{
  "name": "list_files",
  "input_schema": {
    "type": "object",
    "properties": {
      "pattern": {"type": "string", "description": "Glob pattern (default: '**/*')"}
    }
  }
}
```

Lists files matching a glob pattern. Searches all allowed roots.

### `bash`

```json
{
  "name": "bash",
  "input_schema": {
    "type": "object",
    "properties": {
      "command": {"type": "string"},
      "timeout": {"type": "integer", "description": "Timeout in seconds (default 60, max 300)"}
    },
    "required": ["command"]
  }
}
```

Executes shell commands in the workspace directory. Commands are sandboxed
via `Agentic.Sandbox.Runner`. Output truncated at 1MB.

## Delegation Tool

### `delegate_task`

Defined in `Agentic.Subagent.DelegateTask`.

```json
{
  "name": "delegate_task",
  "input_schema": {
    "type": "object",
    "properties": {
      "task": {"type": "string", "description": "Task description for the subagent"},
      "max_turns": {"type": "integer", "description": "Max turns (default 20, max 50)"}
    },
    "required": ["task"]
  }
}
```

Spawns a bounded subagent that runs `Agentic.run/1` with its own context.
Maximum nesting depth: 3. Subagent inherits workspace and callbacks.

## Skill Tools

Defined in `Agentic.Tools.Skill`.

| Tool | Required Input | Description |
|------|---------------|-------------|
| `skill_list` | (none) | Lists all installed skills |
| `skill_read` | `skill_name` | Reads full SKILL.md instructions |
| `skill_search` | `query` | Searches public registries |
| `skill_info` | `repo` | Fetches info before installing |
| `skill_install` | `repo` | Installs from GitHub (`owner/repo/skill-name`) |
| `skill_remove` | `skill_name` | Removes installed skill |
| `skill_analyze` | `skill_name` | Analyzes model tier requirements |

## Memory Tools

Defined in `Agentic.Tools.Memory`.

| Tool | Required Input | Description |
|------|---------------|-------------|
| `memory_query` | (none) | Searches knowledge store. Optional `query` and `entry_type` |
| `memory_write` | `content` | Persists to knowledge store. Optional `entry_type`, `summary` |
| `memory_note` | `key`, `value` | In-process working memory with optional `ttl` and `priority` |
| `memory_recall` | `query` | Searches in-process working memory |

## Tool Gateway

Defined in `Agentic.Tools.Gateway`.

| Tool | Required Input | Description |
|------|---------------|-------------|
| `search_tools` | `query` | Discovers external tools. Optional `category` filter |
| `use_tool` | `tool_name` | Executes external tool (MCP, OpenAPI). Optional `arguments` |
| `get_tool_schema` | `tool_name` | Gets full input schema for an external tool |
| `activate_tool` | `tool_name` | Promotes external tool to first-class (appears in tool list) |
| `deactivate_tool` | `tool_name` | Removes activated tool, frees budget slot |

### Tool Activation

External tools start as "discovered" (only accessible via `use_tool`). Activating
a tool promotes it to first-class status — it appears as a direct tool in the LLM
request. Budget-limited (default 10 slots). LRU eviction when exceeded.

State is in `ctx.activation`, not a separate process.

## Extension Modules

Tool execution dispatches to three extension modules in order:
1. `Agentic.Tools.Skill` — skill-related tools
2. `Agentic.Tools.Gateway` — tool discovery and external execution
3. `Agentic.Tools.Memory` — memory and knowledge store tools

If no extension handles the tool, falls back to core file tools and `delegate_task`.
