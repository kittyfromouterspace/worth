defmodule Worth.Agent.Tracker do
  @moduledoc """
  Tracks active agent sessions (main + subagents) for the UI Agents panel.

  Listens to AgentEx telemetry events to register/unregister sessions and
  update their status in real time.  The UI polls `list_active/0` on each
  render tick.

  State is kept in an ETS table for lock-free reads from the UI process.
  """

  use GenServer

  require Logger

  @table :worth_agent_tracker
  @handler_id "worth-agent-tracker"

  # ── Public API ─────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Register a new agent session."
  def register(session_id, opts \\ []) do
    GenServer.cast(__MODULE__, {:register, session_id, opts})
  end

  @doc "Remove a completed/errored session."
  def unregister(session_id) do
    GenServer.cast(__MODULE__, {:unregister, session_id})
  end

  @doc "Update a field on a tracked session."
  def update_field(session_id, field, value) do
    GenServer.cast(__MODULE__, {:update_field, session_id, field, value})
  end

  @doc "Return all active agents as a list of maps, sorted by depth then start time."
  def list_active do
    if :ets.whereis(@table) != :undefined do
      @table
      |> :ets.tab2list()
      |> Enum.map(&elem(&1, 1))
      |> Enum.sort_by(&{&1.depth, &1.started_at})
    else
      []
    end
  rescue
    _ -> []
  end

  # ── GenServer callbacks ────────────────────────────────────────────

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    attach_telemetry()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_cast({:register, session_id, opts}, state) do
    agent = %{
      session_id: session_id,
      parent_session_id: Keyword.get(opts, :parent_session_id),
      depth: Keyword.get(opts, :depth, 0),
      status: :running,
      mode: Keyword.get(opts, :mode),
      workspace: Keyword.get(opts, :workspace),
      started_at: System.monotonic_time(:millisecond),
      cost: 0.0,
      turns: 0,
      current_tool: nil,
      label: Keyword.get(opts, :label)
    }

    :ets.insert(@table, {session_id, agent})
    broadcast()
    {:noreply, state}
  end

  def handle_cast({:unregister, session_id}, state) do
    :ets.delete(@table, session_id)
    broadcast()
    {:noreply, state}
  end

  def handle_cast({:update_field, session_id, field, value}, state) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, agent}] ->
        :ets.insert(@table, {session_id, Map.put(agent, field, value)})
        broadcast()

      [] ->
        :ok
    end

    {:noreply, state}
  end

  # ── Telemetry hooks ────────────────────────────────────────────────

  defp attach_telemetry do
    events = [
      [:agent_ex, :session, :start],
      [:agent_ex, :session, :stop],
      [:agent_ex, :session, :error],
      [:agent_ex, :subagent, :spawn],
      [:agent_ex, :subagent, :complete],
      [:agent_ex, :subagent, :error],
      [:agent_ex, :tool, :start],
      [:agent_ex, :tool, :stop],
      [:agent_ex, :llm_call, :stop]
    ]

    :telemetry.attach_many(
      @handler_id,
      events,
      &__MODULE__.handle_telemetry/4,
      nil
    )
  end

  # Session lifecycle
  def handle_telemetry([:agent_ex, :session, :start], _measurements, metadata, _config) do
    register(metadata.session_id,
      mode: Map.get(metadata, :mode),
      workspace: Map.get(metadata, :workspace),
      label: Map.get(metadata, :label, "main agent")
    )
  end

  def handle_telemetry([:agent_ex, :session, :stop], _measurements, metadata, _config) do
    unregister(metadata.session_id)
  end

  def handle_telemetry([:agent_ex, :session, :error], _measurements, metadata, _config) do
    update_field(metadata.session_id, :status, :error)
  end

  # Subagent lifecycle
  def handle_telemetry([:agent_ex, :subagent, :spawn], _measurements, metadata, _config) do
    register(metadata.session_id,
      parent_session_id: Map.get(metadata, :parent_session_id),
      depth: Map.get(metadata, :depth, 1),
      label: Map.get(metadata, :label, "subagent")
    )
  end

  def handle_telemetry([:agent_ex, :subagent, :complete], _measurements, metadata, _config) do
    update_field(metadata.session_id, :status, :done)
    # Keep for a moment so the UI can show "done", then clean up
    Process.send_after(__MODULE__, {:cleanup, metadata.session_id}, 5_000)
  end

  def handle_telemetry([:agent_ex, :subagent, :error], _measurements, metadata, _config) do
    update_field(metadata.session_id, :status, :error)
  end

  # Tool tracking
  def handle_telemetry([:agent_ex, :tool, :start], _measurements, metadata, _config) do
    update_field(metadata.session_id, :current_tool, metadata.tool_name)
  end

  def handle_telemetry([:agent_ex, :tool, :stop], _measurements, metadata, _config) do
    update_field(metadata.session_id, :current_tool, nil)
  end

  # Cost tracking from LLM calls
  def handle_telemetry([:agent_ex, :llm_call, :stop], measurements, metadata, _config) do
    cost = Map.get(measurements, :cost_usd, 0.0)

    if cost > 0 do
      case :ets.lookup(@table, metadata.session_id) do
        [{sid, agent}] ->
          :ets.insert(@table, {sid, %{agent | cost: agent.cost + cost}})

        [] ->
          :ok
      end
    end
  end

  def handle_telemetry(_, _, _, _), do: :ok

  # Delayed cleanup of completed subagents
  @impl true
  def handle_info({:cleanup, session_id}, state) do
    :ets.delete(@table, session_id)
    broadcast()
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  # ── PubSub broadcast ───────────────────────────────────────────────

  defp broadcast do
    Phoenix.PubSub.broadcast(Worth.PubSub, "agents:updates", :agents_updated)
  rescue
    _ -> :ok
  end
end
