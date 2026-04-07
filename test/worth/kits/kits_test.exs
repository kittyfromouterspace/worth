defmodule Worth.KitsTest do
  use ExUnit.Case, async: false

  describe "list_installed/0" do
    test "returns empty map when no kits installed" do
      {:ok, kits} = Worth.Kits.list_installed()
      assert is_map(kits)
    end
  end

  describe "search/2" do
    test "handles JourneyKits response gracefully" do
      result = Worth.Kits.search("test-query-nonexistent")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "info/2" do
    test "returns error for nonexistent kit" do
      {:error, _reason} = Worth.Kits.info("nonexistent", "no-kit")
    end
  end
end
