defmodule WorthWeb.Commands.McpCommands do
  @moduledoc false
  import WorthWeb.Commands.Helpers

  def handle({:mcp, :list}, socket) do
    connections = Worth.Brain.mcp_list()

    if connections == [] do
      append_system(socket, "No MCP servers connected.")
    else
      lines =
        Enum.map_join(connections, "\n", fn c -> "  [#{c.status}] #{c.name} (#{c.tool_count} tools)" end)

      append_system(socket, "MCP Servers:\n#{lines}")
    end
  end

  def handle({:mcp, {:connect, name}}, socket) do
    case Worth.Mcp.Config.get_server(name) do
      nil ->
        append_error(socket, "Server '#{name}' not configured. Add it to ~/.worth/config.exs")

      config ->
        case Worth.Brain.mcp_connect(name, config) do
          {:ok, _} ->
            append_system(socket, "Connected to MCP server '#{name}'.")

          {:error, :already_connected} ->
            append_system(socket, "Already connected to '#{name}'.")

          {:error, reason} ->
            append_error(socket, "Failed to connect: #{inspect(reason)}")
        end
    end
  end

  def handle({:mcp, {:disconnect, name}}, socket) do
    case Worth.Brain.mcp_disconnect(name) do
      :ok ->
        append_system(socket, "Disconnected from '#{name}'.")

      {:error, :not_connected} ->
        append_system(socket, "Server '#{name}' was not connected.")
    end
  end

  def handle({:mcp, {:tools, name}}, socket) do
    tools = Worth.Brain.mcp_tools(name)

    if tools == [] do
      append_system(socket, "No tools found for server '#{name}'.")
    else
      lines =
        Enum.map_join(tools, "\n", fn t -> "  #{t["name"]}: #{String.slice(t["description"] || "", 0, 60)}" end)

      append_system(socket, "Tools from #{name}:\n#{lines}")
    end
  end
end
