# Vision

Worth is a single-user, terminal-native AI assistant built on Elixir/BEAM. One central brain operates across multiple workspaces, can write code and do general research, and is extensible through a skills system with self-learning. Everything runs locally in one BEAM node -- no containers, no VMs, no web server.

The design strips away the multi-user, billing, and deployment complexity of Homunculus while preserving its core agent architecture: the agent runtime (agentic), the memory engine (recollect), the skills system, and the workspace model.

## One Brain, One Memory

The core architectural shift from homunculus is the unification of memory. Homunculus scoped everything per-user, per-workspace. Worth is a single-user system with a **single global knowledge store**. Every workspace draws from the same collective knowledge. Workspaces are not memory silos -- they are lenses. Each workspace has an **overlay** that layers workspace-specific context (project identity, local skills, project conventions) on top of the global knowledge base.

This means:
- A pattern learned in one workspace (e.g., "user prefers conventional commits") is available everywhere
- MCP integrations configured once are available globally (with optional per-workspace overrides)
- Skills created by the agent are global artifacts that any workspace can use
- The brain sees the full picture -- no partitioned context

## What Worth Does

- **Code**: Read, write, edit, refactor, run commands, manage git in any workspace
- **Research**: Search the web, fetch URLs, analyze documents, synthesize information
- **Remember**: Persistent knowledge across sessions via recollect (vector search + knowledge graph + memory decay)
- **Learn**: Self-improving skills that get better with use (create, test, refine, promote)
- **Extend**: Connect to external services via MCP (GitHub, databases, search, Slack, etc.)
- **Adapt**: Multiple LLM providers with smart model routing (Anthropic, OpenAI, OpenRouter)

## What Worth Does Not Include

Homunculus features explicitly excluded:

- Multi-user authentication and authorization
- Billing/Stripe integration
- Firecracker microVMs and container orchestration
- Web UI (Phoenix LiveView)
- Agent-to-agent communication via MCP
- Marketplace (agent-to-agent task delegation)
- Bot integrations (Slack, Discord)
- WebRTC browser streaming
- Team workspaces
- Google Drive sync
- Admin dashboard
- Oban background jobs

These can be added later if needed but are not part of the core vision.
