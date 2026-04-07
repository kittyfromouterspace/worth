# Worth

A terminal-based AI assistant built on Elixir/BEAM.

## What

Single-user, terminal-native AI assistant. One central brain operating across multiple workspaces. Can write code and do general research. Extensible through a skills system with self-learning. Connects to the world through MCP.

## Docs

| Doc | Description |
|-----|-------------|
| [vision.md](docs/vision.md) | What worth is and why it exists |
| [architecture.md](docs/architecture.md) | System architecture, dependency graph, component overview |
| [beam-architecture.md](docs/beam-architecture.md) | Supervision tree, ETS/:persistent_term strategy, telemetry, PubSub, error handling |
| [database-layer.md](docs/database-layer.md) | Ash + AshPostgres analysis, coexistence with mneme, skill lifecycle modeling |
| [memory.md](docs/memory.md) | Unified global memory, workspace overlays, knowledge lifecycle |
| [brain.md](docs/brain.md) | The central brain GenServer, callbacks, system prompt assembly |
| [workspaces.md](docs/workspaces.md) | Workspace model, types, lifecycle, directory structure |
| [skills.md](docs/skills.md) | Agent Skills standard, self-learning lifecycle, trust levels |
| [kits.md](docs/kits.md) | JourneyKits integration: workflow registry, install, publish |
| [mcp.md](docs/mcp.md) | MCP integration: broker, tools, resources, config |
| [ui.md](docs/ui.md) | TermUI layout, Elm components, events, slash commands |
| [tools.md](docs/tools.md) | Tool registry: builtin, memory, skill, gateway, MCP |
| [config.md](docs/config.md) | File layout, config schema, workspace config |
| [project-structure.md](docs/project-structure.md) | Source code layout, module responsibilities |
| [implementation-strategy.md](docs/implementation-strategy.md) | Phased plan with deliverables |
| [risks.md](docs/risks.md) | Risks, mitigations, design decisions |
| [testing.md](docs/testing.md) | Test structure, patterns, infrastructure, per-phase coverage |
| [appendix-skills-research.md](docs/appendix-skills-research.md) | Skills research: agentskills.io, self-learning, risks |
| [appendix-mcp-research.md](docs/appendix-mcp-research.md) | MCP research: spec, hermes_mcp, ecosystem |

---

## Implementation Progress

### Phase 1: Skeleton & Core Loop -- COMPLETE

**Deliverable:** `worth` starts, shows a terminal chat, you type a question, it streams a response.

| Step | Status | Files |
|------|--------|-------|
| Mix project setup with dependencies | Done | `mix.exs`, `config/*.exs` |
| `Worth.Application` -- supervision tree | Done | `lib/worth/application.ex` |
| `Worth.Config` -- runtime config loading | Done | `lib/worth/config.ex` |
| `Worth.Repo` -- Ecto Repo for Mneme | Done | `lib/worth/repo.ex` |
| `Worth.UI.Root` -- Elm Architecture TUI component | Done | `lib/worth/ui/root.ex` |
| `Worth.Brain` -- GenServer, AgentEx integration | Done | `lib/worth/brain.ex`, `lib/worth/brain/supervisor.ex` |
| `Worth.LLM` -- multi-provider adapter (Anthropic, OpenAI, OpenRouter) | Done | `lib/worth/llm.ex`, `lib/worth/llm/*.ex` |
| `Worth.CLI` -- CLI entry point | Done | `lib/worth/cli.ex` |
| `Worth.Telemetry` -- telemetry span helper | Done | `lib/worth/telemetry.ex` |
| `Worth.Error` -- structured error type | Done | `lib/worth/error.ex` |
| `Worth.Workspace.Service` -- workspace CRUD | Done | `lib/worth/workspace/service.ex` |
| `Worth.Workspace.Context` -- system prompt assembly | Done | `lib/worth/workspace/context.ex` |
| `Worth.Persistence.Transcript` -- JSONL backend | Done | `lib/worth/persistence/transcript.ex` |
| System prompt template | Done | `priv/prompts/system.md` |
| Test infrastructure (DataCase, BrainCase) | Done | `test/support/*.ex`, `test/worth_test.exs` |
| Dependencies resolve and compile clean | Done | 0 warnings in worth code |

**Key decisions made during implementation:**

1. **TermUI API**: Uses `use TermUI.Elm` with `init/1`, `event_to_msg/2`, `update/2`, `view/1` callbacks. Rendering uses `text/2`, `box/2`, `stack/2` (imported from `TermUI.Component.Helpers`). Styles built with `Style.from/1` (not `Style.new/1`). App started via `TermUI.Runtime.run(root: module)`.

2. **mneme dependency override**: mneme is a path dep for worth but a git dep for agent_ex. Added `override: true` in worth's mix.exs to resolve the conflict.

3. **Brain async execution**: Brain delegates AgentEx.run to Task.Supervisor to keep the GenServer responsive. Agent events flow back via `send/2` to the UI process.

4. **Polling for events**: The UI polls for brain events every 100ms via `Command.interval/2`, using a non-blocking `receive after 0` pattern. This avoids needing a direct PID coupling between Brain and UI.

### Phase 2: Workspaces & File Tools -- COMPLETE

**Deliverable:** `worth -w my-project` opens in the project directory, agent can read and edit files.

| Step | Status | Files |
|------|--------|-------|
| `Worth.Workspace.Service` -- init, list, switch, create workspaces | Done | `lib/worth/workspace/service.ex` |
| Workspace scaffolding (IDENTITY.md, AGENTS.md, .worth/skills.json) | Done | `lib/worth/workspace/service.ex` |
| Brain switches to `:agentic` profile for code mode | Done | `lib/worth/brain.ex` (mode_to_profile/1) |
| agent_ex's core file tools available via default `:execute_tool` | Done | (inherited from agent_ex) |
| `Worth.Workspace.Context` -- system prompt assembly | Done | `lib/worth/workspace/context.ex` |
| `Worth.Brain` -- mode switching, workspace switching, tool permissions | Done | `lib/worth/brain.ex` |
| Tool permission system (`:on_tool_approval` callback) | Done | `lib/worth/brain.ex` (build_callbacks) |
| `Worth.Tools.Web` -- web_fetch, web_search | Done | `lib/worth/tools/web.ex` |
| `Worth.Tools.Git` -- git_diff, git_log, git_status | Done | `lib/worth/tools/git.ex` |
| `Worth.Tools.Workspace` -- workspace_status, workspace_list, workspace_switch | Done | `lib/worth/tools/workspace.ex` |
| `Worth.Persistence.Transcript` -- JSONL append per turn | Done | `lib/worth/persistence/transcript.ex` |
| UI: tool call/result rendering (blue >> tool, magenta << result) | Done | `lib/worth/ui/root.ex` (message_to_nodes) |
| UI: sidebar with workspace/tools/status tabs (Tab to toggle) | Done | `lib/worth/ui/root.ex` (render_sidebar) |
| UI: command history (Up/Down arrows) | Done | `lib/worth/ui/root.ex` (history_prev/next) |
| UI: header with mode indicator, turn counter, cost | Done | `lib/worth/ui/root.ex` (render_header) |
| Slash commands: /mode, /workspace list/switch/new, /status | Done | `lib/worth/ui/root.ex` (parse_command) |
| CLI: --mode flag, --init flag | Done | `lib/worth/cli.ex` |
| Tests: workspace service, brain switching | Done | `test/worth/workspace_test.exs`, `test/worth/brain_test.exs` |

**Key decisions made during implementation:**

1. **Mode/profile mapping**: `:code` -> `:agentic`, `:research` -> `:conversational`, `:planned` -> `:agentic_planned`, `:turn_by_turn` -> `:turn_by_turn`. Brain translates user-facing modes to agent_ex profiles.

2. **Tool permissions**: `bash` and `write_file` require approval by default. Everything else is auto-approved. The `:on_tool_approval` callback sends a notification to the UI and auto-approves for now (full human-in-the-loop approval UI comes in Phase 5).

3. **Worth-specific tools** (web_fetch, git_diff, etc.) are defined as extension modules with `definitions/0` and `execute/3` functions. They'll be registered as agent_ex extensions when wiring up the full tool pipeline (Phase 3/4).

4. **Event draining**: The UI polls every 50ms and drains ALL pending events in one batch. This avoids event buildup and ensures tool_call/tool_result messages appear inline in the chat.

5. **System prompt assembly**: `Worth.Workspace.Context.build_system_prompt/1` merges the base prompt (`priv/prompts/system.md`) with workspace identity files (IDENTITY.md, AGENTS.md).

### Phase 3: Unified Memory -- COMPLETE

**Deliverable:** Agent recalls prior conversations across all workspaces, extracts and persists facts globally.

| Step | Status | Files |
|------|--------|-------|
| Configure Mneme with global scope UUID | Done | `config/config.exs`, `config/dev.exs`, `config/test.exs` |
| `Worth.Memory.Manager` -- global retrieval with workspace boosting | Done | `lib/worth/memory/manager.ex` |
| `Worth.Memory.FactExtractor` -- response/tool fact extraction (LLM + deterministic) | Done | `lib/worth/memory/fact_extractor.ex` |
| Implement `:on_response_facts` callback (async fact extraction + storage) | Done | `lib/worth/brain.ex` (build_callbacks) |
| Implement `:on_tool_facts` callback (async tool result extraction) | Done | `lib/worth/brain.ex` (build_callbacks) |
| Wire `:knowledge_search/:create/:recent` through Memory.Manager | Done | `lib/worth/brain.ex` (build_callbacks) |
| System prompt integration: memory context within budget | Done | `lib/worth/workspace/context.ex` |
| WorkingMemory (ContextKeeper) per workspace: push/read/clear/flush | Done | `lib/worth/memory/manager.ex` (working_*) |
| Workspace deactivation flush: WorkingMemory -> global Mneme | Done | `lib/worth/brain.ex` (switch_workspace, flush_working_memory) |
| `Worth.Tools.Memory` -- memory_query, memory_write, memory_note, memory_recall | Done | `lib/worth/tools/memory.ex` |
| Wire memory tools into Brain execute_external_tool/search_tools/get_tool_schema | Done | `lib/worth/brain.ex` (build_callbacks) |
| `/memory query`, `/memory note`, `/memory recent` slash commands | Done | `lib/worth/ui/root.ex` (parse_command, update) |
| Outcome feedback: good/bad signals after successful/failed agent turns | Done | `lib/worth/brain.ex` (store_outcome_feedback) |
| User message pushed to working memory on each turn | Done | `lib/worth/brain.ex` (execute_agent_loop) |
| Worth.Config added to supervision tree (was missing) | Done | `lib/worth/application.ex` |
| PostgrexTypes for pgvector support | Done | `lib/worth/postgrex_types.ex`, `lib/worth/repo.ex` |
| Mneme migrations copied to worth | Done | `priv/repo/migrations/*.exs` |
| Tests: Memory.Manager, FactExtractor, Tools.Memory | Done | `test/worth/memory/`, `test/worth/tools/memory_test.exs` |

**Key decisions made during implementation:**

1. **Scope UUID**: Mneme's `scope_id` is `:binary_id` (UUID), not a string. Worth uses a fixed UUID `"00000000-0000-0000-0000-000000000001"` as the global scope. Workspace provenance is stored in entry `metadata.workspace`.

2. **Memory context in system prompt**: `Worth.Workspace.Context.build_system_prompt/2` now accepts an optional `user_message` parameter. When provided, it runs a memory search against the query; otherwise, it loads the 5 most recent entries. Memory context is capped at 4KB.

3. **Fact extraction**: `on_response_facts` and `on_tool_facts` run fact extraction asynchronously via `Task.Supervisor.start_child`. Extraction uses LLM when available (via a `llm_fn` closure), falling back to deterministic pattern matching for preference/commit-convention patterns.

4. **Working memory flush**: When switching workspaces, the Brain calls `flush_working_memory/1` which promotes high-importance (>=0.5) working memory entries to the global Mneme store with adjusted confidence.

5. **PostgrexTypes**: Worth defines `Worth.PostgrexTypes` using `Postgrex.Types.define` with `Pgvector.extensions()`. This is required for any query that touches the `embedding` field in mneme tables.

6. **Mneme migrations**: All 7 mneme migrations copied to `priv/repo/migrations/` to ensure all enhancement columns (emotional_valence, half_life_days, pinned, context_hints, handoffs, mipmaps) are available.

### Phase 4: Skills & Research Mode -- COMPLETE

**Deliverable:** agentskills.io-compatible skill system with self-learning foundation.

| Step | Status | Files |
|------|--------|-------|
| `Worth.Skill.Parser` -- parse SKILL.md with YAML frontmatter + worth extensions | Done | `lib/worth/skills/parser.ex` |
| `Worth.Skill.Validator` -- static validation (name, description, trust, body) | Done | `lib/worth/skills/validator.ex` |
| `Worth.Skill.Trust` -- provenance tracking, trust levels, tool access, promotion criteria | Done | `lib/worth/skills/trust.ex` |
| `Worth.Skill.Service` -- global skill CRUD: list, read, install, remove, record_usage | Done | `lib/worth/skills/service.ex` |
| `Worth.Skill.Registry` -- :persistent_term metadata cache for L1/L2 disclosure | Done | `lib/worth/skills/registry.ex` |
| `Worth.Skill.Evaluator` -- success rate tracking, promotion/refinement triggers | Done | `lib/worth/skills/evaluator.ex` |
| `Worth.Skill.Lifecycle` -- CREATE stage: from experience, from failure, promotion flow | Done | `lib/worth/skills/lifecycle.ex` |
| Ship 5 core skills (agent-tools, human-agency, tool-discovery, skill-lifecycle, self-improvement) | Done | `priv/core_skills/*/SKILL.md` |
| `Worth.Tools.Skills` -- skill_list, skill_read, skill_install, skill_remove, skill_create | Done | `lib/worth/tools/skills.ex` |
| Wire skill tools into Brain (search_tools, execute_external_tool, get_tool_schema) | Done | `lib/worth/brain.ex` |
| Integrate skills into system prompt (L1 metadata via Registry.metadata_for_prompt) | Done | `lib/worth/workspace/context.ex` |
| `/skill list`, `/skill read`, `/skill remove` slash commands | Done | `lib/worth/ui/root.ex` |
| Skill registry initialized on app startup | Done | `lib/worth/application.ex` |
| Tests: Parser, Validator, Trust, Tools.Skills | Done | `test/worth/skills/`, `test/worth/tools/skills_test.exs` |

**Key decisions made during implementation:**

1. **YAML frontmatter parsing**: Used `yaml_elixir` (transitive dep from agent_ex) for YAML parsing. Custom YAML serialization for `to_frontmatter_string/1` since `yaml_elixir` doesn't support writing.

2. **Core skills location**: `priv/core_skills/` bundled with the app. User skills at `~/.worth/skills/`. Learned skills at `~/.worth/skills/learned/`. Path resolution checks core → user → learned in order.

3. **Registry via :persistent_term**: Skill metadata indexed in `:persistent_term` for nanosecond reads. Refreshed on skill install/remove/usage update. Initialized asynchronously on app startup via a dedicated Task.Supervisor.

4. **Progressive disclosure**: L1 metadata (name + description) for all skills injected into system prompt via `Worth.Skill.Registry.metadata_for_prompt/0`. L2 (full body) via `skill_read` tool. L3+ via `read_file` on skill directory.

5. **Trust levels and tool access**: Core/installed = full access, learned = restricted to allowed_tools list, unverified = read-only tools. Promotion requires success_rate >= 0.7/0.8 and usage_count >= 5/10 plus user approval.

### Phase 5: Self-Learning Skills & Polish -- COMPLETE

**Deliverable:** Self-learning skills with full lifecycle, multi-provider, polished UX.

| Step | Status | Files |
|------|--------|-------|
| `Worth.Skill.Refiner` -- reactive refinement (analyze failures, update skills) + proactive review | Done | `lib/worth/skills/refiner.ex` |
| `Worth.Skill.Versioner` -- version management, rollback, history | Done | `lib/worth/skills/versioner.ex` |
| `Worth.LLM.Router` -- primary/lightweight tier routing | Done | `lib/worth/llm/router.ex` |
| `Worth.UI.Theme` -- configurable dark/light/minimal themes with style_for | Done | `lib/worth/ui/theme.ex` |
| `Worth.Brain.Session` -- session resumption via AgentEx.resume/1 | Done | `lib/worth/brain/session.ex` |
| Wire Refiner into Brain (skill failure -> reactive refinement, proactive review after turns) | Done | `lib/worth/brain.ex` |
| Wire Versioner into Brain (skill_history, skill_rollback) + UI commands | Done | `lib/worth/brain.ex`, `lib/worth/ui/root.ex` |
| Wire Session into Brain (resume_session, list_sessions) + UI commands | Done | `lib/worth/brain.ex`, `lib/worth/ui/root.ex` |
| Theme integration in UI rendering (header, messages, tool calls, thinking) | Done | `lib/worth/ui/root.ex` |
| Cost limit enforcement (warns on cost events, checks against config limit) | Done | `lib/worth/brain.ex` |
| Memory-skill provenance (Mneme entries tagged with skill via metadata) | Done | `lib/worth/memory/manager.ex` |
| Fix compile errors (refiner missing end, adapter_for private, Style module, Transcript arity) | Done | Multiple files |
| UI commands: /skill history, /skill rollback, /skill refine, /session list, /session resume | Done | `lib/worth/ui/root.ex` |
| `Worth.LLM.adapter_for/1` made public for Router access | Done | `lib/worth/llm.ex` |
| `Worth.Persistence.Transcript.list_sessions/2` arity fix per behaviour | Done | `lib/worth/persistence/transcript.ex` |
| Tests: Refiner, Versioner, Router, Theme | Done | `test/worth/skills/refiner_test.exs`, `test/worth/skills/versioner_test.exs`, `test/worth/llm/router_test.exs`, `test/worth/ui/theme_test.exs` |

**Key decisions made during implementation:**

1. **Refiner integration**: Brain triggers `Worth.Skill.Refiner.refine/2` (with LLM assistance) when skill tool failures are detected and `should_refine?` is true. Proactive review runs after every completed agent turn, checking all learned skills for the 20-use review cycle.

2. **Cost limit enforcement**: The `handle_info({:agent_event, {:cost, amount}}` handler checks cumulative cost against `config[:cost_limit]` (default $5.0). When exceeded, an error event is sent to the UI. The actual abort is handled by AgentEx's built-in `cost_limit` option.

3. **Theme system**: `Worth.UI.Theme` provides `style_for/1` and `status_indicator/1` used throughout the UI. Three presets (dark, light, minimal) override the default theme. Theme selection via `Worth.Config.get([:ui, :theme])`.

4. **Session resumption**: `Worth.Brain.Session.resume/4` builds callbacks matching the main Brain's callback structure and calls `AgentEx.resume/1` with transcript backend. The `/session list` command reads from `Worth.Persistence.Transcript`.

5. **Skill version history**: `Worth.Skill.Versioner` saves skill snapshots to `.worth/history/vN.md` before any modification. Rollback restores a previous version while saving the current state first.

6. **LLM Router**: `Worth.LLM.Router` supports `:primary` and `:lightweight` tiers. Providers can declare a `tier:` field in config. Lightweight tier is intended for fact extraction, refinement, and other background tasks.

### Phase 6: MCP Integration -- NOT STARTED

**Deliverable:** Agent can connect to MCP servers, discover tools, execute them.

### Phase 6: MCP Integration -- COMPLETE

**Deliverable:** Agent can connect to MCP servers, discover tools, execute them.

| Step | Status | Files |
|------|--------|-------|
| `Worth.Mcp.Config` -- load MCP server configs from global config + workspace overrides | Done | `lib/worth/mcp/config.ex` |
| `Worth.Mcp.Broker` -- DynamicSupervisor for MCP server connections | Done | `lib/worth/mcp/broker.ex` |
| `Worth.Mcp.Registry` -- ETS-based server PID lookup with metadata | Done | `lib/worth/mcp/registry.ex` |
| `Worth.Mcp.ToolIndex` -- tool_name → server_name mapping (namespaced) | Done | `lib/worth/mcp/tool_index.ex` |
| `Worth.Mcp.Client.Supervisor` -- wraps Hermes.Client.Supervisor per connection | Done | `lib/worth/mcp/client/supervisor.ex` |
| `Worth.Mcp.Gateway` -- lazy tool discovery, execution dispatcher, resources/prompts | Done | `lib/worth/mcp/gateway.ex` |
| `Worth.Mcp.ConnectionMonitor` -- 30s health checks, exponential backoff reconnection | Done | `lib/worth/mcp/connection_monitor.ex` |
| `Worth.Tools.Mcp` -- 5 tools: mcp_list_servers, mcp_server_tools, mcp_call_tool, mcp_connect, mcp_disconnect | Done | `lib/worth/tools/mcp.ex` |
| Wire MCP tools into Brain (execute_external_tool, search_tools, get_tool_schema) | Done | `lib/worth/brain.ex` |
| Namespaced tool execution: `server:tool_name` resolves via ToolIndex | Done | `lib/worth/brain.ex` |
| UI commands: /mcp list, /mcp connect, /mcp disconnect, /mcp tools | Done | `lib/worth/ui/root.ex` |
| MCP Broker + ConnectionMonitor added to supervision tree | Done | `lib/worth/application.ex` |
| Autoconnect on startup (servers with autoconnect: true) | Done | `lib/worth/application.ex` |
| Tests: Config, Registry, ToolIndex, Tools.Mcp | Done | `test/worth/mcp/`, `test/worth/tools/mcp_test.exs` |

**Key decisions made during implementation:**

1. **hermes_mcp Client API**: Uses `Hermes.Client.Supervisor.start_link/2` which manages both client GenServer and transport process (`one_for_all` strategy). The `Hermes.Client.Base` module provides `list_tools/2`, `call_tool/4`, `ping/2`, `list_resources/2`, `read_resource/3`, `list_prompts/2`, `get_prompt/4`.

2. **Tool namespacing**: MCP tools are indexed under both `tool_name` (plain) and `server:tool_name` (namespaced). Agent calls use the namespaced form to prevent collisions across servers. The `execute_external_tool` callback detects `:` in tool names to route to MCP.

3. **Connection lifecycle**: Broker starts `Worth.Mcp.Client.Supervisor` as a temporary child per connection. On startup, it calls `list_tools` to discover and register all tools in `ToolIndex`. The Registry stores client PIDs and metadata (tool count, connected_at, errors).

4. **Config merging**: Global config from `~/.worth/config.exs` is loaded first, workspace config from `.worth/mcp.json` merges on top (workspace wins for conflicts). Transport type is normalized from string to atom.

5. **ConnectionMonitor**: Runs every 30s, pings each connected server, triggers reconnect with exponential backoff (1s → 30s max, 10 attempts). Broadcasts events via Phoenix.PubSub on `:mcp_failed`, `:mcp_reconnected`.

6. **Protocol version selection**: STDIO defaults to `"2024-11-05"`, Streamable HTTP uses `"2025-03-26"` (required by that transport). Protocol negotiation happens automatically in the Hermes handshake.

### Phase 7: Advanced Features -- COMPLETE

**Deliverable:** Worth as MCP server, JourneyKits integration, planned/turn-by-turn modes.

| Step | Status | Files |
|------|--------|-------|
| `Worth.Mcp.Server` -- Hermes.Server exposing brain/memory/skills to MCP clients | Done | `lib/worth/mcp/server.ex` |
| Server tools: Chat, MemoryQuery, MemoryWrite, SkillList, SkillRead, WorkspaceStatus | Done | `lib/worth/mcp/server/tools/*.ex` |
| `Worth.Kits` -- JourneyKits search/install/publish REST client | Done | `lib/worth/kits.ex` |
| `Worth.Tools.Kits` -- 5 tools: kit_search, kit_install, kit_list, kit_info, kit_publish | Done | `lib/worth/tools/kits.ex` |
| Wire Kits into Brain (execute_external_tool, search_tools, get_tool_schema) | Done | `lib/worth/brain.ex` |
| UI commands: /kit search, /kit install, /kit list, /kit info | Done | `lib/worth/ui/root.ex` |
| Kit installation tracking in ~/.worth/installed_kits.json | Done | `lib/worth/kits.ex` |
| Kit skill extraction with :kit provenance into global skills directory | Done | `lib/worth/kits.ex` |
| Tests: Kits, Tools.Kits | Done | `test/worth/kits/`, `test/worth/tools/kits_test.exs` |

**Key decisions made during implementation:**

1. **Worth as MCP Server**: Uses `use Hermes.Server` with 6 component tools. Exposes `worth_chat`, `worth_memory_query`, `worth_memory_write`, `worth_skill_list`, `worth_skill_read`, `worth_workspace_status`. Runs on stdio (for CLI piping) or Streamable HTTP (for remote access). Other MCP clients (Claude Desktop, VS Code, Cursor) can connect to worth and use its memory and skills.

2. **JourneyKits integration**: `Worth.Kits` wraps the JourneyKits REST API using `Req`. Search is public (no auth). Install fetches the payload, extracts skills into `~/.worth/skills/` with `provenance: :kit`, writes source files to workspace, and tracks installation in `~/.worth/installed_kits.json`. Publish requires `JOURNEY_API_KEY` env var.

3. **Kit→Skill mapping**: Installed kit skills get `trust_level: :installed` and `provenance: :kit` with kit metadata. They flow through the existing skill system (Registry, progressive disclosure). No separate code path needed.

4. **Planned/Turn-by-turn modes**: Already wired in Phases 1-2 (`mode_to_agent_mode/1` maps `:planned` → `:agentic_planned`, `:turn_by_turn` → `:turn_by_turn`). AgentEx handles the loop behavior. Worth's Brain and UI already support mode switching via `/mode`.

5. **Sub-agent delegation**: Available via `AgentEx.Subagent.Coordinator` (transitive dep). Worth can delegate tasks by starting sub-agents with scoped callbacks. Not yet wired into tools (future enhancement).
