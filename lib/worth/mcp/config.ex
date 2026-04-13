defmodule Worth.Mcp.Config do
  @moduledoc """
  MCP server configuration.

  Global servers are stored in `~/.worth/mcp.json` (inside the data directory).
  Per-workspace servers come from `<workspace>/.worth/mcp.json`.
  """

  def load(workspace_path \\ nil) do
    global = load_global()
    workspace = load_workspace(workspace_path)
    Map.merge(global, workspace)
  end

  defp global_config_path do
    Path.join(Worth.Paths.data_dir(), "mcp.json")
  end

  def server_names(workspace_path \\ nil) do
    workspace_path |> load() |> Map.keys()
  end

  def get_server(name, workspace_path \\ nil) do
    workspace_path |> load() |> Map.get(to_string(name))
  end

  def add_server(name, config) do
    name = to_string(name)
    servers = load_global()
    updated = Map.put(servers, name, config)
    save_global(updated)
    :ok
  end

  def remove_server(name) do
    name = to_string(name)
    servers = load_global()
    updated = Map.delete(servers, name)
    save_global(updated)
    :ok
  end

  def build_transport_opts(server_config) do
    raw_type = server_config["type"] || server_config[:type] || "stdio"
    type = if is_binary(raw_type), do: safe_to_existing_atom(raw_type), else: raw_type

    case type do
      :stdio ->
        command = server_config["command"] || server_config[:command]
        args = server_config["args"] || server_config[:args] || []
        env = resolve_env(server_config["env"] || server_config[:env] || %{})

        {:stdio, [command: command, args: args] ++ if(env == %{}, do: [], else: [env: env])}

      :streamable_http ->
        url = server_config["url"] || server_config[:url]
        mcp_path = server_config["mcp_path"] || server_config[:mcp_path] || "/"
        headers = resolve_env(server_config["headers"] || server_config[:headers] || %{})

        {:streamable_http,
         [url: url, mcp_path: mcp_path] ++
           if(headers == %{}, do: [], else: [headers: headers])}

      :sse ->
        base_url = server_config["url"] || server_config["base_url"]
        {:sse, [base_url: base_url]}

      _ ->
        {:error, "Unknown transport type: #{type}"}
    end
  end

  def autoconnect_servers(workspace_path \\ nil) do
    workspace_path
    |> load()
    |> Enum.filter(fn {_name, config} ->
      config["autoconnect"] || config[:autoconnect] || false
    end)
    |> Enum.map(fn {name, _config} -> name end)
  end

  defp load_global do
    path = global_config_path()

    if File.exists?(path) do
      case File.read(path) do
        {:ok, json} ->
          case Jason.decode(json) do
            {:ok, %{"mcpServers" => servers}} when is_map(servers) ->
              stringify_keys(servers)

            {:ok, servers} when is_map(servers) ->
              stringify_keys(servers)

            _ ->
              %{}
          end

        _ ->
          %{}
      end
    else
      %{}
    end
  end

  defp load_workspace(nil), do: %{}

  defp load_workspace(workspace_path) do
    manifest = Path.join(workspace_path, ".worth/mcp.json")

    case File.read(manifest) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, %{"mcpServers" => servers}} when is_map(servers) ->
            stringify_keys(servers)

          _ ->
            %{}
        end

      _ ->
        %{}
    end
  end

  defp save_global(servers) do
    path = global_config_path()
    File.mkdir_p!(Path.dirname(path))
    json = Jason.encode!(%{"mcpServers" => servers}, pretty: true)
    File.write!(path, json)
    :ok
  end

  defp resolve_env(env) when is_map(env) do
    Map.new(env, fn {k, v} ->
      case v do
        %{"env" => var} -> {k, System.get_env(var) || ""}
        {:env, var} -> {k, System.get_env(var) || ""}
        _ -> {k, v}
      end
    end)
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      key = if is_atom(k), do: Atom.to_string(k), else: k
      {key, v}
    end)
  end

  defp safe_to_existing_atom(str) when is_binary(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> nil
  end

  defp safe_to_existing_atom(other), do: other
end
