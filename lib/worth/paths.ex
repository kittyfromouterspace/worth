defmodule Worth.Paths do
  @moduledoc """
  Canonical path resolution for Worth's two directory roots.

  ## Data directory (`data_dir/0`)

  Internal files the user doesn't interact with directly: the SQLite
  database, config file, logs, and caches. Follows OS conventions:

    * Linux:   `~/.local/share/worth`  (XDG_DATA_HOME)
    * macOS:   `~/Library/Application Support/worth`
    * Windows: `%LOCALAPPDATA%/worth`

  ## Workspace directory (`workspace_dir/0`)

  User-facing files: workspaces and their contents (including per-workspace
  skills). Defaults to `~/work`, configurable via onboarding or settings.
  Stored in the config as `:workspace_directory`.
  """

  @default_workspace_dir "~/work"

  @doc "Default workspace directory suggested in onboarding."
  def default_workspace_dir, do: @default_workspace_dir

  @doc """
  The internal data directory, derived from OS conventions.
  Not user-configurable — always auto-detected.
  """
  def data_dir do
    case :os.type() do
      {:unix, :darwin} ->
        Path.expand("~/Library/Application Support/worth")

      {:win32, _} ->
        case System.get_env("LOCALAPPDATA") do
          nil -> Path.expand("~/.local/share/worth")
          dir -> Path.join(dir, "worth")
        end

      {:unix, _} ->
        case System.get_env("XDG_DATA_HOME") do
          nil -> Path.expand("~/.local/share/worth")
          dir -> Path.join(dir, "worth")
        end
    end
  end

  @doc """
  The user-facing workspace directory. Read from the runtime config
  (`:workspace_directory`), falling back to the default.

  During early boot (before `Worth.Config` agent is started), reads
  directly from the on-disk config file.
  """
  def workspace_dir do
    case Process.whereis(Worth.Config) do
      nil ->
        load_workspace_dir_default()

      _pid ->
        Worth.Config.get(:workspace_directory) || load_workspace_dir_default()
    end
  end

  defp load_workspace_dir_default do
    # Try Settings DB directly (preference, no vault needed)
    pref =
      try do
        Worth.Settings.get_preference("workspace_directory")
      rescue
        _ -> nil
      catch
        :exit, _ -> nil
      end

    case pref do
      path when is_binary(path) and path != "" ->
        Path.expand(path)

      _ ->
        Path.expand(@default_workspace_dir)
    end
  end

  @doc "Ensure the data directory exists on disk."
  def ensure_data_dir! do
    dir = data_dir()

    if not File.dir?(dir) do
      File.mkdir_p!(dir)
    end

    dir
  end

  @doc "Ensure the workspace directory exists on disk."
  def ensure_workspace_dir! do
    dir = workspace_dir()

    if not File.dir?(dir) do
      File.mkdir_p!(dir)
    end

    dir
  end
end
