defmodule Worth.Skill.VersionerTest do
  use ExUnit.Case, async: false

  setup do
    tmp_dir = System.tmp_dir!()
    skill_dir = Path.join(tmp_dir, "versioner-test-skill")
    File.rm_rf(skill_dir)
    File.mkdir_p!(skill_dir)

    skill_content = """
    ---
    name: versioner-test-skill
    description: A test skill for versioner
    loading: on_demand
    trust_level: learned
    provenance: agent
    evolution:
      version: 1
      usage_count: 5
      success_rate: 0.8
    ---
    # Test Skill

    Instructions.
    """

    File.write!(Path.join(skill_dir, "SKILL.md"), skill_content)

    user_skills = Path.expand("~/.worth/skills")
    dest = Path.join(user_skills, "versioner-test-skill")

    File.rm_rf(dest)
    File.mkdir_p!(user_skills)
    File.cp_r(skill_dir, dest)

    Worth.Skill.Registry.refresh()

    on_exit(fn ->
      File.rm_rf(dest)
      File.rm_rf(skill_dir)
      Worth.Skill.Registry.refresh()
    end)

    :ok
  end

  describe "save_version/1" do
    test "saves current version to history" do
      assert {:ok, _path} = Worth.Skill.Versioner.save_version("versioner-test-skill")
    end

    test "returns already_saved for duplicate save" do
      Worth.Skill.Versioner.save_version("versioner-test-skill")
      assert {:ok, :already_saved} = Worth.Skill.Versioner.save_version("versioner-test-skill")
    end

    test "returns error for nonexistent skill" do
      assert {:error, _} = Worth.Skill.Versioner.save_version("nonexistent-skill-xyz")
    end
  end

  describe "list_versions/1" do
    test "returns empty list when no history" do
      assert {:ok, []} = Worth.Skill.Versioner.list_versions("versioner-test-skill")
    end

    test "lists saved versions" do
      Worth.Skill.Versioner.save_version("versioner-test-skill")
      assert {:ok, [{1, %{path: _}}]} = Worth.Skill.Versioner.list_versions("versioner-test-skill")
    end
  end
end
