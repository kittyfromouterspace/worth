defmodule Worth.Mcp.Broker do
  use DynamicSupervisor

  def start_link(opts \\ []) do
    Worth.Mcp.Registry.init()
    Worth.Mcp.ToolIndex.init()
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def connect(server_name, server_config) do
    server_name = to_string(server_name)

    case Worth.Mcp.Registry.lookup(server_name) do
      {:ok, _pid, _meta} ->
        {:error, :already_connected}

      {:error, :not_found} ->
        start_connection(server_name, server_config)
    end
  end

  def disconnect(server_name) do
    server_name = to_string(server_name)

    case Worth.Mcp.Registry.lookup(server_name) do
      {:ok, pid, _meta} ->
        Worth.Mcp.ToolIndex.unregister_server(server_name)
        Worth.Mcp.Registry.unregister(server_name)
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      {:error, :not_found} ->
        {:error, :not_connected}
    end
  end

  def connect_auto(workspace_path \\ nil) do
    Worth.Mcp.Config.autoconnect_servers(workspace_path)
    |> Enum.map(fn name ->
      case Worth.Mcp.Config.get_server(name, workspace_path) do
        nil -> {name, {:error, :not_configured}}
        config -> {name, connect(name, config)}
      end
    end)
  end

  def list_connections do
    Worth.Mcp.Registry.all()
    |> Enum.map(fn entry ->
      status =
        if is_pid(entry.pid) and Process.alive?(entry.pid) do
          :connected
        else
          :disconnected
        end

      %{
        name: entry.name,
        status: status,
        pid: entry.pid,
        connected_at: entry[:connected_at],
        tool_count: entry[:tool_count] || 0
      }
    end)
  end

  defp start_connection(server_name, server_config) do
    case Worth.Mcp.Config.build_transport_opts(server_config) do
      {:error, reason} ->
        {:error, reason}

      transport_opts ->
        protocol_version = determine_protocol_version(transport_opts)

        client_name = Module.concat([Worth.Mcp.Client, String.capitalize(server_name)])

        child_spec =
          {Worth.Mcp.Client.Supervisor,
           name: client_name, transport: transport_opts, server_name: server_name, protocol_version: protocol_version}

        case DynamicSupervisor.start_child(__MODULE__, child_spec) do
          {:ok, sup_pid} ->
            discover_and_register(server_name, client_name, sup_pid)

          {:error, {:already_started, pid}} ->
            {:ok, _} = discover_and_register(server_name, client_name, pid)

          error ->
            error
        end
    end
  end

  defp discover_and_register(server_name, client_name, _sup_pid) do
    Worth.Mcp.Registry.register(server_name, client_name, %{connected_at: DateTime.utc_now()})

    try do
      case Hermes.Client.Base.list_tools(client_name, timeout: 10_000) do
        {:ok, %Hermes.MCP.Response{result: %{"tools" => tools}}} ->
          Worth.Mcp.ToolIndex.register_tools(server_name, tools)
          Worth.Mcp.Registry.update_meta(server_name, %{tool_count: length(tools)})
          {:ok, server_name}

        {:ok, _} ->
          {:ok, server_name}

        {:error, reason} ->
          Worth.Mcp.Registry.update_meta(server_name, %{error: inspect(reason)})
          {:ok, server_name}
      end
    rescue
      e ->
        Worth.Mcp.Registry.update_meta(server_name, %{error: Exception.message(e)})
        {:ok, server_name}
    end
  end

  defp determine_protocol_version({:streamable_http, _}), do: "2025-03-26"
  defp determine_protocol_version(_), do: "2024-11-05"
end
