defmodule Worth.Skill.TrustTest do
  use ExUnit.Case

  alias Worth.Skill.Trust

  describe "tool_access/1" do
    test "core skills have full access" do
      assert Trust.tool_access(:core) == :all
    end

    test "installed skills have full access" do
      assert Trust.tool_access(:installed) == :all
    end

    test "learned skills have restricted access" do
      assert Trust.tool_access(:learned) == :restricted
    end

    test "unverified skills have readonly access" do
      assert Trust.tool_access(:unverified) == :readonly
    end
  end

  describe "promotion_path/1" do
    test "unverified can promote to installed then core" do
      assert Trust.promotion_path(:unverified) == [:installed, :core]
    end

    test "learned can promote to installed then core" do
      assert Trust.promotion_path(:learned) == [:installed, :core]
    end

    test "core has no promotion path" do
      assert Trust.promotion_path(:core) == []
    end
  end

  describe "meets_promotion_criteria?/2" do
    test "meets criteria when success rate and usage are sufficient" do
      skill = %{trust_level: :learned, evolution: %{success_rate: 0.9, usage_count: 15}}
      assert Trust.meets_promotion_criteria?(skill, :installed)
    end

    test "fails when success rate too low" do
      skill = %{trust_level: :learned, evolution: %{success_rate: 0.5, usage_count: 15}}
      refute Trust.meets_promotion_criteria?(skill, :installed)
    end

    test "fails when usage count too low" do
      skill = %{trust_level: :learned, evolution: %{success_rate: 0.9, usage_count: 3}}
      refute Trust.meets_promotion_criteria?(skill, :installed)
    end
  end
end
