defmodule Worth.Mcp.Gateway do
  @moduledoc false
  alias Hermes.MCP.Response
  alias Worth.Mcp.ToolIndex

  def execute(tool_name, args \\ %{}) do
    case resolve_tool(tool_name) do
      {:mcp, server_name, original_name, _schema} ->
        execute_mcp_tool(server_name, original_name, args)

      {:error, :not_found} ->
        {:error, "Tool '#{tool_name}' not found in MCP tool index"}
    end
  end

  def resolve_tool(tool_name) do
    with {:ok, server} <- ToolIndex.find_server(tool_name),
         {:ok, schema} <- ToolIndex.get_schema(tool_name) do
      original_name = schema["name"] || schema[:name] || tool_name
      {:mcp, server, original_name, schema}
    else
      {:error, _} -> {:error, :not_found}
    end
  end

  def list_mcp_tools do
    ToolIndex.all_tools()
  end

  def refresh_tools(server_name) do
    case Worth.Mcp.Registry.lookup_client(server_name) do
      {:ok, client_pid} ->
        case Hermes.Client.Base.list_tools(client_pid, timeout: 10_000) do
          {:ok, %Response{result: %{"tools" => tools}}} ->
            ToolIndex.unregister_server(server_name)
            ToolIndex.register_tools(server_name, tools)
            Worth.Mcp.Registry.update_meta(server_name, %{tool_count: length(tools)})
            {:ok, length(tools)}

          error ->
            error
        end

      error ->
        error
    end
  end

  def list_resources(server_name) do
    with {:ok, client_pid} <- Worth.Mcp.Registry.lookup_client(server_name) do
      Hermes.Client.Base.list_resources(client_pid, timeout: 10_000)
    end
  end

  def read_resource(server_name, uri) do
    with {:ok, client_pid} <- Worth.Mcp.Registry.lookup_client(server_name) do
      Hermes.Client.Base.read_resource(client_pid, uri, timeout: 10_000)
    end
  end

  def list_prompts(server_name) do
    with {:ok, client_pid} <- Worth.Mcp.Registry.lookup_client(server_name) do
      Hermes.Client.Base.list_prompts(client_pid, timeout: 10_000)
    end
  end

  def get_prompt(server_name, name, args \\ nil) do
    with {:ok, client_pid} <- Worth.Mcp.Registry.lookup_client(server_name) do
      Hermes.Client.Base.get_prompt(client_pid, name, args, timeout: 10_000)
    end
  end

  def health_check(server_name) do
    case Worth.Mcp.Registry.lookup_client(server_name) do
      {:ok, client_pid} ->
        case Hermes.Client.Base.ping(client_pid, timeout: 5_000) do
          :pong -> :healthy
          {:error, _} -> :unhealthy
        end

      {:error, :not_found} ->
        :disconnected
    end
  end

  defp execute_mcp_tool(server_name, tool_name, args) do
    case Worth.Mcp.Registry.lookup_client(server_name) do
      {:ok, client_pid} ->
        result = Hermes.Client.Base.call_tool(client_pid, tool_name, args, timeout: 30_000)

        case result do
          {:ok, %Response{} = response} ->
            if Response.success?(response) do
              {:ok, format_response(response)}
            else
              {:error, format_response(response)}
            end

          {:error, %Hermes.MCP.Error{} = error} ->
            {:error, error.message}
        end

      {:error, :not_found} ->
        {:error, "MCP server '#{server_name}' not connected"}
    end
  end

  defp format_response(%Response{} = response) do
    unwrapped = Response.unwrap(response)

    case unwrapped do
      %{"content" => content} when is_list(content) ->
        Enum.map_join(content, "\n", fn
          %{"text" => text} -> text
          %{"data" => data} -> data
          other -> inspect(other)
        end)

      other ->
        inspect(other)
    end
  end
end
