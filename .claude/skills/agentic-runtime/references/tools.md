# Tools Quick Reference

## File Tools

### read_file
- **Required**: `path` (string)
- **Optional**: `offset` (integer, 1-based), `limit` (integer)
- Returns file content with line numbers

### write_file
- **Required**: `path`, `content`
- Creates or overwrites. Parent dirs created automatically.

### edit_file
- **Required**: `path`, `old_text`, `new_text`
- `old_text` must match exactly. Errors on multiple matches.

### list_files
- **Optional**: `pattern` (default `**/*`)
- Returns files matching glob across all allowed roots.

### bash
- **Required**: `command`
- **Optional**: `timeout` (seconds, default 60, max 300)
- Sandbox-wrapped. Output truncated at 1MB.

## Delegation

### delegate_task
- **Required**: `task`
- **Optional**: `max_turns` (default 20, max 50)
- Max nesting depth: 3.

## Skills

| Tool | Required | Description |
|------|----------|-------------|
| `skill_list` | — | List installed skills |
| `skill_read` | `skill_name` | Read SKILL.md instructions |
| `skill_search` | `query` | Search public registries |
| `skill_info` | `repo` | Info before installing |
| `skill_install` | `repo` | Install from GitHub |
| `skill_remove` | `skill_name` | Remove skill |
| `skill_analyze` | `skill_name` | Analyze model tier needs |

## Memory

| Tool | Required | Description |
|------|----------|-------------|
| `memory_query` | — | Search knowledge store |
| `memory_write` | `content` | Persist to knowledge store |
| `memory_note` | `key`, `value` | In-process working memory |
| `memory_recall` | `query` | Search working memory |

## Tool Gateway

| Tool | Required | Description |
|------|----------|-------------|
| `search_tools` | `query` | Discover external tools |
| `use_tool` | `tool_name` | Execute external tool |
| `get_tool_schema` | `tool_name` | Get external tool schema |
| `activate_tool` | `tool_name` | Promote to first-class |
| `deactivate_tool` | `tool_name` | Remove from active list |

Activation budget: 10 slots (default). LRU eviction on overflow.
