defmodule Worth.Memory.Embeddings.StaleCheck do
  @moduledoc """
  Boot-time check that compares the configured embedding model id
  against the model recorded on the most recently embedded row in
  the mneme tables. When they differ, logs a warning suggesting
  `/memory reembed`. Does not auto-trigger — re-embedding is a
  potentially expensive operation that the user should approve.
  """

  alias Mneme.Config

  require Logger

  @tables ["mneme_chunks", "mneme_entries", "mneme_entities"]

  def run do
    repo = Config.repo()
    current_model = current_model_id()

    if current_model do
      stale =
        Enum.flat_map(@tables, fn table ->
          case latest_model_id(repo, table) do
            nil -> []
            ^current_model -> []
            other -> [{table, other}]
          end
        end)

      if stale != [] do
        details =
          Enum.map_join(stale, ", ", fn {table, m} -> "#{table}=#{m}" end)

        Logger.info(
          "Worth.Memory: configured embedding model #{inspect(current_model)} differs from stored rows (#{details}). Run `/memory reembed` to migrate."
        )
      end
    end
  rescue
    e ->
      Logger.debug("Worth.Memory.Embeddings.StaleCheck failed: #{Exception.message(e)}")
  end

  defp current_model_id do
    case Mneme.EmbeddingProvider.model_id() do
      id when is_binary(id) -> id
      _ -> nil
    end
  end

  defp latest_model_id(repo, table) do
    case Ecto.Adapters.SQL.query(
           repo,
           "SELECT embedding_model_id FROM #{table} WHERE embedding_model_id IS NOT NULL ORDER BY rowid DESC LIMIT 1",
           []
         ) do
      {:ok, %{rows: [[id]]}} -> id
      _ -> nil
    end
  end
end
