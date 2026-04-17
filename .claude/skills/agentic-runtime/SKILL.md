---
name: agentic-runtime
description: "Use this skill when working with the Agentic Elixir library. Consult for agent loop configuration, profiles, tools, callbacks, strategies, and testing patterns."
metadata:
  managed-by: usage-rules
---


<!-- usage-rules-skill-start -->
## Overview

Agentic is a composable AI agent runtime for Elixir (~> 1.19). It provides a
stage pipeline architecture where middleware-style stages wrap each other to
process agent turns.

## Quick Reference

### Entry Points

- `Agentic.run(prompt:, workspace:, callbacks:)` — primary entry point
- `Agentic.resume(session_id:, workspace:, callbacks:)` — resume a session
- `Agentic.new_workspace(path)` — scaffold a workspace

### Critical Convention: String Keys

All tool schemas, messages, content blocks, and LLM responses use **string keys**.

### Correct Tool Names

`read_file`, `write_file`, `edit_file`, `list_files`, `bash`, `delegate_task`,
`skill_list`, `skill_read`, `skill_search`, `skill_info`, `skill_install`,
`skill_remove`, `skill_analyze`, `memory_query`, `memory_write`, `memory_note`,
`memory_recall`, `search_tools`, `use_tool`, `get_tool_schema`, `activate_tool`,
`deactivate_tool`

### Callbacks

Only `:llm_chat` is required. All others are optional.

### Profiles

`:agentic` (default), `:agentic_planned`, `:turn_by_turn`, `:conversational`,
`:claude_code`, `:opencode`, `:codex`, `:acp`

### Phase Machine

Phases: `:init`, `:plan`, `:execute`, `:review`, `:verify`, `:done`.
Transitions go through `Agentic.Loop.Phase.transition/2` — never mutate directly.

## References

See the reference files for detailed information:
- [tools.md](references/tools.md) — Complete tool schemas
- [../usage-rules/loop.md](../../loop.md) — Pipeline stages and profiles
- [../usage-rules/callbacks.md](../../callbacks.md) — All callback signatures
- [../usage-rules/protocols.md](../../protocols.md) — AgentProtocol behaviour
- [../usage-rules/strategies.md](../../strategies.md) — Strategy behaviour
- [../usage-rules/testing.md](../../testing.md) — TestHelpers
<!-- usage-rules-skill-end -->
