defmodule Worth.Learning.TelemetryBridge do
  @moduledoc """
  Bridges Mneme's `:telemetry` learning events into Worth's PubSub system.

  Mneme emits `:telemetry` events during learning. This module attaches
  handlers to those events and rebroadcasts them as
  `{:agent_event, {:learning_progress, details}}` messages on the
  `"workspace:<name>"` PubSub topic so the web UI can display real-time
  progress.

  ## Attached events

  | Mneme event | PubSub payload |
  |---|---|
  | `[:mneme, :learning, :start]` | `%{phase: :start, sources: [...]}` |
  | `[:mneme, :learn, :source, :stop]` | `%{phase: :source_complete, source: ..., fetched: ..., learned: ...}` |
  | `[:mneme, :learn, :coding_agents, :fetch, :stop]` | `%{phase: :agents_fetched, events_found: ...}` |
  | `[:mneme, :learn, :git, :fetch, :stop]` | `%{phase: :git_fetched, commits_found: ...}` |
  | `[:mneme, :learning, :stop]` | `%{phase: :complete, total_learned: ..., total_fetched: ...}` |

  ## Usage

  Started as a named GenServer in the Worth application supervision tree.
  Attaches to telemetry on init, detaches on terminate.
  """

  use GenServer

  @handler_id __MODULE__

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    events = [
      [:mneme, :learning, :start],
      [:mneme, :learning, :stop],
      [:mneme, :learn, :source, :stop],
      [:mneme, :learn, :coding_agents, :fetch, :stop],
      [:mneme, :learn, :git, :fetch, :stop],
      [:mneme, :learn, :claude_code, :fetch, :stop],
      [:mneme, :learn, :opencode, :fetch, :stop]
    ]

    :telemetry.attach_many(@handler_id, events, &__MODULE__.handle_telemetry/4, nil)

    {:ok, %{}}
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach(@handler_id)
    :ok
  end

  def handle_telemetry([:mneme, :learning, :start], _measurements, metadata, _config) do
    scope_id = Map.get(metadata, :scope_id)
    workspace = workspace_from_scope(scope_id)

    broadcast(workspace, %{
      phase: :start,
      sources: Map.get(metadata, :sources, []),
      scope_id: scope_id
    })
  end

  def handle_telemetry([:mneme, :learning, :stop], measurements, metadata, _config) do
    scope_id = Map.get(metadata, :scope_id)
    workspace = workspace_from_scope(scope_id)

    broadcast(workspace, %{
      phase: :complete,
      total_learned: Map.get(measurements, :total_learned, 0),
      total_fetched: Map.get(measurements, :total_fetched, 0),
      duration_ms: Map.get(measurements, :duration_ms, 0),
      scope_id: scope_id
    })
  end

  def handle_telemetry([:mneme, :learn, :source, :stop], measurements, metadata, _config) do
    scope_id = Map.get(metadata, :scope_id)
    workspace = workspace_from_scope(scope_id)

    broadcast(workspace, %{
      phase: :source_complete,
      source: Map.get(metadata, :source),
      fetched: Map.get(measurements, :fetched, 0),
      learned: Map.get(measurements, :learned, 0),
      scope_id: scope_id
    })
  end

  def handle_telemetry([:mneme, :learn, :coding_agents, :fetch, :stop], measurements, metadata, _config) do
    scope_id = Map.get(metadata, :scope_id)
    workspace = workspace_from_scope(scope_id)

    broadcast(workspace, %{
      phase: :agents_fetched,
      events_found: Map.get(measurements, :events_found, 0),
      duration_ms: Map.get(measurements, :duration_ms, 0),
      scope_id: scope_id
    })
  end

  def handle_telemetry([:mneme, :learn, agent, :fetch, :stop], measurements, metadata, _config) do
    scope_id = Map.get(metadata, :scope_id)
    workspace = workspace_from_scope(scope_id)

    broadcast(workspace, %{
      phase: :agent_fetched,
      agent: agent,
      duration_ms: Map.get(measurements, :duration_ms, 0),
      scope_id: scope_id
    })
  end

  def handle_telemetry(_event_name, _measurements, _metadata, _config), do: :ok

  defp broadcast(nil, _payload), do: :ok

  defp broadcast(workspace, payload) do
    Phoenix.PubSub.broadcast(
      Worth.PubSub,
      "workspace:#{workspace}",
      {:agent_event, {:learning_progress, payload}}
    )
  end

  defp workspace_from_scope(nil), do: nil

  defp workspace_from_scope(scope_id) when is_binary(scope_id) do
    default = Application.get_env(:worth, :current_workspace, "personal")

    try do
      import Ecto.Query

      Worth.Repo.one(
        from(e in Worth.Workspace.IndexEntry,
          where: e.workspace_name != "",
          limit: 1,
          select: e.workspace_name
        )
      ) || default
    rescue
      _ -> default
    end
  end
end
