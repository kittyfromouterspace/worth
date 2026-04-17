# Agent Protocols

## Transport Types

Defined in `Agentic.Protocol`:

- `:llm` — Stateless LLM API calls (OpenAI, Anthropic, etc.)
- `:local_agent` — Stateful CLI-based local agents (Claude Code, OpenCode, Codex)
- `:acp` — Agent Client Protocol (JSON-RPC 2.0 over stdio)

## AgentProtocol Behaviour

Defined in `Agentic.AgentProtocol`. Implement for custom backends.

### Required Callbacks

| Callback | Signature | Description |
|----------|-----------|-------------|
| `start/2` | `(backend_config, ctx) -> {:ok, session_id} \| {:error, term}` | Start a new session |
| `send/3` | `(session_id, messages, ctx) -> {:ok, response} \| {:error, term}` | Send messages, get response |
| `resume/3` | `(session_id, messages, ctx) -> {:ok, session_id, response} \| {:error, term}` | Resume existing session |
| `stop/1` | `(session_id) -> :ok \| {:error, term}` | Stop and cleanup session |
| `parse_stream/1` | `(chunk) -> {:message, map} \| :partial \| :eof \| {:error, term}` | Parse streaming chunk |
| `format_messages/2` | `(messages, ctx) -> iodata()` | Format messages for wire protocol |
| `transport_type/0` | `() -> transport_type()` | Return transport type |

### Optional Callbacks (with defaults)

| Callback | Default | Description |
|----------|---------|-------------|
| `estimate_cost/1` | `0.0` | Estimate cost for a response |
| `get_usage/1` | `nil` | Get current usage stats for a session |
| `available?/0` | `true` | Check if protocol is available |
| `stream_message/3` | `:ok` | Stream a chunk to the client |

### Protocol Response Shape

```elixir
%{
  content: String.t() | nil,
  tool_calls: [map()] | nil,
  usage: %{input: non_neg_integer(), output: non_neg_integer()} | nil,
  stop_reason: String.t() | nil,
  metadata: map() | nil
}
```

## Built-in Protocols

### `Agentic.Protocol.LLM`

Wraps existing callback-based LLM calls. Transport: `:llm`. Sessionless.

### `Agentic.Protocol.ClaudeCode`

Claude Code CLI via subprocess. Transport: `:local_agent`. Session-based.
Checks `System.find_executable("claude")` for availability.

CLI args: `-p --output-format stream-json --include-partial-messages --verbose --permission-mode bypassPermissions`

### `Agentic.Protocol.OpenCode`

OpenCode CLI via subprocess. Transport: `:local_agent`. Session-based.
Checks `System.find_executable("opencode")` for availability.

CLI args: `--mode agent`

### `Agentic.Protocol.Codex`

Codex CLI via subprocess. Transport: `:local_agent`. Session-based.
Checks `System.find_executable("codex")` for availability.

CLI args: `--json`

### `Agentic.Protocol.ACP`

Agent Client Protocol (JSON-RPC 2.0 over stdio). Transport: `:acp`. Session-based.
Used for `:acp` and `{:acp, agent_name}` profiles.

## Protocol Registry

Protocols are registered at application startup in `Agentic.Application`.
CLI protocols are only registered if their binary is found on the system.

ACP agents can be configured via:

```elixir
config :agentic,
  acp_agents: [
    [name: "my-agent", command: "my-agent-cli"]
  ]
```

## Errors

- `Agentic.Protocol.Error.NotFound` — Protocol not registered
- `Agentic.Protocol.Error.Unavailable` — CLI binary not found
- `Agentic.Protocol.Error.SessionError` — Session-level error
