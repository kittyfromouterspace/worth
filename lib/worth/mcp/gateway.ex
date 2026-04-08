defmodule Worth.Mcp.Gateway do
  def execute(tool_name, args \\ %{}) do
    case resolve_tool(tool_name) do
      {:mcp, server_name, original_name, _schema} ->
        execute_mcp_tool(server_name, original_name, args)

      {:error, :not_found} ->
        {:error, "Tool '#{tool_name}' not found in MCP tool index"}
    end
  end

  def resolve_tool(tool_name) do
    case Worth.Mcp.ToolIndex.find_server(tool_name) do
      {:ok, server} ->
        {:ok, schema} = Worth.Mcp.ToolIndex.get_schema(tool_name)
        original_name = schema["name"] || schema[:name] || tool_name
        {:mcp, server, original_name, schema}

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  def list_mcp_tools do
    Worth.Mcp.ToolIndex.all_tools()
  end

  def refresh_tools(server_name) do
    case Worth.Mcp.Registry.lookup_client(server_name) do
      {:ok, client_pid} ->
        case Hermes.Client.Base.list_tools(client_pid, timeout: 10_000) do
          {:ok, %Hermes.MCP.Response{result: %{"tools" => tools}}} ->
            Worth.Mcp.ToolIndex.unregister_server(server_name)
            Worth.Mcp.ToolIndex.register_tools(server_name, tools)
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
          {:ok, %Hermes.MCP.Response{} = response} ->
            if Hermes.MCP.Response.success?(response) do
              {:ok, format_response(response)}
            else
              {:error, format_response(response)}
            end

          {:error, %Hermes.MCP.Error{} = error} ->
            {:error, error.message}

          {:error, reason} ->
            {:error, inspect(reason)}
        end

      {:error, :not_found} ->
        {:error, "MCP server '#{server_name}' not connected"}
    end
  end

  defp format_response(%Hermes.MCP.Response{} = response) do
    unwrapped = Hermes.MCP.Response.unwrap(response)

    case unwrapped do
      %{"content" => content} when is_list(content) ->
        content
        |> Enum.map(fn
          %{"text" => text} -> text
          %{"data" => data} -> data
          other -> inspect(other)
        end)
        |> Enum.join("\n")

      other ->
        inspect(other)
    end
  end
end
