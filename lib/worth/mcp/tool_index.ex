defmodule Worth.Mcp.ToolIndex do
  @moduledoc false
  @table :worth_mcp_tool_index

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end

    :ok
  end

  def register_tools(server_name, tools) when is_list(tools) do
    server = to_string(server_name)

    Enum.each(tools, fn tool ->
      tool_name = tool["name"] || tool[:name]
      namespaced = "#{server}:#{tool_name}"
      :ets.insert(@table, {namespaced, server, tool_name, tool})
      :ets.insert(@table, {tool_name, server, tool_name, tool})
    end)

    :ok
  end

  def unregister_server(server_name) do
    server = to_string(server_name)
    :ets.match_delete(@table, {:_, server, :_, :_})
    :ok
  end

  def find_server(tool_name) do
    case :ets.lookup(@table, tool_name) do
      [{_key, server, _original_name, _schema}] -> {:ok, server}
      [] -> {:error, :not_found}
    end
  end

  def get_schema(tool_name) do
    case :ets.lookup(@table, tool_name) do
      [{_key, _server, _original, schema}] -> {:ok, schema}
      [] -> {:error, :not_found}
    end
  end

  def all_tools do
    @table
    |> :ets.tab2list()
    |> Enum.filter(fn {key, _, _, _} -> not String.contains?(key, ":") end)
    |> Enum.map(fn {key, server, _original, schema} ->
      %{
        namespaced_name: "#{server}:#{key}",
        name: key,
        server: server,
        description: schema["description"] || schema[:description] || "",
        schema: schema
      }
    end)
  end

  def tools_for_server(server_name) do
    server = to_string(server_name)

    @table
    |> :ets.tab2list()
    |> Enum.filter(fn {_key, srv, _, _} -> srv == server end)
    |> Enum.filter(fn {key, _, _, _} -> not String.contains?(key, ":") end)
    |> Enum.map(fn {_key, _srv, _original, schema} ->
      Map.put(schema, "server", server)
    end)
  end

  def clear do
    :ets.delete_all_objects(@table)
    :ok
  end
end
