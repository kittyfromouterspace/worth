defmodule Worth.Config do
  @moduledoc """
  In-memory holder for Worth's runtime configuration.

  At boot we load three layers and merge them in this order (later layers
  override earlier ones):

    1. Compile-time `Application.get_all_env(:worth)` (config/*.exs)
    2. The on-disk user config from `Worth.Config.Store` (`~/.worth/config.exs`)

  Secrets stored under `[:secrets, :<env_var_name>]` are exported into the
  process environment via `System.put_env/2` so downstream consumers
  (notably `AgentEx.LLM.Credentials`) can pick them up without having to
  know about Worth's config layout.
  """

  use Agent

  alias Worth.Config.Store

  def start_link(_opts) do
    {compile_time, disk} = load_layers()
    state = %{compile_time: compile_time, disk: disk, merged: deep_merge(compile_time, disk)}
    export_secrets(state.merged)

    # Sync disk values to Application env so runtime code using
    # Application.get_env can see user settings
    sync_disk_to_application_env(disk)

    Agent.start_link(fn -> state end, name: __MODULE__)
  end

  # On startup, sync any user settings from disk to Application env
  # so that code using Application.get_env(:worth, :key) sees them
  defp sync_disk_to_application_env(disk) do
    # home_directory - this affects where skills, workspaces, etc. are stored
    case disk[:home_directory] do
      nil -> :ok
      path when is_binary(path) -> Application.put_env(:worth, :home_directory, path)
    end
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
  Persist a setting at `path` (list of atoms) to:
  1. The in-memory merged state
  2. The on-disk config file
  3. Application env (for keys that need runtime access via Application.get_env)

  Only the user-overrides layer is written to disk; compile-time defaults
  are not round-tripped.
  """
  def put_setting(path, value) when is_list(path) do
    Agent.update(__MODULE__, fn state ->
      new_disk = put_in_path(state.disk, path, value)
      Store.save!(new_disk)
      new_merged = deep_merge(state.compile_time, new_disk)

      # Sync certain critical keys to Application env for runtime access
      sync_to_application_env(path, value)

      %{state | disk: new_disk, merged: new_merged}
    end)
  end

  # Sync critical config values to Application env so other parts of the
  # system can access them via Application.get_env(:worth, :key)
  defp sync_to_application_env([:home_directory], value) when is_binary(value) do
    Application.put_env(:worth, :home_directory, value)
  end

  defp sync_to_application_env(_path, _value), do: :ok

  @doc """
  Store a secret keyed by its env-var name. If the encrypted vault is
  unlocked, the secret goes into the encrypted DB store. Otherwise it
  falls back to the plaintext disk config.
  """
  def put_secret(env_var, value) when is_binary(env_var) and is_binary(value) do
    System.put_env(env_var, value)

    if vault_available?() do
      Worth.Settings.put(env_var, value, "secret")
    else
      put_setting([:secrets, env_var], value)
    end
  end

  @doc """
  Export secrets from the encrypted vault into the process environment.
  Called after vault unlock so credential resolvers can find them.
  """
  def export_vault_secrets do
    if vault_available?() do
      for setting <- Worth.Settings.all_by_category("secret") do
        if is_binary(setting.encrypted_value) and setting.encrypted_value != "" do
          System.put_env(setting.key, setting.encrypted_value)
        end
      end

      :ok
    else
      :noop
    end
  end

  defp vault_available? do
    not Worth.Settings.locked?()
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end

  @doc """
  Reload from compile-time env + disk. Used by tests and the `/setup`
  command after editing the file out-of-band.
  """
  def reload do
    {compile_time, disk} = load_layers()
    merged = deep_merge(compile_time, disk)
    export_secrets(merged)
    Agent.update(__MODULE__, fn _ -> %{compile_time: compile_time, disk: disk, merged: merged} end)
  end

  # ----- internals -----

  defp load_layers do
    compile_time =
      Application.get_all_env(:worth)
      |> Enum.into(%{})
      |> resolve_env_values()

    {compile_time, Store.load()}
  end

  defp export_secrets(%{secrets: secrets}) when is_map(secrets) do
    Enum.each(secrets, fn
      {var, value} when is_binary(var) and is_binary(value) and value != "" ->
        System.put_env(var, value)

      _ ->
        :ok
    end)
  end

  defp export_secrets(_), do: :ok

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

  defp resolve_env_values(%_{} = struct), do: struct

  defp resolve_env_values(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, resolve_env_values(v)} end)
  end

  defp resolve_env_values(list) when is_list(list) do
    Enum.map(list, &resolve_env_values/1)
  end

  defp resolve_env_values({:env, var}) do
    case System.get_env(var) do
      nil -> nil
      val -> val
    end
  end

  # Keyword pairs: preserve the key, recurse into the value. Without this
  # clause `Enum.map` over a keyword list passes each `{k, v}` tuple
  # through the catch-all and any nested `{:env, ...}` inside `v` never
  # gets resolved — leading to Req warnings about non-string header
  # values when an adapter receives the raw tuple as its api_key.
  # Order matters: this MUST come after the `{:env, var}` clause,
  # because `:env` is also an atom and would otherwise match here first.
  defp resolve_env_values({k, v}) when is_atom(k) do
    {k, resolve_env_values(v)}
  end

  defp resolve_env_values(other), do: other
end
