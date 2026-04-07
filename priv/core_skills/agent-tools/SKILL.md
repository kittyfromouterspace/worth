---
name: agent-tools
description: Core file, memory, and workspace tool usage patterns for effective agent operation.
loading: always
model_tier: any
provenance: human
trust_level: core
---

# Agent Tools Usage

## File Operations
- Use `read_file` to understand existing code before making changes
- Use `list_files` to explore directory structure before diving in
- Use `edit_file` for targeted modifications; prefer it over `write_file` for existing files
- Use `write_file` only for new files or complete rewrites
- Use `bash` for running tests, git commands, and other CLI operations

## Memory
- Use `memory_query` to recall relevant facts from previous sessions
- Use `memory_write` to store important observations, decisions, and conventions
- Use `memory_note` for temporary session notes that may be promoted to long-term memory

## Workspace
- Use `workspace_status` to check current workspace context
- Files referenced without paths are relative to the workspace directory
- Always check AGENTS.md for project-specific instructions before writing code

## Best Practices
- Read before writing. Always understand context first
- Make small, incremental changes rather than large rewrites
- Run tests after making changes to verify correctness
- Store important findings in memory for future sessions
