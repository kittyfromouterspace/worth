defmodule Worth.Tools.Memory.Reembed do
  @moduledoc """
  Re-embed all stored memories with the currently configured embedding
  model. Wraps `Recollect.Maintenance.Reembed.run/1` and routes through
  `Agentic.LLM.embed_tier/3` so the same tier resolution that the
  configured `Worth.Memory.Embeddings.Adapter` uses applies here.

  Triggered by:

    * `/memory reembed` slash command
    * direct call from boot-time stale-model detection
    * agent tool `memory_reembed`
  """

  alias Agentic.LLM

  @default_tier :embeddings

  @doc """
  Run a reembed pass.

  Options:

    * `:tier` — embedding tier to use (default: `:embeddings`)
    * `:scope` — `:nil_only` (default), `:all`, `{:stale_model, model_id}`
    * `:tables` — list of recollect table names (default: all three)
    * `:batch_size` — rows per batch (default: `100`)
    * `:progress_callback` — invoked once per batch
  """
  def run(opts \\ []) do
    tier = Keyword.get(opts, :tier, @default_tier)

    embedding_fn = fn text ->
      case LLM.embed_tier(text, tier, []) do
        {:ok, [vector | _], model_id} -> {:ok, vector, model_id}
        {:ok, [], _} -> {:error, :no_embedding_returned}
        {:error, reason} -> {:error, reason}
      end
    end

    progress_cb = Keyword.get(opts, :progress_callback, fn _ -> :ok end)

    Recollect.Maintenance.Reembed.run(
      embedding_fn: embedding_fn,
      progress_callback: progress_cb,
      scope: Keyword.get(opts, :scope, :nil_only),
      tables: Keyword.get(opts, :tables, ["recollect_chunks", "recollect_entries", "recollect_entities"]),
      batch_size: Keyword.get(opts, :batch_size, 100)
    )
  end
end
