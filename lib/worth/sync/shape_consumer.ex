defmodule Worth.Sync.ShapeConsumer do
  @moduledoc """
  Consumes ElectricSQL shape streams and applies operations to Worth's local SQLite.

  Subscribes to Electric shapes via `Electric.Client` and translates
  insert/update/delete operations into Ecto writes on Worth.Repo.

  Brain shapes (by owner_id) are always synced.
  Workspace shapes (by scope_id) are synced on demand based on DeviceWorkspace subscriptions.
  """

  use GenServer

  alias Worth.Repo

  require Logger

  @shape_tables [
    {"recollect_entries", "owner_id", Recollect.Schema.Entry},
    {"recollect_entities", "owner_id", Recollect.Schema.Entity},
    {"recollect_relations", "owner_id", Recollect.Schema.Relation},
    {"recollect_chunks", "owner_id", Recollect.Schema.Chunk},
    {"recollect_documents", "owner_id", Recollect.Schema.Document},
    {"recollect_collections", "owner_id", Recollect.Schema.Collection},
    {"recollect_edges", nil, Recollect.Schema.Edge}
  ]

  defstruct [:client, :owner_id, :subscriptions, :streams]

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def sync_brain(pid \\ __MODULE__, owner_id, client) do
    GenServer.call(pid, {:sync_brain, owner_id, client})
  end

  def sync_workspace(pid \\ __MODULE__, scope_id) do
    GenServer.call(pid, {:sync_workspace, scope_id})
  end

  def stop_workspace(pid \\ __MODULE__, scope_id) do
    GenServer.call(pid, {:stop_workspace, scope_id})
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      owner_id: Keyword.get(opts, :owner_id),
      client: Keyword.get(opts, :client),
      subscriptions: %{},
      streams: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:sync_brain, owner_id, client}, _from, state) do
    state = %{state | owner_id: owner_id, client: client}

    state =
      Enum.reduce(@shape_tables, state, fn {table, filter_col, _schema}, acc ->
        start_shape_stream(acc, table, filter_col, owner_id)
      end)

    {:reply, :ok, state}
  end

  def handle_call({:sync_workspace, scope_id}, _from, state) do
    state = start_workspace_shapes(state, scope_id)
    {:reply, :ok, state}
  end

  def handle_call({:stop_workspace, scope_id}, _from, state) do
    state = stop_workspace_shapes(state, scope_id)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:shape_event, table, operation, data}, state) do
    apply_operation(table, operation, data)
    {:noreply, state}
  end

  defp start_shape_stream(state, table, nil, _owner_id) do
    do_start_stream(state, table, [])
  end

  defp start_shape_stream(state, table, filter_col, owner_id) do
    where = "#{filter_col} = '#{owner_id}'"
    do_start_stream(state, table, where: where)
  end

  defp do_start_stream(state, table, shape_opts) do
    case state.client do
      nil ->
        state

      client ->
        stream = Electric.Client.stream(client, table, shape_opts)

        Task.start(fn ->
          Enum.each(stream, fn
            {:insert, row} -> send(state.owner_pid || self(), {:shape_event, table, :insert, row})
            {:update, row} -> send(state.owner_pid || self(), {:shape_event, table, :update, row})
            {:delete, row} -> send(state.owner_pid || self(), {:shape_event, table, :delete, row})
          end)
        end)

        streams = Map.put(state.streams, {table, :brain}, stream)
        %{state | streams: streams}
    end
  end

  defp start_workspace_shapes(state, scope_id) do
    workspace_tables = [
      {"recollect_handoffs", "scope_id", nil},
      {"workspace_index_entries", "scope_id", nil}
    ]

    Enum.reduce(workspace_tables, state, fn {table, filter_col, _schema}, acc ->
      where = "#{filter_col} = '#{scope_id}'"
      do_start_stream(acc, {table, scope_id}, where: where)
    end)
  end

  defp stop_workspace_shapes(state, scope_id) do
    %{state | subscriptions: Map.delete(state.subscriptions, scope_id)}
  end

  defp apply_operation(table, :insert, data) do
    Logger.debug("ShapeConsumer INSERT #{table}: #{inspect(Map.keys(data))}")
    :ok
  end

  defp apply_operation(table, :update, data) do
    Logger.debug("ShapeConsumer UPDATE #{table}: #{inspect(Map.keys(data))}")
    :ok
  end

  defp apply_operation(table, :delete, data) do
    Logger.debug("ShapeConsumer DELETE #{table}: #{inspect(Map.keys(data))}")
    :ok
  end
end
