---
name: tool-discovery
description: Lazy tool discovery pattern. Search before using, activate on demand.
loading: always
model_tier: any
provenance: human
trust_level: core
---

# Tool Discovery

## Pattern
1. Before using a tool, consider if there are other tools available
2. Use `search_tools` to discover tools relevant to the current task
3. Use `get_tool_schema` to understand a tool's parameters before calling it
4. Tools are registered in categories: file, memory, skill, git, web, workspace

## Available Tool Categories
- **File tools**: `read_file`, `write_file`, `edit_file`, `bash`, `list_files`
- **Memory tools**: `memory_query`, `memory_write`, `memory_note`, `memory_recall`
- **Skill tools**: `skill_list`, `skill_read`, `skill_install`, `skill_remove`, `skill_create`
- **Git tools**: `git_diff`, `git_log`, `git_status`
- **Web tools**: `web_fetch`, `web_search`
- **Workspace tools**: `workspace_status`, `workspace_list`, `workspace_switch`

## Workflow
1. Assess what information you need
2. Search for relevant tools if unsure
3. Read the schema before first use
4. Prefer specific tools over `bash` when available
