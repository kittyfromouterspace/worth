defmodule Worth.Mcp.ConnectionMonitor do
  use GenServer

  @check_interval 30_000
  @max_reconnect_attempts 10

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_check()
    {:ok, %{attempts: %{}}}
  end

  @impl true
  def handle_info(:check, state) do
    state = check_all_connections(state)
    schedule_check()
    {:noreply, state}
  end

  @impl true
  def handle_cast({:reset_attempts, server_name}, state) do
    attempts = Map.delete(state.attempts, to_string(server_name))
    {:noreply, %{state | attempts: attempts}}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @check_interval)
  end

  defp check_all_connections(state) do
    connections = Worth.Mcp.Broker.list_connections()

    Enum.reduce(connections, state, fn conn, acc ->
      if conn.status == :connected do
        check_connection(conn, acc)
      else
        acc
      end
    end)
  end

  defp check_connection(conn, state) do
    case Worth.Mcp.Gateway.health_check(conn.name) do
      :healthy ->
        %{state | attempts: Map.delete(state.attempts, conn.name)}

      :unhealthy ->
        attempts = Map.get(state.attempts, conn.name, 0) + 1

        if attempts <= @max_reconnect_attempts do
          try_reconnect(conn.name)
          %{state | attempts: Map.put(state.attempts, conn.name, attempts)}
        else
          Phoenix.PubSub.broadcast(Worth.PubSub, "mcp:events", {:mcp_failed, conn.name})
          %{state | attempts: Map.put(state.attempts, conn.name, attempts)}
        end
    end
  end

  defp try_reconnect(server_name) do
    Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
      case Worth.Mcp.Config.get_server(server_name) do
        nil ->
          :ok

        config ->
          Worth.Mcp.Broker.disconnect(server_name)

          backoff = min(:math.pow(2, Map.get(%{}, server_name, 0)), 30_000)
          Process.sleep(trunc(backoff))

          case Worth.Mcp.Broker.connect(server_name, config) do
            {:ok, _} ->
              GenServer.cast(__MODULE__, {:reset_attempts, server_name})
              Phoenix.PubSub.broadcast(Worth.PubSub, "mcp:events", {:mcp_reconnected, server_name})

            {:error, _} ->
              Phoenix.PubSub.broadcast(Worth.PubSub, "mcp:events", {:mcp_reconnect_failed, server_name})
          end
      end
    end)
  end
end
