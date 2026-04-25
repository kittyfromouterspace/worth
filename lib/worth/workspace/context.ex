defmodule Worth.Workspace.Context do
  @moduledoc """
  Builds the system prompt for agent sessions.

  Caches the static parts (base prompt, IDENTITY.md, AGENTS.md, skills metadata)
  using an ETS-based cache keyed by workspace path + file mtimes. The dynamic
  parts (memory context, working memory) are fetched fresh on every call.
  """

  alias Worth.Memory.Manager

  @system_prompt_path Path.join(:code.priv_dir(:worth), "prompts/system.md")

  @memory_section_header "\n\n## Memory Context\n\nRelevant knowledge from previous sessions:\n"
  @working_memory_header "\n\n## Working Memory\n\nCurrent session notes:\n"
  @max_memory_chars 4000

  # ETS table for caching static prompt parts
  @cache_table :worth_system_prompt_cache

  # ── Public API ──────────────────────────────────────────────────

  def build_system_prompt(workspace_path, opts \\ []) do
    ensure_cache_table()

    workspace = opts[:workspace] || Path.basename(workspace_path)
    cache_key = {workspace_path, static_mtime_key(workspace_path)}

    # Fetch cached static parts or build and cache them
    static_parts =
      case lookup_cache(cache_key) do
        {:hit, parts} ->
          parts

        :miss ->
          parts = build_static_parts(workspace_path)
          insert_cache(cache_key, parts)
          parts
      end

    # Dynamic parts are always fetched fresh
    dynamic_parts = build_dynamic_parts(workspace, opts[:user_message])

    parts =
      [static_parts.base, static_parts.identity, static_parts.agents, static_parts.skills] ++
        dynamic_parts
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    {:ok, parts}
  end

  @doc "Invalidate the cache for a workspace. Call this when IDENTITY.md or AGENTS.md changes."
  def invalidate_cache(workspace_path) do
    ensure_cache_table()

    # Delete all entries for this workspace path
    :ets.select_delete(@cache_table, [
      {{{workspace_path, :_}, :_}, [], [true]}
    ])
  end

  # ── Cache helpers ───────────────────────────────────────────────

  defp ensure_cache_table do
    if :ets.whereis(@cache_table) == :undefined do
      :ets.new(@cache_table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  defp lookup_cache(key) do
    case :ets.lookup(@cache_table, key) do
      [{^key, parts}] -> {:hit, parts}
      [] -> :miss
    end
  end

  defp insert_cache(key, parts) do
    :ets.insert(@cache_table, {key, parts})
  end

  # ── Static parts (cached) ───────────────────────────────────────

  defp static_mtime_key(workspace_path) do
    files = [
      @system_prompt_path,
      Path.join(workspace_path, "IDENTITY.md"),
      Path.join(workspace_path, "AGENTS.md")
    ]

    Enum.map(files, fn path ->
      case File.stat(path, time: :posix) do
        {:ok, %{mtime: mtime}} -> mtime
        _ -> 0
      end
    end)
  end

  defp build_static_parts(workspace_path) do
    %{
      base: load_base_prompt(),
      identity: load_identity(workspace_path),
      agents: load_agents(workspace_path),
      skills: Worth.Skill.Registry.metadata_for_prompt()
    }
  end

  # ── Dynamic parts (always fresh) ────────────────────────────────

  defp build_dynamic_parts(workspace, user_message) do
    memory_context = load_memory_context(workspace, user_message)
    working_context = load_working_memory(workspace)
    [memory_context, working_context]
  end

  # ── File loaders ────────────────────────────────────────────────

  defp load_base_prompt do
    case File.read(@system_prompt_path) do
      {:ok, content} -> String.trim(content)
      {:error, _} -> "You are Worth, a personal AI assistant that helps with development, research, and automation."
    end
  end

  defp load_identity(workspace_path) do
    case File.read(Path.join(workspace_path, "IDENTITY.md")) do
      {:ok, content} -> String.trim(content)
      {:error, _} -> nil
    end
  end

  defp load_agents(workspace_path) do
    case File.read(Path.join(workspace_path, "AGENTS.md")) do
      {:ok, content} -> String.trim(content)
      {:error, _} -> nil
    end
  end

  # ── Memory loaders ──────────────────────────────────────────────

  defp load_memory_context(workspace, nil) do
    load_recent_memory(workspace)
  end

  defp load_memory_context(workspace, user_message) do
    case Manager.build_memory_context(user_message, workspace: workspace) do
      {:ok, nil} ->
        load_recent_memory(workspace)

      {:ok, text} when byte_size(text) > 0 ->
        truncate(@memory_section_header <> text, @max_memory_chars)

      _ ->
        load_recent_memory(workspace)
    end
  end

  defp load_recent_memory(workspace) do
    case Manager.recent(workspace: workspace, limit: 5) do
      {:ok, entries} when is_list(entries) and entries != [] ->
        lines =
          Enum.map_join(entries, "\n", fn e -> "- #{e.content}" end)

        truncate(@memory_section_header <> lines, @max_memory_chars)

      _ ->
        nil
    end
  end

  defp load_working_memory(workspace) do
    case Manager.working_read(workspace: workspace) do
      {:ok, entries} when is_list(entries) and entries != [] ->
        lines =
          Enum.map_join(entries, "\n", fn e -> "- #{e.content}" end)

        @working_memory_header <> lines

      _ ->
        nil
    end
  end

  defp truncate(text, max_bytes) do
    if byte_size(text) <= max_bytes do
      text
    else
      slice = binary_part(text, 0, max_bytes)
      slice <> "\n... (truncated)"
    end
  end
end
