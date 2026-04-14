defmodule Worth.Boot do
  @moduledoc """
  Starts the Worth application and returns the URL.
  Used by both CLI and desktop bridge.
  """

  alias Worth.Workspace.Service

  def run(opts \\ []) do
    Worth.Config.Setup.maybe_run_first_run!()
    ensure_directories!()

    workspace = Keyword.get(opts, :workspace, "personal")
    mode = parse_mode(Keyword.get(opts, :mode, "code"))

    workspace_path = Service.resolve_path(workspace)

    if !File.dir?(workspace_path) do
      IO.puts("Workspace '#{workspace}' not found. Creating...")
      Service.create(workspace)
    end

    Worth.Config.put(:current_workspace, workspace)
    Worth.Config.put(:current_workspace_path, workspace_path)
    Worth.Config.put(:current_mode, mode)

    if auto_migrate?() do
      run_migrations!()
    end

    Worth.Brain.ensure(workspace)
    Worth.Brain.switch_mode(workspace, mode)

    if strategy = Keyword.get(opts, :strategy) do
      case safe_to_existing_atom(strategy) do
        {:ok, atom} -> Worth.Brain.switch_strategy(workspace, atom)
        {:error, _} -> IO.puts("Unknown strategy: #{strategy}")
      end
    end

    url()
  end

  @endpoint_config Application.compile_env(:worth, WorthWeb.Endpoint, http: [port: 4090])

  def url do
    port = get_in(@endpoint_config, [:http, :port]) || 4090
    "http://localhost:#{port}"
  end

  def auto_migrate? do
    System.get_env("WORTH_DESKTOP") == "1" or
      System.get_env("WORTH_AUTO_MIGRATE") == "1"
  end

  @repo_config Application.compile_env(:worth, Worth.Repo, database: nil)

  def run_migrations! do
    db_path = @repo_config[:database]

    if db_path do
      db_path |> Path.dirname() |> File.mkdir_p!()
    end

    Ecto.Migrator.run(Worth.Repo, :up, all: true)
  rescue
    e ->
      IO.warn("Migration failed: #{inspect(e)}")
  end

  defp parse_mode("code"), do: :code
  defp parse_mode("research"), do: :research
  defp parse_mode("planned"), do: :planned
  defp parse_mode("turn_by_turn"), do: :turn_by_turn
  defp parse_mode(_), do: :code

  defp safe_to_existing_atom(str) when is_binary(str) do
    {:ok, String.to_existing_atom(str)}
  rescue
    ArgumentError -> {:error, :unknown_atom}
  end

  defp ensure_directories! do
    Worth.Paths.ensure_data_dir!()
    Worth.Paths.ensure_workspace_dir!()
  end
end
