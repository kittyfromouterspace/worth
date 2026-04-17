# Appendix A: Skills Research & Design Rationale

## A.1 Anthropic Agent Skills Standard

In December 2025, Anthropic published the [Agent Skills](https://agentskills.io/) specification as an open standard. It is now supported by 30+ agent products including Claude Code, Cursor, OpenCode, Gemini CLI, VS Code, GitHub Copilot, OpenHands, Goose, Amp, Letta, Spring AI, and more.

The specification defines:
- **SKILL.md format**: YAML frontmatter (`name`, `description` required; `license`, `compatibility`, `metadata`, `allowed-tools` optional) followed by Markdown instructions
- **Directory structure**: `SKILL.md` + optional `scripts/`, `references/`, `assets/` directories
- **Progressive disclosure**: three-level loading (metadata → instructions → resources)
- **Naming constraints**: max 64 chars, lowercase + hyphens, no consecutive hyphens

Worth adopts this standard to ensure skill portability. A skill written for Claude Code should work in worth with no changes.

## A.2 MCP Complementarity

| MCP Primitive | Control | Maps to Worth |
|---------------|---------|---------------|
| **Tools** (model-controlled) | LLM decides when to invoke | agentic tool definitions |
| **Resources** (app-driven) | Host decides what to include | workspace identity files, MEMORY.md |
| **Prompts** (user-controlled) | User explicitly invokes | slash commands, on_demand skills |

A skill can teach the agent how to use an MCP server's tools. MCP provides the tools; skills provide the instructions for using them.

## A.3 Self-Learning Skills: Research Foundation

### Memento-Skills (Zhou et al., 2026) -- https://arxiv.org/abs/2603.18743
- "Agent-designing agent" that autonomously constructs and improves task-specific agents
- Skills stored as structured markdown (SKILL.md pattern) serve as persistent, evolving memory
- "Read-Write Reflective Learning": router selects relevant skills, writer updates them
- 26.2% improvement on General AI Assistants benchmark
- Key insight: skills as stateful, evolving prompts rather than static instructions

### SkillX (Wang et al., 2026) -- https://arxiv.org/abs/2604.04804
- Fully automated pipeline for constructing skill knowledge bases
- Three-level skill hierarchy: strategic plans → functional skills → atomic skills
- Iterative Skills Refinement: automatic revision based on execution feedback
- Exploratory Skills Expansion: proactively generates novel skills beyond seed data
- Key insight: skills should be automatically evaluated and refined, not just created

### SkillRL (Xia et al., 2026) -- https://arxiv.org/abs/2602.08234
- SkillBank: hierarchical skill library co-evolving with agent policy
- Skills distilled from raw experience trajectories
- Adaptive retrieval for general and task-specific heuristics
- 15.3% improvement on ALFWorld, WebShop
- Key insight: the skill library should co-evolve with the agent, not be static

### MetaClaw (Xia et al., 2026) -- https://arxiv.org/abs/2603.17187
- Production-scale continual meta-learning
- Analyzes failure trajectories to synthesize new skills (zero downtime)
- Versioning mechanism to separate support/query data
- 32% relative accuracy improvement
- Key insight: version management and data contamination prevention are critical

### SAGE (Wang et al., 2025) -- https://arxiv.org/abs/2512.17102
- Sequential Rollout: agents traverse chains of similar tasks, skills accumulate
- Skill-integrated Reward: RL signal accounting for skill quality
- 8.9% higher goal completion with 26% fewer steps
- Key insight: measure both task outcome AND skill utilization quality

### ELL Framework (Cai et al., 2025) -- https://arxiv.org/abs/2508.19005
- Four principles: Experience Exploration, Long-term Memory, Skill Learning, Knowledge Internalization
- Skill learning: abstracting recurring patterns into reusable skills, actively refined
- Key insight: skills should compress raw experience into high-level reusable patterns

## A.4 Risks of Self-Evolving Skills

### Misevolution (Shao et al., ICLR 2026) -- https://arxiv.org/abs/2509.26354
- Self-evolution can degrade capabilities even on top-tier LLMs
- Four risk pathways: model evolution, memory evolution, tool evolution, workflow evolution
- Mitigation: sandboxed testing, version rollback, safety alignment checks

### Security (Xu & Yan, 2025) -- https://arxiv.org/abs/2602.12430
- 26.1% of community-contributed skills contain vulnerabilities
- Proposed Skill Trust and Lifecycle Governance Framework
- Mitigation: provenance-based permissions, gate-based deployment, audit trails

### Worth Mitigations
1. **Trust levels** -- learned skills start with restricted permissions
2. **Sandboxed testing** -- validated before promotion
3. **Version rollback** -- every version kept
4. **Human gate** -- promotion requires explicit user approval
5. **Audit trail** -- `evolution` metadata tracks everything
6. **No self-promotion** -- agent creates/refines but cannot promote without user action
