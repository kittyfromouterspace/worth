defmodule Worth.Mcp.Registry do
  @table :worth_mcp_registry

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end

    :ok
  end

  def register(server_name, client_pid, meta \\ %{}) do
    :ets.insert(@table, {to_string(server_name), client_pid, meta})
    :ok
  end

  def unregister(server_name) do
    :ets.delete(@table, to_string(server_name))
    :ok
  end

  def lookup(server_name) do
    case :ets.lookup(@table, to_string(server_name)) do
      [{_name, pid, meta}] -> {:ok, pid, meta}
      [] -> {:error, :not_found}
    end
  end

  def lookup_client(server_name) do
    case lookup(server_name) do
      {:ok, pid, _meta} -> {:ok, pid}
      error -> error
    end
  end

  def all do
    :ets.tab2list(@table)
    |> Enum.map(fn {name, pid, meta} -> Map.put(meta, :name, name) |> Map.put(:pid, pid) end)
  end

  def server_names do
    :ets.match(@table, {:"$1", :_, :_})
    |> List.flatten()
  end

  def update_meta(server_name, updates) when is_map(updates) do
    name = to_string(server_name)

    case :ets.lookup(@table, name) do
      [{^name, pid, meta}] ->
        new_meta = Map.merge(meta, updates)
        :ets.insert(@table, {name, pid, new_meta})
        :ok

      [] ->
        {:error, :not_found}
    end
  end
end
