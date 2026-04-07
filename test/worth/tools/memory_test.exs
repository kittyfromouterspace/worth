defmodule Worth.Tools.MemoryTest do
  use Worth.DataCase, async: false

  describe "definitions/0" do
    test "returns four tool definitions" do
      defs = Worth.Tools.Memory.definitions()
      assert length(defs) == 4

      names = Enum.map(defs, & &1.name)
      assert "memory_query" in names
      assert "memory_write" in names
      assert "memory_note" in names
      assert "memory_recall" in names
    end

    test "each definition has required fields" do
      for def <- Worth.Tools.Memory.definitions() do
        assert Map.has_key?(def, :name)
        assert Map.has_key?(def, :description)
        assert Map.has_key?(def, :parameters)
      end
    end
  end

  describe "execute/3" do
    test "memory_write stores a fact" do
      result =
        Worth.Tools.Memory.execute(
          "memory_write",
          %{
            "content" => "This project uses Ash",
            "entry_type" => "observation"
          },
          "test-workspace"
        )

      assert match?({:ok, _}, result)
    end

    test "memory_query returns results or no memories message" do
      Worth.Tools.Memory.execute(
        "memory_write",
        %{"content" => "User prefers vim keybindings"},
        "test-ws"
      )

      result =
        Worth.Tools.Memory.execute(
          "memory_query",
          %{"query" => "vim", "limit" => 5},
          "test-ws"
        )

      assert match?({:ok, _}, result)
    end

    test "memory_note adds to working memory" do
      assert {:ok, "Note added to working memory."} =
               Worth.Tools.Memory.execute(
                 "memory_note",
                 %{
                   "content" => "Remember to check config",
                   "importance" => 0.6
                 },
                 "test-ws"
               )
    after
      Worth.Memory.Manager.working_clear(workspace: "test-ws")
    end

    test "memory_recall reads working memory" do
      Worth.Tools.Memory.execute(
        "memory_note",
        %{"content" => "Session observation"},
        "test-ws"
      )

      {:ok, result} = Worth.Tools.Memory.execute("memory_recall", %{}, "test-ws")
      assert is_binary(result)
      assert result =~ "Session observation"
    after
      Worth.Memory.Manager.working_clear(workspace: "test-ws")
    end

    test "memory_recall returns empty message when no notes" do
      {:ok, result} = Worth.Tools.Memory.execute("memory_recall", %{}, "empty-ws")
      assert result =~ "empty"
    after
      Worth.Memory.Manager.working_clear(workspace: "empty-ws")
    end

    test "unknown tool returns error" do
      assert {:error, msg} = Worth.Tools.Memory.execute("memory_unknown", %{}, "test-ws")
      assert String.contains?(msg, "Unknown")
    end
  end
end
