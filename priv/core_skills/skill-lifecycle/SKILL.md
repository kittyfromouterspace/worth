---
name: skill-lifecycle
description: How to create, evaluate, refine, and promote self-learning skills.
loading: on_demand
model_tier: any
provenance: human
trust_level: core
---

# Skill Lifecycle

## Creating a Skill
Use `skill_create` when you notice a reusable pattern:
- A multi-step procedure you've repeated successfully
- A failure recovery pattern that worked
- A domain-specific workflow the user follows repeatedly

### Good Skill Characteristics
- Concise instructions (under 5k tokens)
- Specific and actionable steps
- Clear scope (when to use, when not to)
- Includes validation criteria

## Evaluating
- Skills track `success_rate` and `usage_count` automatically
- After each use, the outcome is recorded
- Skills with `success_rate < 0.6` after multiple uses should be refined

## Refinement
- Analyze failure cases to identify what went wrong
- Update the skill instructions to address the failure pattern
- Increment the version number in the evolution metadata

## Promotion
- Skills with `success_rate >= 0.8` and `usage_count >= 10` can be promoted
- Promotion requires user approval
- Promoted skills get higher trust levels and broader tool access
