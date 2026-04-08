# Skill Template

This directory contains skill templates for common development tasks. Copy this structure to create new skills.

## Structure

```
skill_name/
└── SKILL.md
```

## SKILL.md Format

```markdown
---
name: skill-name
description: Brief description of what this skill does.
loading: auto    # auto, eager, never
model_tier: any # any, lightweight, primary
provenance: human # human, agent
trust_level: installed # core, installed, learned
---

# Skill Name

## When to Use
When to activate this skill.

## Core Concepts
...

## Examples
...

## Common Patterns
...

(End of file)
```

## Fields

| Field | Description |
|-------|-------------|
| `name` | kebab-case identifier |
| `description` | Short description (1-2 sentences) |
| `loading` | `auto` - activate on mention, `eager` - load at startup, `never` - manual |
| `model_tier` | `any`, `lightweight`, `primary` - which models work best |
| `provenance` | `human` - human-written, `agent` - AI-generated |
| `trust_level` | `core` - trusted, `installed` - reviewed, `learned` - experimental |

## Available Templates

- `tui-design` - Terminal UI design best practices
- `tui-implementation` - Production TUI implementation patterns
- `term-ui` - Elixir TermUI framework specific patterns
