defmodule Worth.Learning.ProjectMappingTest do
  use ExUnit.Case, async: true

  alias Worth.Learning.ProjectMapping

  describe "similar_to_workspace?/2" do
    test "matches direct substring" do
      assert ProjectMapping.similar_to_workspace?("homunculus", "homunculus")
      assert ProjectMapping.similar_to_workspace?("homunculus", "-home-lenz-code-homunculus")
      assert ProjectMapping.similar_to_workspace?("worth", "-home-lenz-code-worth")
    end

    test "matches when workspace is substring of project" do
      assert ProjectMapping.similar_to_workspace?("worth", "worth-project")
    end

    test "matches word-level overlap ignoring common path segments" do
      assert ProjectMapping.similar_to_workspace?("homunculus", "home lenz code homunculus")
      assert ProjectMapping.similar_to_workspace?("my-app", "home lenz code my-app")
    end

    test "ignores common path segments alone" do
      refute ProjectMapping.similar_to_workspace?("home", "home lenz code")
      refute ProjectMapping.similar_to_workspace?("code", "home lenz code")
      refute ProjectMapping.similar_to_workspace?("lenz", "home lenz code")
    end

    test "handles hyphens and underscores" do
      assert ProjectMapping.similar_to_workspace?("my_app", "home lenz code my-app")
      assert ProjectMapping.similar_to_workspace?("my-app", "home lenz code my_app")
    end

    test "case insensitive" do
      assert ProjectMapping.similar_to_workspace?("Homunculus", "homunculus")
      assert ProjectMapping.similar_to_workspace?("HOMUNCULUS", "homunculus")
      assert ProjectMapping.similar_to_workspace?("homunculus", "HOMUNCULUS")
    end

    test "returns false for unrelated names" do
      refute ProjectMapping.similar_to_workspace?("homunculus", "worth")
      refute ProjectMapping.similar_to_workspace?("foo", "bar-baz")
      refute ProjectMapping.similar_to_workspace?("react-app", "vue-project")
    end
  end
end
