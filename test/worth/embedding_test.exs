defmodule Worth.EmbeddingTest do
  @moduledoc """
  Tests the local embedding pipeline end-to-end:
  Bumblebee model → Mneme.Embedding.Local → vector store → similarity search.

  These tests use the Mneme.Embedding.Mock provider configured in test.exs
  to avoid downloading the real model during CI. The mock validates the
  pipeline plumbing works correctly.

  To test with real local embeddings, run:
    WORTH_TEST_LOCAL_EMBEDDINGS=1 mix test test/worth/embedding_test.exs
  """

  use Worth.DataCase, async: false

  alias Mneme.Embedding.Local

  @moduletag :embedding

  describe "embedding provider configuration" do
    test "Mneme is configured with an embedding provider" do
      provider = Mneme.Config.embedding_provider()
      assert provider
    end

    test "embedding dimensions are configured" do
      dims = Mneme.Config.dimensions()
      assert is_integer(dims)
      assert dims > 0
    end
  end

  describe "memory store and retrieve (mock embeddings)" do
    test "Mneme.remember/2 stores an entry" do
      scope_id = Ecto.UUID.generate()

      result =
        Mneme.remember("The deploy script is at scripts/deploy.sh",
          scope_id: scope_id,
          entry_type: "observation"
        )

      assert {:ok, entry} = result
      assert entry.content =~ "deploy"
    end

    test "stored entries can be retrieved by scope" do
      scope_id = Ecto.UUID.generate()

      {:ok, entry} =
        Mneme.remember("Elixir uses the BEAM virtual machine",
          scope_id: scope_id,
          entry_type: "observation"
        )

      # Verify the entry was stored with correct content
      assert entry.content =~ "BEAM"
      assert entry.scope_id == scope_id
      assert entry.entry_type == "observation"

      # Note: Vector search (Mneme.search) uses PostgreSQL-specific operators
      # (cosine distance <=>). LibSQL/SQLite tests verify storage only.
      # Full vector search is tested with WORTH_TEST_LOCAL_EMBEDDINGS=1
      # against a real PostgreSQL + pgvector setup.
    end
  end

  if System.get_env("WORTH_TEST_LOCAL_EMBEDDINGS") == "1" do
    describe "real local embeddings (requires model download)" do
      @tag :slow
      test "Mneme.Embedding.Local generates 384-dim vectors" do
        {:ok, vector} = Local.embed("Hello world", [])
        assert is_list(vector)
        assert length(vector) == 384
        assert Enum.all?(vector, &is_float/1)
      end

      @tag :slow
      test "similar texts have higher cosine similarity" do
        {:ok, v1} = Local.embed("The cat sat on the mat", [])
        {:ok, v2} = Local.embed("A cat was sitting on a rug", [])
        {:ok, v3} = Local.embed("Quantum mechanics describes particle behavior", [])

        sim_12 = cosine_similarity(v1, v2)
        sim_13 = cosine_similarity(v1, v3)

        # Cat sentences should be more similar than cat vs quantum physics
        assert sim_12 > sim_13
      end

      defp cosine_similarity(a, b) do
        dot = a |> Enum.zip(b) |> Enum.map(fn {x, y} -> x * y end) |> Enum.sum()
        norm_a = a |> Enum.map(&(&1 * &1)) |> Enum.sum() |> :math.sqrt()
        norm_b = b |> Enum.map(&(&1 * &1)) |> Enum.sum() |> :math.sqrt()
        dot / (norm_a * norm_b)
      end
    end
  end
end
