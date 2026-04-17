defmodule Worth.Memory.Manager do
  @moduledoc false
  @scope_uuid "00000000-0000-0000-0000-000000000001"

  def search(query, opts \\ []) do
    unless_disabled(opts, fn ->
      search_opts = build_search_opts(opts)
      context_pack = Recollect.search(query, search_opts)
      track_retrieved(context_pack)
      apply_workspace_boost(context_pack, opts)
    end)
  end

  def remember(content, opts \\ []) do
    unless_disabled(opts, fn ->
      merged =
        Enum.reject(
          [
            scope_id: @scope_uuid,
            entry_type: opts[:entry_type] || "note",
            source: opts[:source] || "agent",
            confidence: opts[:confidence],
            half_life_days: opts[:half_life_days],
            pinned: opts[:pinned],
            emotional_valence: opts[:emotional_valence],
            metadata: build_metadata(opts),
            context_hints: build_context_hints(opts),
            tags: opts[:tags]
          ],
          fn {_k, v} -> is_nil(v) end
        )

      Recollect.remember(content, merged)
    end)
  end

  def recent(opts \\ []) do
    unless_disabled(opts, fn ->
      limit = opts[:limit] || 20
      Recollect.Knowledge.recent(@scope_uuid, limit: limit)
    end)
  end

  def working_push(content, opts \\ []) do
    unless_disabled(opts, fn ->
      scope = working_scope(opts)
      Recollect.WorkingMemory.push(scope, content, opts)
    end)
  end

  def working_read(opts \\ []) do
    unless_disabled(opts, fn ->
      scope = working_scope(opts)
      Recollect.WorkingMemory.read(scope)
    end)
  end

  def working_clear(opts \\ []) do
    unless_disabled(opts, fn ->
      scope = working_scope(opts)
      Recollect.WorkingMemory.clear(scope)
    end)
  end

  def working_flush(opts \\ []) do
    unless_disabled(opts, fn ->
      scope = working_scope(opts)

      case Recollect.WorkingMemory.read(scope) do
        {:ok, entries} ->
          flushed =
            entries
            |> Enum.filter(fn e -> Map.get(e, :importance, 0) >= 0.5 end)
            |> Enum.map(fn e ->
              remember(e.content,
                entry_type: e.metadata[:entry_type] || "note",
                source: "working_memory",
                confidence: min(Map.get(e, :importance, 0.5) * 1.2, 1.0),
                metadata: Map.get(e, :metadata, %{})
              )
            end)

          Recollect.WorkingMemory.clear(scope)
          {:ok, length(flushed)}

        error ->
          error
      end
    end)
  end

  def outcome_good(opts \\ []) do
    unless_disabled(opts, fn ->
      Recollect.Outcome.good(@scope_uuid)
    end)
  end

  def outcome_bad(opts \\ []) do
    unless_disabled(opts, fn ->
      Recollect.Outcome.bad(@scope_uuid)
    end)
  end

  def build_memory_context(query, opts \\ []) do
    case search(query, opts) do
      {:ok, context_pack} ->
        text = Recollect.Search.ContextFormatter.format(context_pack)

        if text == "" do
          {:ok, nil}
        else
          {:ok, text}
        end

      error ->
        error
    end
  end

  defp unless_disabled(opts, fun) do
    if memory_enabled?(opts) do
      result = fun.()

      if match?({:ok, _}, result) or match?({:error, _}, result) do
        result
      else
        {:ok, result}
      end
    else
      {:ok, nil}
    end
  end

  defp memory_enabled?(opts) do
    Keyword.get(opts, :enabled, Worth.Config.get([:memory, :enabled], true))
  end

  defp build_search_opts(opts) do
    base = [
      scope_id: @scope_uuid,
      limit: opts[:limit] || 10,
      tier: :lightweight
    ]

    if opts[:owner_id], do: Keyword.put(base, :owner_id, opts[:owner_id]), else: base
  end

  defp track_retrieved({:ok, %{entries: entries}}) when is_list(entries) do
    ids = Enum.map(entries, & &1.id)
    if ids != [], do: Recollect.OutcomeTracker.set(@scope_uuid, ids)
    {:ok, %{entries: entries}}
  end

  defp track_retrieved(other), do: other

  defp apply_workspace_boost({:ok, context_pack}, opts) do
    workspace = opts[:workspace]

    if workspace do
      current_ctx = %{workspace: workspace}
      boosted_entries = Recollect.Search.ContextBooster.apply_boost(context_pack.entries, current_ctx)
      {:ok, %{context_pack | entries: boosted_entries}}
    else
      {:ok, context_pack}
    end
  end

  defp apply_workspace_boost(other, _opts), do: other

  defp build_metadata(opts) do
    base = opts[:metadata] || %{}

    base =
      if opts[:workspace] do
        Map.put(base, :workspace, opts[:workspace])
      else
        base
      end

    if opts[:skill] do
      Map.put(base, :skill, opts[:skill])
    else
      base
    end
  end

  defp build_context_hints(opts) do
    hints = Recollect.Context.Detector.detect()

    if opts[:workspace] do
      Map.put(hints, :workspace, opts[:workspace])
    else
      hints
    end
  end

  defp working_scope(opts) do
    workspace = opts[:workspace] || "default"
    "worth:working:#{workspace}"
  end
end
