defmodule Worth.Skill.RefinerTest do
  use ExUnit.Case, async: false

  setup do
    tmp_dir = System.tmp_dir!()
    skill_dir = Path.join(tmp_dir, "refiner-test-skill")
    File.rm_rf(skill_dir)
    File.mkdir_p!(skill_dir)

    skill_content = """
    ---
    name: refiner-test-skill
    description: A test skill for refiner
    loading: on_demand
    trust_level: learned
    provenance: agent
    evolution:
      version: 1
      usage_count: 10
      success_rate: 0.3
      refinement_count: 0
      feedback_summary: "Fails often"
    ---
    # Test Skill

    Original instructions.
    """

    File.write!(Path.join(skill_dir, "SKILL.md"), skill_content)

    user_skills = Path.expand("~/.worth/skills")
    dest = Path.join(user_skills, "refiner-test-skill")

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

  describe "refine/2" do
    test "refines a failing skill without LLM" do
      result = Worth.Skill.Refiner.refine("refiner-test-skill")
      assert {:ok, %{version: 2}} = result
    end

    test "returns no_refinement_needed for healthy skill" do
      tmp_dir = System.tmp_dir!()
      skill_dir = Path.join(tmp_dir, "healthy-skill")
      File.rm_rf(skill_dir)
      File.mkdir_p!(skill_dir)

      skill_content = """
      ---
      name: healthy-skill
      description: A healthy skill
      loading: on_demand
      trust_level: learned
      provenance: agent
      evolution:
        version: 1
        usage_count: 20
        success_rate: 0.9
      ---
      # Healthy Skill

      Good instructions.
      """

      File.write!(Path.join(skill_dir, "SKILL.md"), skill_content)

      user_skills = Path.expand("~/.worth/skills")
      dest = Path.join(user_skills, "healthy-skill")
      File.rm_rf(dest)
      File.mkdir_p!(user_skills)
      File.cp_r(skill_dir, dest)
      Worth.Skill.Registry.refresh()

      result = Worth.Skill.Refiner.refine("healthy-skill")
      assert {:ok, :no_refinement_needed} = result

      File.rm_rf(dest)
      Worth.Skill.Registry.refresh()
    end
  end

  describe "reactive_refine/3" do
    test "appends failure context without LLM" do
      result = Worth.Skill.Refiner.reactive_refine("refiner-test-skill", "Timeout on large files")
      assert {:ok, %{version: 2}} = result
    end
  end

  describe "proactive_review/1" do
    test "returns error for nonexistent skill" do
      assert {:error, _} = Worth.Skill.Refiner.proactive_review("nonexistent-skill-xyz")
    end
  end
end
