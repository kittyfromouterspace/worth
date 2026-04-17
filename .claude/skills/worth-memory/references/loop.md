# Loop Pipeline

## Pipeline Architecture

Each stage wraps the next, receiving `ctx` and a `next` function. Stages can:
- Pass through: call `next.(ctx)`
- Short-circuit: return `{:done, result}`
- Transform: modify ctx before calling `next`
- Loop: call `next` multiple times

All stages implement `Agentic.Loop.Stage` behaviour with `call/2` and optional `model_tier/0`.

## Stage Modules

| Stage | Purpose |
|-------|---------|
| `Stages.ContextGuard` | Checks context window usage, triggers compaction, enforces cost limit |
| `Stages.ProgressInjector` | Injects system reminder after tool calls to prevent context drift |
| `Stages.LLMCall` | Makes LLM API call via callback, stores response in `ctx.last_response` |
| `Stages.ModeRouter` | Routes based on `(mode, phase, stop_reason)` — decides loop/terminate/compact |
| `Stages.TranscriptRecorder` | Records session events to transcript backend for resumption |
| `Stages.ToolExecutor` | Executes pending tool calls, re-enters pipeline |
| `Stages.CommitmentGate` | Intercepts unfulfilled commitments (e.g. "Let me analyze..." without tool use) |
| `Stages.PlanBuilder` | Injects structured plan-request prompt (agentic_planned only) |
| `Stages.PlanTracker` | Tracks plan step completion, transitions to :verify (agentic_planned only) |
| `Stages.VerifyPhase` | Injects verification prompt (agentic_planned only) |
| `Stages.WorkspaceSnapshot` | Gathers git/file/instruction context on first pass |
| `Stages.HumanCheckpoint` | Yields to human for approval (turn_by_turn only) |
| `Stages.CLIExecutor` | Executes via CLI protocol (claude_code/opencode/codex) |
| `Stages.ACPExecutor` | Executes via ACP protocol |

## Profile Stage Lists

### :agentic (default)
```
ContextGuard → ProgressInjector → LLMCall → ModeRouter → TranscriptRecorder → ToolExecutor → CommitmentGate
```

### :agentic_planned
```
WorkspaceSnapshot → ContextGuard → PlanBuilder → ProgressInjector → LLMCall → ModeRouter → TranscriptRecorder → ToolExecutor → PlanTracker → CommitmentGate
```

### :turn_by_turn
```
WorkspaceSnapshot → ContextGuard → LLMCall → ModeRouter → TranscriptRecorder → HumanCheckpoint → ToolExecutor → CommitmentGate
```

### :conversational
```
ContextGuard → LLMCall → ModeRouter → TranscriptRecorder
```

### :claude_code
```
ContextGuard → ProgressInjector → CLIExecutor → ModeRouter → TranscriptRecorder → ToolExecutor → CommitmentGate
```

### :opencode
Same stages as `:claude_code`.

### :codex
Same stages as `:claude_code`.

### :acp / {:acp, agent}
```
ContextGuard → ProgressInjector → ACPExecutor → ModeRouter → TranscriptRecorder → CommitmentGate
```

## Phase State Machine

### Mode Transitions

| Mode | From | Allowed Transitions |
|------|------|-------------------|
| `:agentic` | `:init` | `:execute` |
| `:agentic` | `:execute` | `:execute`, `:done` |
| `:agentic_planned` | `:init` | `:plan` |
| `:agentic_planned` | `:plan` | `:execute` |
| `:agentic_planned` | `:execute` | `:execute`, `:verify` |
| `:agentic_planned` | `:verify` | `:done` |
| `:turn_by_turn` | `:init` | `:review` |
| `:turn_by_turn` | `:review` | `:review`, `:execute` |
| `:turn_by_turn` | `:execute` | `:review`, `:done` |
| `:conversational` | `:init` | `:execute` |
| `:conversational` | `:execute` | `:done` |

### Initial Phases

- `:agentic` → `:execute`
- `:agentic_planned` → `:plan` (skipped to `:execute` if pre-built plan provided)
- `:turn_by_turn` → `:review`
- `:conversational` → `:execute`

## ModeRouter Routing Table

| Mode | Phase | Stop Reason | Action |
|------|-------|-------------|--------|
| `:agentic` | `:execute` | `end_turn` | Accumulate text → next (CommitmentGate) |
| `:agentic` | `:execute` | `tool_use` | Store pending_tool_calls → next (ToolExecutor) |
| `:agentic_planned` | `:plan` | `end_turn` | Parse plan → transition to `:execute` → reentry |
| `:agentic_planned` | `:execute` | `end_turn` | Accumulate text → next (CommitmentGate) |
| `:agentic_planned` | `:execute` | `tool_use` | Store pending_tool_calls → next (ToolExecutor) |
| `:agentic_planned` | `:verify` | `end_turn` | Accumulate verification → done |
| `:turn_by_turn` | `:review` | `end_turn` | Build proposal → next (HumanCheckpoint) |
| `:turn_by_turn` | `:review` | `tool_use` | Store pending_tool_calls → next (ToolExecutor) |
| `:turn_by_turn` | `:execute` | `end_turn` | Transition to `:review` → reentry |
| `:conversational` | `:execute` | `end_turn` | Accumulate text → done |
| any | any | `max_tokens` | Return what we have → done |

## Context Struct Key Fields

| Field | Type | Description |
|-------|------|-------------|
| `session_id` | `String.t \| nil` | Session identifier |
| `user_id` | `String.t \| nil` | User identifier |
| `caller` | `pid \| nil` | Pid to receive events |
| `profile` | `atom` | Profile name |
| `mode` | `atom` | Current mode |
| `phase` | `atom` | Current phase |
| `messages` | `[map]` | Conversation history (string-keyed) |
| `tools` | `[map]` | Active tool definitions |
| `core_tools` | `[map]` | Built-in tool definitions |
| `last_response` | `LLM.Response \| nil` | Most recent LLM response |
| `pending_tool_calls` | `[map]` | Tool calls awaiting execution |
| `accumulated_text` | `String.t` | Concatenated response text |
| `turns_used` | `non_neg_integer` | Turn counter |
| `total_cost` | `float` | Session cost in USD |
| `total_tokens` | `non_neg_integer` | Total tokens used |
| `plan` | `map \| nil` | Current plan (agentic_planned) |
| `config` | `map` | Profile config |
| `callbacks` | `map` | Callback functions |
| `metadata` | `map` | Workspace path, workspace_id, allowed_roots |
| `model_tier` | `atom` | `:primary`, `:lightweight`, `:any` |
| `model_selection_mode` | `atom` | `:manual` or `:auto` |
| `strategy` | `atom` | Strategy id |
| `reentry_pipeline` | `fun \| nil` | Cached pipeline for re-entry |
| `activation` | `map` | Tool activation state |
| `tool_permissions` | `map` | Per-tool permissions (`:auto`, `:approve`, `:deny`) |
| `subagent_depth` | `non_neg_integer` | Current subagent nesting depth |

## Profile Config Defaults

| Profile | max_turns | compaction_at_pct | progress_injection |
|---------|-----------|-------------------|-------------------|
| `:agentic` | 50 | 0.80 | `:system_reminder` |
| `:agentic_planned` | 100 | 0.80 | `:system_reminder` |
| `:turn_by_turn` | 200 | 0.80 | `:none` |
| `:conversational` | 100 | 0.80 | `:none` |
| CLI profiles | 50 | 0.80 | `:system_reminder` |
