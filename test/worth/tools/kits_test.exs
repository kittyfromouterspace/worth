defmodule Worth.Tools.KitsTest do
  use ExUnit.Case, async: false

  alias Worth.Tools.Kits

  describe "definitions/0" do
    test "returns 5 tool definitions" do
      defs = Kits.definitions()
      assert length(defs) == 5
      names = Enum.map(defs, & &1.name)
      assert "kit_search" in names
      assert "kit_install" in names
      assert "kit_list" in names
      assert "kit_info" in names
      assert "kit_publish" in names
    end

    test "each definition has required fields" do
      Enum.each(Kits.definitions(), fn d ->
        assert d.name
        assert d.description
        assert d.input_schema
      end)
    end
  end

  describe "execute/3" do
    test "kit_list returns message when no kits" do
      {:ok, msg} = Kits.execute("kit_list", %{}, "test")
      assert msg =~ "No kits installed"
    end

    test "kit_search handles response gracefully" do
      result = Kits.execute("kit_search", %{"query" => "nonexistent"}, "test")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "kit_info returns error for nonexistent kit" do
      {:error, _reason} = Kits.execute("kit_info", %{"owner" => "x", "slug" => "y"}, "test")
    end

    test "unknown kit tool returns error" do
      {:error, msg} = Kits.execute("kit_nonexistent", %{}, "test")
      assert msg =~ "Unknown kit tool"
    end
  end
end
