defmodule Worth.Config.Store do
  @moduledoc """
  On-disk persistence for Worth's user-level config.

  The config file is ALWAYS stored at ~/.worth/config.exs, regardless of
  the configured home_directory. This ensures the config can be found at
  boot time before the home_directory setting is loaded.

  The file is a single Elixir map literal evaluated with `Code.eval_file/1`.
  No `Mix.Config` DSL — just plain data, written by Worth and read back at
  boot. Secrets are currently stored **in plain text** with `0600`
  permissions; encryption-at-rest is a planned follow-up.

  This module is the only place that touches the file. Higher-level callers
  go through `Worth.Config` (in-memory) and `Worth.Config.Setup` (mutations).
  """

  # Fixed location for config file - this is the source of truth
  @config_path Path.expand("~/.worth/config.exs")

  @doc "Absolute path to the config file. Always ~/.worth/config.exs"
  def path, do: @config_path

  @doc """
  The Worth home directory (configurable via settings, defaults to ~/.worth).

  This is read from:
  1. The config file if set there
  2. Application env (config/*.exs) as fallback
  3. Defaults to ~/.worth
  """
  def home_directory do
    # First try to read from the already-loaded runtime config
    case Process.whereis(Worth.Config) do
      nil ->
        # Config not loaded yet, check the file directly or use default
        load_home_directory_from_file_or_env()

      _pid ->
        # Config is loaded, use the runtime value
        Worth.Config.get(:home_directory) || load_home_directory_from_file_or_env()
    end
  end

  defp load_home_directory_from_file_or_env do
    # Check if home_directory is set in the config file
    disk_config = load()

    case disk_config[:home_directory] do
      nil ->
        # Fall back to Application env, then default
        Application.get_env(:worth, :home_directory, "~/.worth") |> Path.expand()

      path when is_binary(path) ->
        Path.expand(path)
    end
  end

  @doc "True if the config file exists on disk."
  def exists? do
    File.exists?(path())
  end

  @doc """
  Loads the on-disk config map. Creates the file with defaults if it doesn't
  exist. Returns an empty map if the file fails to parse.
  """
  def load do
    file = path()

    cond do
      not File.exists?(file) ->
        # Initialize with empty config - defaults come from Application env
        ensure_config_dir!()
        save!(%{})
        %{}

      true ->
        try do
          {value, _} = Code.eval_file(file)
          if is_map(value), do: value, else: %{}
        rescue
          e ->
            require Logger
            Logger.warning("Worth.Config.Store: failed to load #{file}: #{Exception.message(e)}")
            %{}
        end
    end
  end

  defp ensure_config_dir! do
    path() |> Path.dirname() |> File.mkdir_p!()
  end

  @doc """
  Persists `map` to disk, creating parent directories as needed and
  forcing `0600` perms on the file.
  """
  def save!(map) when is_map(map) do
    file = path()
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, format(map))
    _ = File.chmod(file, 0o600)
    :ok
  end

  defp format(map) do
    """
    # Worth config — managed by Worth.Config.Store.
    # Hand edits are preserved on the next save as long as the file
    # remains a single Elixir map literal. Secrets are plain text;
    # keep this file at 0600.
    #{inspect(map, pretty: true, limit: :infinity, printable_limit: :infinity)}
    """
  end
end
