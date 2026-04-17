# Skills System

Worth's skill system is designed around three principles:

1. **Agent Skills compatibility** -- adopt the [agentskills.io](https://agentskills.io/) open standard (30+ agent products)
2. **Progressive disclosure** -- three-level context loading to stay within token budgets
3. **Self-learning from the start** -- create, test, refine, promote lifecycle with agent-driven evolution

## SKILL.md Format (agentskills.io Standard)

A skill is a directory containing a `SKILL.md` file:

```
skills/
├── git-workflow/
│   ├── SKILL.md              # Required: metadata + instructions
│   ├── scripts/              # Optional: executable code
│   │   └── commit-validate.sh
│   ├── references/           # Optional: documentation
│   │   └── CONVENTIONS.md
│   └── assets/               # Optional: templates, resources
│       └── commit-template.txt
```

**SKILL.md frontmatter** (agentskills.io required + worth extensions):

```yaml
---
name: git-workflow                          # required, max 64 chars, lowercase + hyphens
description: >                              # required, max 1024 chars
  Manages git operations for this project...
license: MIT
compatibility: Requires git 2.40+
metadata:
  author: worth
  version: "1.2.0"

# --- worth extensions ---
loading: always                             # always | on_demand | trigger:<event>
model_tier: any                             # primary | lightweight | any
provenance: human                           # human | agent | hybrid
trust_level: core                           # core | installed | learned | unverified
evolution:                                  # self-learning metadata (auto-maintained)
  created_at: "2026-04-07T10:00:00Z"
  created_by: human
  version: 3
  refinement_count: 2
  success_rate: 0.92
  usage_count: 47
  last_used: "2026-04-07T09:30:00Z"
  last_refined: "2026-04-06T14:00:00Z"
  superseded_by: null
  superseded_from: []
  feedback_summary: "Works well for feature branches."
---
```

## Progressive Disclosure (Three Levels)

| Level | When Loaded | Token Cost | Content |
|-------|------------|------------|---------|
| **L1: Metadata** | Always (at startup) | ~100 tokens/skill | `name` + `description` in system prompt |
| **L2: Instructions** | When skill is triggered | <5k tokens | Full SKILL.md body via `skill_read` |
| **L3+: Resources** | As needed (on demand) | Unlimited | `scripts/`, `references/`, `assets/` files |

## Trust Levels

| Trust Level | Source | Permissions |
|-------------|--------|-------------|
| `core` | Shipped with worth | Full tool access, always loaded |
| `installed` | Installed by user or via kit | Full tool access, on_demand |
| `learned` | Created/refined by agent | Tool access limited to `allowed-tools` |
| `unverified` | Installed from untrusted source | Read-only tools, sandboxed |

Promotion: `unverified → installed → core`, `learned → installed → core`. Kit-installed skills start at `installed` with `provenance: :kit`.

## Self-Learning Lifecycle

```
CREATE ──────► TEST ──────► REFINE ──────► PROMOTE
  ▲              │              │              │
  │              ▼              ▼              ▼
  │         (failure)     (iterate)      (production)
  └──────────────────────────────────────────────────┘
```

### CREATE

| Path | Trigger |
|------|---------|
| Experience distillation | After a novel successful task |
| Failure analysis | After a task fails and is retried |
| Explicit request | User says "learn from this" |
| Skill composition | Two skills frequently used together |
| Gap detection | Recollect reveals patterns without skill coverage |

### TEST

1. Static validation (format, frontmatter, file references)
2. Dry-run evaluation (test context, no real side effects)
3. A/B comparison (with/without skill)
4. Cross-domain check (no side effects on unrelated tasks)

If `success_rate < 0.6`, skip PROMOTE and enter REFINE immediately.

### REFINE

**Reactive**: failure triggers analysis → skill update → re-test.

**Proactive**: every 20 usages, review accumulated feedback, check if description matches usage, merge superseded skills, compress if too large.

Version management: `skills/name/.worth/history/v1.md`, `v2.md`, etc. User can `/skill revert name v2`.

### PROMOTE

Criteria: `success_rate >= 0.8`, `usage_count >= 10`, no changes in last 5 uses. Requires explicit user approval.

## Skill Tools

| Tool | Purpose | Who |
|------|---------|-----|
| `skill_list` | List all skills with metadata | Agent + user |
| `skill_read` | Load full SKILL.md into context | Agent |
| `skill_search` | Search for skills on GitHub | Agent + user |
| `skill_install` | Install skill from GitHub | User |
| `skill_remove` | Remove skill | User |
| `skill_analyze` | Analyze skill requirements | Agent |
| `skill_create` | Create a new skill | Agent |
| `skill_refine` | Trigger refinement | Agent |
| `skill_review` | Promote/demote, view history | User |
| `skill_revert` | Roll back to previous version | User |
| `skill_export` | Export as shareable archive | User |

## Core Skills (Shipped)

| Skill | Loading | Purpose |
|-------|---------|---------|
| `agent-tools` | always | Core file/memory/workspace tool usage patterns |
| `human-agency` | always | When to ask for input vs. act autonomously |
| `tool-discovery` | always | Lazy tool discovery and activation workflow |
| `skill-lifecycle` | on_demand | How to create, refine, and promote skills |
| `self-improvement` | on_demand | How to analyze own performance |

## Global Skill Storage

Skills are stored globally in `~/.worth/skills/`, not per-workspace. See [memory.md](memory.md) for the full unified memory architecture.

Workspaces specify which skills are active via `.worth/skills.json` and can override global skills with workspace-specific versions.
