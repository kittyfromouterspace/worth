defmodule Worth.Workspace.IdentityTest do
  use ExUnit.Case, async: true

  alias Worth.Workspace.Identity

  describe "load/1 with frontmatter" do
    setup do
      dir = Path.join(System.tmp_dir!(), "identity_test_#{:rand.uniform(999_999)}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    test "parses IDENTITY.md with llm frontmatter", %{dir: dir} do
      content = """
      ---
      name: test-project
      llm:
        tiers:
          primary: "anthropic/claude-opus-4-6"
          lightweight: "anthropic/claude-haiku-4-5"
        prefer_free: true
        cost_ceiling_per_turn: 0.05
      ---

      # Test Project

      Some description.
      """

      File.write!(Path.join(dir, "IDENTITY.md"), content)

      assert {:ok, result} = Identity.load(dir)
      assert result.frontmatter[:name] == "test-project"
      assert result.llm.tiers[:primary] == "anthropic/claude-opus-4-6"
      assert result.llm.tiers[:lightweight] == "anthropic/claude-haiku-4-5"
      assert result.llm.prefer_free == true
      assert result.llm.cost_ceiling_per_turn == 0.05
      assert result.body =~ "# Test Project"
    end

    test "handles IDENTITY.md without frontmatter", %{dir: dir} do
      content = "# My Project\n\nJust a regular markdown file.\n"
      File.write!(Path.join(dir, "IDENTITY.md"), content)

      assert {:ok, result} = Identity.load(dir)
      assert result.frontmatter == nil
      assert result.llm == %{}
      assert result.body =~ "# My Project"
    end

    test "handles missing IDENTITY.md", %{dir: dir} do
      assert {:ok, result} = Identity.load(dir)
      assert result.frontmatter == nil
      assert result.body == nil
    end
  end

  describe "tier_overrides/1" do
    setup do
      dir = Path.join(System.tmp_dir!(), "identity_tier_test_#{:rand.uniform(999_999)}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    test "extracts tier overrides", %{dir: dir} do
      content = """
      ---
      llm:
        tiers:
          primary: "anthropic/claude-opus-4-6"
          lightweight: "openai/gpt-4o-mini"
      ---
      # Test
      """

      File.write!(Path.join(dir, "IDENTITY.md"), content)

      tiers = Identity.tier_overrides(dir)
      assert tiers[:primary] == "anthropic/claude-opus-4-6"
      assert tiers[:lightweight] == "openai/gpt-4o-mini"
    end

    test "returns empty map without frontmatter", %{dir: dir} do
      File.write!(Path.join(dir, "IDENTITY.md"), "# Test\n")
      assert Identity.tier_overrides(dir) == %{}
    end
  end

  describe "llm_config/1" do
    setup do
      dir = Path.join(System.tmp_dir!(), "identity_llm_test_#{:rand.uniform(999_999)}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    test "returns full llm config", %{dir: dir} do
      content = """
      ---
      llm:
        tiers:
          primary: "anthropic/claude-sonnet-4"
        prefer_free: false
        prompt_caching: true
      ---
      # Test
      """

      File.write!(Path.join(dir, "IDENTITY.md"), content)

      config = Identity.llm_config(dir)
      assert config.tiers[:primary] == "anthropic/claude-sonnet-4"
      assert config.prefer_free == false
      assert config.prompt_caching == true
    end
  end
end
