defmodule Worth.Config do
  @moduledoc """
  In-memory holder for Worth's runtime configuration.

  Configuration comes from two sources (later overrides earlier):

    1. Compile-time `Application.get_all_env(:worth)` (config/*.exs)
    2. User preferences from `Worth.Settings` (DB-backed, plaintext preferences)

  Secrets are managed via `Worth.Settings` (encrypted) and resolved
  per-call by `Worth.LLM` — no env var intermediation needed.
  """

  use Agent

  require Logger

  # Preference keys that map to config paths.
  # {settings_key, config_path, parser}
  @preference_mappings [
    {"workspace_directory", [:workspace_directory], &Worth.Config.parse_string/1},
    {"memory_enabled", [:memory, :enabled], &Worth.Config.parse_boolean/1},
    {"memory_decay_days", [:memory, :decay_days], &Worth.Config.parse_integer/1},
    {"embedding_model", [:memory, :embedding_model], &Worth.Config.parse_string/1}
  ]

  def start_link(_opts) do
    compile_time = load_compile_time()
    overrides = load_settings_overrides()
    merged = deep_merge(compile_time, overrides)

    sync_to_application_env(merged)

    Agent.start_link(fn -> %{base: compile_time, merged: merged} end, name: __MODULE__)
  end

  @doc """
  Look up a key. `key` may be an atom (top-level) or a list of atoms for
  a nested path.
  """
  def get(key, default \\ nil)

  def get(key, default) when is_atom(key) do
    Agent.get(__MODULE__, &Map.get(&1.merged, key, default))
  end

  def get(path, default) when is_list(path) do
    Agent.get(__MODULE__, fn %{merged: merged} ->
      case get_in(merged, path) do
        nil -> default
        val -> val
      end
    end)
  end

  def get_all do
    Agent.get(__MODULE__, & &1.merged)
  end

  @doc """
  Store a runtime value in the in-memory config Agent.
  Does NOT persist to the Settings DB or sync to Application env.
  Use this for transient runtime state (e.g., current workspace).
  """
  def put(key, value) when is_atom(key) do
    Agent.update(__MODULE__, fn state ->
      %{state | merged: Map.put(state.merged, key, value)}
    end)
  end

  def put(path, value) when is_list(path) do
    Agent.update(__MODULE__, fn state ->
      %{state | merged: put_in_path(state.merged, path, value)}
    end)
  end

  @doc """
  Persist a setting at `path` (list of atoms) to:
  1. The in-memory merged state
  2. The Settings DB as a preference
  3. Application env (for keys that need runtime access)
  """
  def put_setting(path, value, opts \\ []) when is_list(path) do
    # Persist to Settings DB unless explicitly skipped
    if opts[:persist] != false do
      settings_key = path_to_settings_key(path)
      serialized = serialize_value(value)
      safe_persist_preference(settings_key, serialized)
    end

    Agent.update(__MODULE__, fn state ->
      new_merged = put_in_path(state.merged, path, value)
      sync_to_application_env(path, value)
      %{state | merged: new_merged}
    end)
  end

  @doc """
  Store a secret keyed by its env-var name. Requires the vault to be
  unlocked — returns `{:error, :vault_locked}` if the vault is locked.
  """
  def put_secret(env_var, value) when is_binary(env_var) and is_binary(value) do
    if vault_available?() do
      case Worth.Settings.put(env_var, value, "secret") do
        {:ok, _setting} -> :ok
        :ok -> :ok
        error -> error
      end
    else
      {:error, :vault_locked}
    end
  end

  @doc """
  Reload configuration from compile-time env + Settings DB.
  """
  def reload do
    compile_time = load_compile_time()
    overrides = load_settings_overrides()
    merged = deep_merge(compile_time, overrides)
    sync_to_application_env(merged)
    Agent.update(__MODULE__, fn _ -> %{base: compile_time, merged: merged} end)
  end

  # ----- internals -----

  defp load_compile_time do
    :worth
    |> Application.get_all_env()
    |> Map.new()
  end

  defp load_settings_overrides do
    Enum.reduce(@preference_mappings, %{}, fn {key, path, parser}, acc ->
      case safe_get_preference(key) do
        nil -> acc
        val -> put_in_path(acc, path, parser.(val))
      end
    end)
  end

  defp safe_get_preference(key) do
    Worth.Settings.get_preference(key)
  catch
    :exit, {:noproc, _} -> nil
    :exit, _ -> nil
  end

  defp vault_available? do
    not Worth.Settings.locked?()
  catch
    :exit, {:noproc, _} -> false
    :exit, _ -> false
  end

  defp safe_persist_preference(key, value) do
    case Worth.Settings.put(key, value, "preference") do
      {:ok, _} ->
        :ok

      :ok ->
        :ok

      {:error, e} ->
        Logger.warning("Worth.Config: failed to persist preference #{key}: #{inspect(e)}")
        :ok
    end
  rescue
    DBConnection.OwnershipError -> :ok
    Ecto.StaleEntryError -> :ok
  catch
    :exit, {:noproc, _} -> :ok
    :exit, _ -> :ok
  end

  @doc """
  Persist model routing config to both the in-memory Agent and the Settings DB.

  Accepts a map with keys like `%{mode: "auto" | "manual", preference: "...",
  filter: "...", manual_model: %{provider: "...", model_id: "..."}}`.
  """
  def save_routing(routing) when is_map(routing) do
    Agent.update(__MODULE__, fn state ->
      %{state | merged: put_in_path(state.merged, [:model_routing], routing)}
    end)

    persist_routing_preferences(routing)
  end

  defp persist_routing_preferences(routing) do
    safe_persist_preference("model_routing_mode", Map.get(routing, :mode, "auto"))

    pref = Map.get(routing, :preference)
    if pref, do: safe_persist_preference("model_routing_preference", pref)

    filter = Map.get(routing, :filter)
    if filter, do: safe_persist_preference("model_routing_filter", filter)

    case Map.get(routing, :manual_model) do
      %{provider: p, model_id: m} ->
        safe_persist_preference("model_routing_manual_model", "#{p}/#{m}")

      _ ->
        safe_persist_preference("model_routing_manual_model", "")
    end
  end

  defp path_to_settings_key([:workspace_directory]), do: "workspace_directory"
  defp path_to_settings_key([:memory, :enabled]), do: "memory_enabled"
  defp path_to_settings_key([:memory, :decay_days]), do: "memory_decay_days"
  defp path_to_settings_key([:memory, :embedding_model]), do: "embedding_model"
  defp path_to_settings_key(path), do: Enum.map_join(path, ".", &to_string/1)

  # Sync the full merged config to Application env at boot
  defp sync_to_application_env(%{} = merged) do
    case merged[:workspace_directory] do
      nil -> :ok
      path when is_binary(path) -> Application.put_env(:worth, :workspace_directory, path)
    end
  end

  # Sync individual path updates
  defp sync_to_application_env([:workspace_directory], value) when is_binary(value) do
    Application.put_env(:worth, :workspace_directory, value)
  end

  defp sync_to_application_env(_path, _value), do: :ok

  defp put_in_path(state, [key], value), do: Map.put(state, key, value)

  defp put_in_path(state, [key | rest], value) do
    inner = Map.get(state, key, %{})
    inner = if is_map(inner), do: inner, else: %{}
    Map.put(state, key, put_in_path(inner, rest, value))
  end

  defp deep_merge(a, b) when is_map(a) and is_map(b) do
    Map.merge(a, b, fn _k, v1, v2 -> deep_merge(v1, v2) end)
  end

  defp deep_merge(_a, b), do: b

  defp serialize_value(val) when is_binary(val), do: val
  defp serialize_value(val) when is_boolean(val), do: to_string(val)
  defp serialize_value(val) when is_integer(val), do: to_string(val)
  defp serialize_value(val) when is_float(val), do: to_string(val)
  defp serialize_value(val) when is_atom(val), do: Atom.to_string(val)

  defp serialize_value(val) when is_list(val) or is_map(val) do
    case Jason.encode(val) do
      {:ok, json} -> json
      _ -> inspect(val)
    end
  end

  defp serialize_value(val), do: to_string(val)

  # Public parsers for preference mappings
  @doc false
  def parse_string(val), do: val
  @doc false
  def parse_boolean("true"), do: true
  def parse_boolean("false"), do: false
  def parse_boolean(val), do: val
  @doc false
  def parse_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> val
    end
  end

  def parse_integer(val), do: val
end
