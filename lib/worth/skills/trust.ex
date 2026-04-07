defmodule Worth.Skill.Trust do
  @trust_levels [:core, :installed, :learned, :unverified]

  @tool_access %{
    core: :all,
    installed: :all,
    learned: :restricted,
    unverified: :readonly
  }

  def trust_levels, do: @trust_levels

  def tool_access(trust_level), do: Map.get(@tool_access, trust_level, :readonly)

  def can_use_tool?(skill, tool_name) do
    case tool_access(skill.trust_level) do
      :all -> true
      :readonly -> tool_name in readonly_tools()
      :restricted -> allowed_to_use?(skill, tool_name)
    end
  end

  def promotion_path(:unverified), do: [:installed, :core]
  def promotion_path(:learned), do: [:installed, :core]
  def promotion_path(:installed), do: [:core]
  def promotion_path(:core), do: []

  def can_promote_to?(current, target) do
    target in promotion_path(current)
  end

  def promotion_criteria do
    %{
      installed: [min_success_rate: 0.7, min_usage_count: 5],
      core: [min_success_rate: 0.8, min_usage_count: 10]
    }
  end

  def meets_promotion_criteria?(skill, target_level) do
    criteria = Map.get(promotion_criteria(), target_level, [])
    evolution = skill.evolution

    Enum.all?(criteria, fn
      {:min_success_rate, min} -> (evolution[:success_rate] || 0.0) >= min
      {:min_usage_count, min} -> (evolution[:usage_count] || 0) >= min
    end)
  end

  defp readonly_tools do
    ~w(read_file list_files memory_query memory_recall skill_list skill_read)
  end

  defp allowed_to_use?(skill, tool_name) do
    case skill.allowed_tools do
      nil -> true
      tools when is_list(tools) -> tool_name in tools
      _ -> true
    end
  end
end
