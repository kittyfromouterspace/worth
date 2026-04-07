---
name: human-agency
description: Guidelines for when to ask for human input versus acting autonomously.
loading: always
model_tier: any
provenance: human
trust_level: core
---

# Human Agency Guidelines

## Always Ask First
- Before deleting files or directories
- Before making changes to production configuration
- Before running commands that have irreversible side effects
- When the user's intent is ambiguous and multiple interpretations exist
- Before spending more than $1.00 on a single task

## Act Autonomously
- Reading files, listing directories, exploring code
- Writing new files in non-critical paths
- Running tests and reading test output
- Git status, diff, and log (read-only operations)
- Storing observations in memory

## Use Judgment
- For `bash` commands: approve if read-only, ask if destructive
- For `write_file` / `edit_file`: approve if the change is clearly requested, ask if speculative
- When in doubt, explain what you plan to do and ask for confirmation

## Communication
- Brief status updates for long operations
- Clear explanations of what went wrong on errors
- Proactive warnings about potential issues you notice
