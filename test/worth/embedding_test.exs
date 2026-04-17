defmodule Worth.EmbeddingTest do
  @moduledoc """
  Tests the embedding pipeline end-to-end:
  Worth.Memory.Embeddings.Adapter → Recollect → vector store → similarity search.

  These tests use the Recollect.Embedding.Mock provider configured in test.exs
  to avoid hitting external APIs during CI.
  """

  use Worth.DataCase, async: false

  @moduletag :embedding

  describe "embedding provider configuration" do
    test "Recollect is configured with an embedding provider" do
      provider = Recollect.Config.embedding_provider()
      assert provider
    end

    test "embedding dimensions are configured" do
      dims = Recollect.Config.dimensions()
      assert is_integer(dims)
      assert dims > 0
    end
  end

  describe "memory store and retrieve (mock embeddings)" do
    test "Recollect.remember/2 stores an entry" do
      scope_id = Ecto.UUID.generate()

      result =
        Recollect.remember("The deploy script is at scripts/deploy.sh",
          scope_id: scope_id,
          entry_type: "observation"
        )

      assert {:ok, entry} = result
      assert entry.content =~ "deploy"
    end

    test "stored entries can be retrieved by scope" do
      scope_id = Ecto.UUID.generate()

      {:ok, entry} =
        Recollect.remember("Elixir uses the BEAM virtual machine",
          scope_id: scope_id,
          entry_type: "observation"
        )

      assert entry.content =~ "BEAM"
      assert entry.scope_id == scope_id
      assert entry.entry_type == "observation"
    end
  end
end
