defmodule Worth.Skill.ParserTest do
  use ExUnit.Case

  @valid_skill """
  ---
  name: test-skill
  description: A test skill for parsing
  loading: always
  trust_level: core
  ---
  # Test Skill

  This is the body.
  """

  @skill_with_extensions """
  ---
  name: advanced-skill
  description: An advanced skill with extensions
  loading: on_demand
  model_tier: primary
  provenance: agent
  trust_level: learned
  evolution:
    version: 2
    success_rate: 0.85
    usage_count: 15
  ---
  # Advanced Skill

  Complex instructions here.
  """

  describe "parse/1" do
    test "parses valid SKILL.md with frontmatter and body" do
      {:ok, skill} = Worth.Skill.Parser.parse(@valid_skill)

      assert skill.name == "test-skill"
      assert skill.description == "A test skill for parsing"
      assert skill.loading == :always
      assert skill.trust_level == :core
      assert skill.body =~ "# Test Skill"
    end

    test "parses skill with worth extensions" do
      {:ok, skill} = Worth.Skill.Parser.parse(@skill_with_extensions)

      assert skill.name == "advanced-skill"
      assert skill.loading == :on_demand
      assert skill.model_tier == :primary
      assert skill.provenance == :agent
      assert skill.trust_level == :learned
      assert skill.evolution[:version] == 2
      assert skill.evolution[:success_rate] == 0.85
      assert skill.evolution[:usage_count] == 15
    end

    test "returns error for missing frontmatter" do
      assert {:error, msg} = Worth.Skill.Parser.parse("Just some text without frontmatter")
      assert msg =~ "No frontmatter"
    end

    test "returns error for invalid YAML" do
      invalid = "---\nname: [invalid yaml: {{{\n---\nBody"
      assert {:error, msg} = Worth.Skill.Parser.parse(invalid)
      assert msg =~ "YAML"
    end

    test "handles missing optional fields with defaults" do
      minimal = "---\nname: minimal\n---\nBody"
      {:ok, skill} = Worth.Skill.Parser.parse(minimal)

      assert skill.loading == :on_demand
      assert skill.model_tier == :any
      assert skill.provenance == :human
      assert skill.trust_level == :installed
      assert skill.evolution[:version] == 1
    end
  end

  describe "parse_file/1" do
    test "parses a core skill file" do
      path = Path.join(:code.priv_dir(:worth), "core_skills/agent-tools/SKILL.md")
      {:ok, skill} = Worth.Skill.Parser.parse_file(path)

      assert skill.name == "agent-tools"
      assert skill.trust_level == :core
      assert skill.loading == :always
      assert skill.body =~ "File Operations"
    end

    test "returns error for nonexistent file" do
      assert {:error, msg} = Worth.Skill.Parser.parse_file("/nonexistent/SKILL.md")
      assert msg =~ "Failed to read"
    end
  end

  describe "to_frontmatter_string/1" do
    test "roundtrips a parsed skill" do
      {:ok, skill} = Worth.Skill.Parser.parse(@valid_skill)
      serialized = Worth.Skill.Parser.to_frontmatter_string(skill)
      {:ok, reparsed} = Worth.Skill.Parser.parse(serialized)

      assert reparsed.name == skill.name
      assert reparsed.description == skill.description
      assert reparsed.trust_level == skill.trust_level
      assert reparsed.body == skill.body
    end
  end
end
