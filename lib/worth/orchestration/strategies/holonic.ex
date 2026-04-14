defmodule Worth.Orchestration.Strategies.Holonic do
  @moduledoc """
  Holonic strategy with recursive agent composition.

  The strategy instructs the agent to decompose work into holon-forming
  subtasks with capacity limits. Tracks holon formation events and
  adjusts capacity based on success rates.
  """

  @behaviour AgentEx.Strategy

  defstruct [
    :workspace,
    holon_capacity: 3,
    active_holons: 0,
    holon_history: [],
    max_holons: 10
  ]

  @impl true
  def id, do: :holonic

  @impl true
  def display_name, do: "Holonic"

  @impl true
  def description, do: "Recursive agent composition with holon-forming subtask decomposition"

  @impl true
  def init(opts) do
    workspace = Keyword.get(opts, :workspace)
    capacity = Keyword.get(opts, :holon_capacity, 3)
    {:ok, %__MODULE__{workspace: workspace, holon_capacity: capacity}}
  end

  @impl true
  def prepare_run(opts, state) do
    system_prompt = Keyword.get(opts, :system_prompt, "")
    overlay = build_holonic_overlay(state)

    prepared =
      Keyword.put(opts, :system_prompt, system_prompt <> overlay)

    {:ok, prepared, state}
  end

  @impl true
  def handle_result({:ok, result}, _opts, state) do
    new_state = %{state | holon_history: state.holon_history |> Enum.take(50)}
    {:done, result, new_state}
  end

  @impl true
  def handle_result({:error, reason}, _opts, state) do
    new_state = %{state | active_holons: max(state.active_holons - 1, 0)}
    {:done, {:error, reason}, new_state}
  end

  def handle_event({:tool_use, "delegate_task", _workspace_id}, state) do
    new_active = min(state.active_holons + 1, state.holon_capacity)
    {:ok, %{state | active_holons: new_active}}
  end

  def handle_event(_event, state), do: {:ok, state}

  @impl true
  def telemetry_tags, do: [orchestration_type: :holonic]

  defp build_holonic_overlay(state) do
    "\n\n## Holonic Decomposition\nYou are operating in holonic mode. " <>
      "Break complex tasks into self-contained subtasks (holons). " <>
      "Each holon should be independently verifiable.\n" <>
      "Current holon capacity: #{state.holon_capacity}\n" <>
      "Active holons: #{state.active_holons}\n" <>
      "Use delegate_task to spawn sub-holons when decomposition is beneficial."
  end
end
