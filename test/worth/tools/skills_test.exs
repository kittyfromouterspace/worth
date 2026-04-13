defmodule Worth.Tools.SkillsTest do
  use ExUnit.Case

  alias Worth.Tools.Skills

  describe "definitions/0" do
    test "returns five tool definitions" do
      defs = Skills.definitions()
      assert length(defs) == 5

      names = Enum.map(defs, & &1.name)
      assert "skill_list" in names
      assert "skill_read" in names
      assert "skill_install" in names
      assert "skill_remove" in names
      assert "skill_create" in names
    end
  end

  describe "execute/3" do
    test "skill_list returns formatted list" do
      {:ok, result} = Skills.execute("skill_list", %{}, "test-ws")
      assert is_binary(result)
      assert result =~ "agent-tools"
    end

    test "skill_list with filter" do
      {:ok, result} = Skills.execute("skill_list", %{"filter" => "core"}, "test-ws")
      assert is_binary(result)
    end

    test "skill_read returns skill body for core skill" do
      {:ok, body} = Skills.execute("skill_read", %{"name" => "agent-tools"}, "test-ws")
      assert body =~ "File Operations"
    end

    test "skill_read returns error for nonexistent skill" do
      {:error, msg} = Skills.execute("skill_read", %{"name" => "nonexistent"}, "test-ws")
      assert msg =~ "Failed to read"
    end

    test "skill_remove returns error for core skill" do
      {:error, msg} = Skills.execute("skill_remove", %{"name" => "agent-tools"}, "test-ws")
      assert msg =~ "Cannot remove core"
    end

    test "unknown tool returns error" do
      {:error, msg} = Skills.execute("skill_unknown", %{}, "test-ws")
      assert msg =~ "Unknown"
    end
  end
end
