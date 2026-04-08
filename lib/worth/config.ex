defmodule Worth.Config do
  use Agent

  def start_link(_opts) do
    initial = resolve_config(Application.get_all_env(:worth))
    Agent.start_link(fn -> initial end, name: __MODULE__)
  end

  def get(key, default \\ nil) do
    Agent.get(__MODULE__, &Map.get(&1, key, default))
  end

  def get_all do
    Agent.get(__MODULE__, & &1)
  end

  def reload do
    resolved = resolve_config(Application.get_all_env(:worth))
    Agent.update(__MODULE__, fn _ -> resolved end)
  end

  defp resolve_config(config) do
    config
    |> Enum.into(%{})
    |> resolve_env_values()
  end

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
