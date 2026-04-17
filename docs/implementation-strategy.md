# Implementation Strategy

## Phase 1: Skeleton & Core Loop (Week 1-2)

**Goal:** Worth starts, renders a terminal UI, accepts input, calls an LLM, streams the response back.

Steps:
1. Mix project setup with agentic, phoenix_live_view, recollect, hermes_mcp dependencies
2. `Worth.Application` -- supervision tree (Brain, Repo, Agentic deps, McpRegistry)
3. `Worth.Config` -- load from `~/.worth/config.exs`
4. `Worth.Repo` -- Ecto Repo for Recollect, run migrations
5. `WorthWeb.ChatLive` -- Phoenix LiveView with chat input + message display
6. `Worth.Brain` -- GenServer, receive input, call Agentic.run/1 with `:conversational` profile
7. `Worth.LLM` -- implement `:llm_chat` callback for one provider (Anthropic)
8. `:on_event` callback -- stream text chunks to UI via PubSub
9. Basic rendering: user messages, assistant messages, tool call/result blocks

**Deliverable:** `worth` starts, shows a web chat in the browser, you type a question, it streams a response.

## Phase 2: Workspaces & File Tools (Week 2-3)

**Goal:** Agent can read, write, edit files in a workspace directory.

Steps:
1. `Worth.Workspace.Service` -- init, list, switch workspaces
2. Workspace scaffolding (IDENTITY.md, AGENTS.md) -- reuse agentic's WorkspaceService
3. Switch Brain to `:agentic` profile for code workspaces
4. Register agentic's core file tools
5. `Worth.Workspace.Context` -- system prompt assembly from identity files + global memory
6. `WorthWeb.ChatLive` -- workspace tab, tools tab, skills tab, status sidebar
7. Tool call/result rendering in LiveView
8. Tool permission system (`:on_tool_approval` callback)
9. Status display in LiveView -- cost tracking, turn counter

**Deliverable:** `worth -w my-project` opens in the project directory, agent can read and edit files.

## Phase 3: Unified Memory (Week 3-4)

**Goal:** Global knowledge store, workspace-aware retrieval, cross-session memory.

Steps:
1. Configure Recollect with global `scope_id: "worth"`
2. `Worth.Memory.Manager` -- orchestrate global retrieval with workspace boosting
3. Implement `:on_response_facts` and `on_tool_facts` callbacks (global storage with workspace tagging)
4. Start ContextKeeper per workspace (ephemeral session state)
5. Workspace deactivation flush: ContextKeeper → global recollect (tagged with workspace)
6. `:knowledge_search`, `:knowledge_create`, `:knowledge_recent` callbacks (all global)
7. System prompt integration: memory context within budget
8. `/memory query`, `/memory note` slash commands

**Deliverable:** Agent recalls prior conversations across all workspaces, extracts and persists facts globally.

## Phase 4: Skills & Research Mode (Week 4-5)

**Goal:** agentskills.io-compatible skill system with self-learning foundation, research mode.

Steps:
1. `Worth.Skill.Parser` -- parse SKILL.md with agentskills.io frontmatter + worth extensions
2. `Worth.Skill.Service` -- global skill CRUD: list, read, install (from GitHub), remove
3. `Worth.Skill.Validator` -- static validation
4. Ship core skills (agent-tools, human-agency, tool-discovery, skill-lifecycle, self-improvement)
5. Progressive disclosure: L1 metadata, L2 via skill_read, L3 via read_file
6. `/skill install`, `/skill list`, `/skill read` commands
7. `Worth.Tools.Web` -- web_fetch and web_search tools
8. Research workspace type with conversational profile
9. `/mode research` and `/mode code` switching
10. `Worth.Skill.Trust` -- provenance tracking, trust levels
11. `Worth.Skill.Lifecycle` -- CREATE stage: agent creates learned skills from experience
12. `Worth.Skill.Evaluator` -- TEST stage: success rate tracking

**Deliverable:** agentskills.io-compatible skill system with self-learning foundation.

## Phase 5: Self-Learning Skills & Polish (Week 5-7)

**Goal:** Complete skill lifecycle, multi-provider LLM, production UX.

Steps:
1. `Worth.Skill.Refiner` -- reactive refinement: analyze failures, update skills
2. `Worth.Skill.Versioner` -- version management, rollback
3. `Worth.Skill.Lifecycle` -- PROMOTE stage: user review flow
4. Memory-skill integration: Recollect entries tagged with skill provenance
5. Skill gap detection: Recollect knowledge search reveals patterns without skill coverage
6. Additional LLM providers (OpenAI, OpenRouter) with ModelRouter
7. Model routing: primary for complex tasks, lightweight for quick responses
8. Session resumption via Agentic.resume/1
9. `Worth.Theme` -- configurable themes (Standard, Cyberdeck, Fifth Element)
10. `Worth.UI.Commands` -- command history, command parsing
11. `WorthWeb.CommandHandler` -- slash command dispatch
12. Context compaction UI feedback, error handling, cost limits
13. `worth init` CLI command

**Deliverable:** Self-learning skills with full lifecycle, multi-provider, polished UX.

## Phase 6: MCP Integration (Week 7-8)

**Goal:** Full MCP client support, connect to external servers, discover and use their tools.

Steps:
1. `Worth.Mcp.Broker` -- DynamicSupervisor for MCP server connections
2. `Worth.Mcp.Registry` -- Elixir Registry for PID lookup
3. `Worth.Mcp.ToolIndex` -- Agent mapping tool_name → server_name
4. `Worth.Mcp.ConnectionMonitor` -- health checks, exponential backoff reconnection
5. `Worth.Mcp.Gateway` -- lazy tool discovery, execution dispatcher
6. `Worth.Mcp.Config` -- load from global config + workspace overrides
7. Transport support: stdio + Streamable HTTP
8. Bundle default servers: filesystem, fetch, sequential-thinking
9. `/mcp list`, `/mcp add`, `/mcp connect`, `/mcp tools` slash commands
10. MCP resources and prompts handling
11. `notifications/tools/list_changed` dynamic tool updates

**Deliverable:** Agent can connect to MCP servers, discover tools, execute them.

## Phase 7: Advanced Features (Week 8+)

- Planned mode with plan visualization in UI
- Codebase indexing via Recollect Tier 1 pipeline
- Turn-by-turn mode with approval UI
- Sub-agent delegation for parallel tasks
- Git integration tools (diff, log, status)
- Workspace templates for common project types
- Worth as MCP server (expose brain to other MCP hosts)
- JourneyKits integration (search, install, publish workflow kits)
- OAuth 2.0 authorization for remote MCP servers
