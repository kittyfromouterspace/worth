defmodule Worth.Skill.Evaluator do
  def record_success(skill_name) do
    Worth.Skill.Service.record_usage(skill_name, true)
  end

  def record_failure(skill_name) do
    Worth.Skill.Service.record_usage(skill_name, false)
  end

  def should_promote?(skill_name) do
    case Worth.Skill.Service.read(skill_name) do
      {:ok, skill} ->
        Worth.Skill.Trust.meets_promotion_criteria?(skill, :installed) and
          skill.trust_level in [:learned, :unverified]

      _ ->
        false
    end
  end

  def should_refine?(skill_name) do
    case Worth.Skill.Service.read(skill_name) do
      {:ok, skill} ->
        evolution = skill.evolution
        usage = evolution[:usage_count] || 0
        rate = evolution[:success_rate] || 0.0
        usage > 0 and rate < 0.6

      _ ->
        false
    end
  end

  def performance_summary(skill_name) do
    case Worth.Skill.Service.read(skill_name) do
      {:ok, skill} ->
        evo = skill.evolution

        %{
          name: skill.name,
          trust_level: skill.trust_level,
          usage_count: evo[:usage_count] || 0,
          success_rate: evo[:success_rate] || 0.0,
          version: evo[:version] || 1,
          last_used: evo[:last_used],
          can_promote: Worth.Skill.Trust.meets_promotion_criteria?(skill, :installed),
          needs_refinement: should_refine?(skill_name)
        }

      _ ->
        nil
    end
  end
end
