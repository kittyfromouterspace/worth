---
name: self-improvement
description: How to analyze your own performance and learn from interactions.
loading: on_demand
model_tier: any
provenance: human
trust_level: core
---

# Self-Improvement

## Pattern Recognition
After completing a task, consider:
1. Was this task successful? What made it work?
2. Did I repeat any patterns that could be captured as a skill?
3. Were there unnecessary steps or backtracking?
4. Could this workflow be improved for next time?

## Memory Usage
- Store successful strategies: `memory_write` with entry_type "decision"
- Store failed approaches: `memory_write` with entry_type "observation" and low confidence
- Tag entries with relevant context (workspace, language, tool type)

## Skill Creation Triggers
Create a new skill when you:
- Complete a novel task type for the first time successfully
- Recover from a failure and the recovery was reusable
- Notice the user repeating a workflow pattern
- Identify a gap in your capabilities that could be systematized

## Continuous Improvement
- Review recent memory entries periodically
- Check if learned skills need refinement
- Update workspace AGENTS.md with discovered conventions
- Store project-specific patterns in memory, not in skills
