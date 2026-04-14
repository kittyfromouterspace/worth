defmodule Worth.Orchestration.Strategies.Stigmergy do
  @moduledoc """
  Stigmergy-based orchestration strategy using pheromone coordination via Mneme.

  Agents deposit digital pheromones (intention, completion, failure signals)
  in Mneme's knowledge store. On each run, pheromone trails are fetched
  and injected into the system prompt as coordination context.

  ## Hypothesis

  Deposited environmental signals help the next agent turn converge faster
  on the right approach, reducing turns, tool backtracking, and cost.
  """

  @behaviour AgentEx.Strategy

  alias Worth.Memory.Manager

  defstruct [
    :workspace,
    active_trails: [],
    deposited_pheromones: [],
    trail_decay: 0.95,
    max_trails: 10
  ]

  @impl true
  def id, do: :stigmergy

  @impl true
  def display_name, do: "Stigmergy (Ant Colony)"

  @impl true
  def description, do: "Coordinates through environmental signals deposited in the knowledge store"

  @impl true
  def init(opts) do
    workspace = Keyword.get(opts, :workspace)
    {:ok, %__MODULE__{workspace: workspace}}
  end

  @impl true
  def prepare_run(opts, state) do
    pheromones = fetch_pheromones(state.workspace, state.max_trails)

    system_prompt = Keyword.get(opts, :system_prompt, "")
    overlay = build_pheromone_overlay(pheromones)

    prepared =
      opts
      |> Keyword.put(:system_prompt, system_prompt <> overlay)
      |> Keyword.put(:strategy_opts, Keyword.put(opts[:strategy_opts] || [], :pheromone_context, pheromones))

    {:ok, prepared, %{state | active_trails: pheromones}}
  end

  @impl true
  def handle_result({:ok, result}, _opts, state) do
    pheromone = deposit_completion_pheromone(result, state.workspace)

    new_state = %{
      state
      | deposited_pheromones: Enum.take([pheromone | state.deposited_pheromones], 50)
    }

    {:done, result, new_state}
  end

  @impl true
  def handle_result({:error, reason}, _opts, state) do
    deposit_failure_pheromone(reason, state.workspace)
    {:done, {:error, reason}, state}
  end

  def handle_event({:tool_use, name, _workspace_id}, state) when is_binary(name) do
    deposit_intention_pheromone(name, state.workspace)
    {:ok, state}
  end

  def handle_event(_event, state), do: {:ok, state}

  @impl true
  def telemetry_tags do
    [orchestration_type: :stigmergy]
  end

  defp fetch_pheromones(nil, _limit), do: []

  defp fetch_pheromones(workspace, limit) do
    # Search for pheromone entries scoped to this workspace.
    # We include "pheromone" in the query text for semantic matching and pass
    # entry_type as a search opt so downstream filters can narrow results
    # if the store supports structured filtering.
    case Manager.search(
           "pheromone workspace:#{workspace}",
           limit: limit,
           entry_type: "pheromone"
         ) do
      {:ok, %{entries: entries}} when is_list(entries) -> entries
      _ -> []
    end
  end

  defp deposit_completion_pheromone(_result, nil), do: %{content: "", metadata: %{}}

  defp deposit_completion_pheromone(result, workspace) do
    text = result[:text] || ""

    preview =
      if byte_size(text) > 200 do
        String.slice(text, 0, 200) <> "..."
      else
        text
      end

    case Manager.remember("pheromone completion: #{preview}",
           entry_type: "pheromone_completion",
           metadata: %{
             signal: :completion,
             cost: result[:cost],
             workspace: workspace
           }
         ) do
      {:ok, entry} -> entry
      _ -> %{content: preview, metadata: %{signal: :completion, workspace: workspace}}
    end
  end

  defp deposit_failure_pheromone(_reason, nil), do: :ok

  defp deposit_failure_pheromone(reason, workspace) do
    Manager.remember("pheromone failure: #{inspect(reason)}",
      entry_type: "pheromone_failure",
      metadata: %{signal: :failure, workspace: workspace}
    )
  end

  defp deposit_intention_pheromone(_tool_name, nil), do: :ok

  defp deposit_intention_pheromone(tool_name, workspace) do
    Manager.remember("pheromone intention: #{tool_name}",
      entry_type: "pheromone_intention",
      metadata: %{signal: :intention, tool: tool_name, workspace: workspace}
    )
  end

  @doc false
  def build_pheromone_overlay([]), do: ""

  def build_pheromone_overlay(pheromones) do
    trails =
      Enum.map_join(pheromones, "\n", fn p ->
        meta = Map.get(p, :metadata) || Map.get(p, "metadata") || %{}
        signal = meta[:signal] || meta["signal"] || "unknown"
        content = Map.get(p, :content) || Map.get(p, "content") || ""
        "- #{signal}: #{content}"
      end)

    "\n\n## Active Pheromone Trails\nOther agents have left these coordination signals:\n#{trails}\nConsider these trails when choosing your approach."
  end
end
