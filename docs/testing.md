# Testing Strategy

## Approach

Worth is tested at three levels: unit (isolated modules), integration (subsystem interactions), and acceptance (end-to-end scenarios). Tests run against real dependencies where possible (no mocks for agentic, recollect, hermes_mcp) with sandboxed databases and fake LLM responses.

## Test Structure

```
test/
├── worth_test.exs                  # Smoke test: mix test passes
├── worth/
│   ├── brain_test.exs              # Brain GenServer lifecycle
│   ├── config_test.exs             # Config loading & resolution
│   ├── workspace_test.exs          # Workspace CRUD, switching, identity loading
│   ├── llm/
│   │   ├── adapter_test.exs        # Provider adapter normalization
│   │   └── cost_test.exs           # Cost calculation
│   ├── memory/
│   │   ├── manager_test.exs        # Global retrieval + workspace boosting
│   │   └── extractor_test.exs      # Fact extraction
│   ├── skills/
│   │   ├── parser_test.exs         # SKILL.md parsing
│   │   ├── validator_test.exs      # Static validation rules
│   │   ├── lifecycle_test.exs      # CREATE/TEST/REFINE/PROMOTE
│   │   └── trust_test.exs          # Trust level transitions
│   ├── mcp/
│   │   ├── broker_test.exs         # Connection lifecycle
│   │   ├── gateway_test.exs        # Tool discovery + execution
│   │   └── config_test.exs         # Global + workspace merge
│   ├── tools/
│   │   ├── workspace_test.exs
│   │   ├── web_test.exs
│   │   └── git_test.exs
│   └── persistence/
│       └── transcript_test.exs     # JSONL read/write
├── support/
│   ├── data_case.ex                # Ecto case with sandboxed repo
│   ├── brain_case.ex               # Test brain with fake LLM
│   └── mcp_case.ex                 # Test MCP server stub
└── web/
    └── chat_live_test.exs            # LiveView component tests
```

## Testing Patterns

### Unit Tests

```elixir
defmodule Worth.Skills.ParserTest do
  use ExUnit.Case, async: true

  test "parses agentskills.io frontmatter with worth extensions" do
    skill_md = """
    ---
    name: git-workflow
    description: Manages git operations
    loading: always
    trust_level: core
    evolution:
      version: 1
      success_rate: 0.0
    ---
    # Instructions
    ...
    """

    assert {:ok, skill} = Worth.Skills.Parser.parse(skill_md)
    assert skill.name == "git-workflow"
    assert skill.loading == :always
    assert skill.trust_level == :core
  end
end
```

### Integration Tests

```elixir
defmodule Worth.Memory.ManagerTest do
  use Worth.DataCase

  test "global retrieval boosts workspace-tagged entries" do
    Worth.Memory.Manager.store("User prefers Ecto", workspace: "my-phoenix-app")
    Worth.Memory.Manager.store("User prefers Postgrest", workspace: "api-project")

    results = Worth.Memory.Manager.retrieve("database preference", workspace: "my-phoenix-app")

    assert Enum.find(results, &(&1.metadata.workspace == "my-phoenix-app"))
    # workspace-tagged entry should rank higher
  end
end
```

### Acceptance Tests

```elixir
defmodule Worth.AcceptanceTest do
  use Worth.BrainCase

  test "agent reads a file and edits it" do
    start_brain(profile: :agentic)
    stub_llm_response(tool_calls: [
      %{name: "read_file", input: %{path: "lib/app.ex"}},
      %{name: "edit_file", input: %{path: "lib/app.ex", old: "def foo", new: "def bar"}}
    ])

    send_message("Rename foo to bar in lib/app.ex")

    assert_tool_called("read_file")
    assert_tool_called("edit_file")
    assert_file_content("lib/app.ex", "def bar")
  end
end
```

## Test Infrastructure

### DataCase

Wraps Ecto SQL sandbox for parallel test isolation:

```elixir
defmodule Worth.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias Worth.Repo
      import Ecto.Query
    end
  end

  setup tags do
    Worth.DataCase.setup_sandbox(tags)
    :ok
  end
end
```

### BrainCase

Spins up a test Brain with a fake LLM that returns canned responses. Used for acceptance tests that verify the full loop (input → brain → agentic → tools → output) without hitting real LLM APIs.

### McpCase

Starts a stub MCP server process that responds to `list_tools` and `call_tool` with configurable fixtures. Used to test Mcp.Broker, Mcp.Gateway, and tool execution flow.

## LLM Testing

Real LLM calls are never made in tests. Two strategies:

1. **Stub LLM**: `BrainCase` intercepts the `:llm_chat` callback and returns canned responses (text + tool calls). Used for most tests.
2. **Recorded transcripts**: For regression testing, real conversations are recorded as JSONL and replayed through the brain. The expected output is snapshot-tested.

```elixir
# test/support/brain_case.ex
defmodule Worth.BrainCase do
  use ExUnit.CaseTemplate

  setup do
    canned = %{
      text: "I'll help with that.",
      tool_calls: [],
      usage: %{input_tokens: 100, output_tokens: 50}
    }

    {:ok, brain} = Worth.Brain.start_link(test_mode: true, canned_llm: canned)
    {:ok, brain: brain, canned: canned}
  end
end
```

## What Gets Tested Per Phase

| Phase | Tests Added |
|-------|-------------|
| 1. Skeleton | Brain lifecycle, LLM adapter normalization, config loading |
| 2. Workspaces | Workspace CRUD, file tool execution, identity loading, system prompt assembly |
| 3. Memory | Global store/retrieve, workspace boosting, ContextKeeper flush, fact extraction |
| 4. Skills | SKILL.md parsing, validation, progressive disclosure, trust levels |
| 5. Self-Learning | Lifecycle state machine, refinement triggers, version management |
| 6. MCP | Broker lifecycle, gateway dispatch, config merge, connection monitoring |
| 7. Advanced | MCP server mode, codebase indexing, sub-agent coordination |

## CI

```yaml
# .github/workflows/test.yml
- mix test                          # Unit + integration
- mix test --include acceptance     # Acceptance (slower, tagged)
- mix credo                         # Linting
- mix dialyzer                      # Types
- mix format --check-formatted      # Formatting
```
