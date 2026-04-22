defmodule Recollect.Embedding.Mock do
  @moduledoc """
  Deterministic embedding provider used by Worth's test suite.

  Recollect ships its own copy under `test/support/` for its own tests,
  but that path isn't compiled when Recollect is consumed as a dependency,
  so Worth keeps a local copy here.
  """

  @behaviour Recollect.EmbeddingProvider

  @dimensions 1536
  @model_id "mock-1536"

  @impl true
  def dimensions(_opts), do: @dimensions

  @impl true
  def generate(texts, _opts) when is_list(texts) do
    {:ok, Enum.map(texts, &mock_embedding/1)}
  end

  @impl true
  def embed(text, _opts) do
    {:ok, mock_embedding(text)}
  end

  @impl true
  def model_id(_opts), do: @model_id

  defp mock_embedding(text) when is_binary(text) do
    :sha256
    |> :crypto.hash(text)
    |> :binary.bin_to_list()
    |> Stream.cycle()
    |> Stream.take(@dimensions)
    |> Enum.map(fn b -> b / 255.0 * 2.0 - 1.0 end)
  end
end
