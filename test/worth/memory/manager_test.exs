defmodule Worth.Memory.ManagerTest do
  use Worth.DataCase, async: false

  describe "remember/2 and search/2" do
    test "stores and retrieves a fact globally" do
      {:ok, _entry} =
        Worth.Memory.Manager.remember("User prefers Elixir over Python",
          entry_type: "observation",
          source: "user",
          workspace: "test-workspace"
        )

      {:ok, %{entries: entries}} =
        Worth.Memory.Manager.search("programming language preference",
          workspace: "test-workspace"
        )

      assert is_list(entries)
    end

    test "tags entries with workspace metadata" do
      {:ok, entry} =
        Worth.Memory.Manager.remember("This project uses conventional commits",
          entry_type: "observation",
          workspace: "my-project"
        )

      assert get_in(entry.metadata, [:workspace]) == "my-project"
    end

    test "returns empty results when memory is disabled" do
      {:ok, nil} =
        Worth.Memory.Manager.remember("test", enabled: false)

      {:ok, nil} =
        Worth.Memory.Manager.search("test", enabled: false)
    end
  end

  describe "recent/1" do
    test "returns recent entries via direct remember + query" do
      {:ok, _} =
        Worth.Memory.Manager.remember("Recent fact one",
          entry_type: "observation",
          workspace: "test"
        )

      {:ok, entries} = Worth.Memory.Manager.recent(workspace: "test", limit: 5)
      assert is_list(entries)
      assert length(entries) >= 1
    end
  end

  describe "working memory" do
    test "push and read working memory entries" do
      {:ok, _} =
        Worth.Memory.Manager.working_push("Session note",
          workspace: "test-ws",
          importance: 0.7
        )

      {:ok, entries} = Worth.Memory.Manager.working_read(workspace: "test-ws")

      assert is_list(entries)
      contents = Enum.map(entries, & &1.content)
      assert "Session note" in contents
    after
      Worth.Memory.Manager.working_clear(workspace: "test-ws")
    end

    test "flush promotes high-importance entries to global store" do
      {:ok, _} =
        Worth.Memory.Manager.working_push("Important finding",
          workspace: "flush-test",
          importance: 0.8,
          metadata: %{entry_type: "observation"}
        )

      {:ok, _} =
        Worth.Memory.Manager.working_push("Trivial note",
          workspace: "flush-test",
          importance: 0.2
        )

      {:ok, count} = Worth.Memory.Manager.working_flush(workspace: "flush-test")
      assert count >= 1
    end
  end

  describe "build_memory_context/2" do
    test "returns formatted context or nil when no results" do
      result =
        Worth.Memory.Manager.build_memory_context("nonexistent topic xyz",
          workspace: "ctx-test"
        )

      case result do
        {:ok, text} when is_binary(text) -> assert true
        {:ok, nil} -> assert true
        other -> flunk("Unexpected result: #{inspect(other)}")
      end
    end
  end
end
