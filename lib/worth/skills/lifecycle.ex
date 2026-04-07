defmodule Worth.Skill.Lifecycle do
  @create_prompt """
  Based on the following experience, create a reusable skill. The skill should be a concise set of instructions
  that captures the pattern used to solve this type of problem. Format it as plain markdown instructions.

  Experience:
  """

  def create_from_experience(name, description, experience, opts \\ []) do
    content = build_skill_content(experience, Keyword.get(opts, :llm_fn))

    Worth.Skill.Service.install(
      %{type: :content, name: name, content: content},
      description: description,
      trust_level: :learned,
      provenance: :agent,
      allowed_tools: opts[:allowed_tools]
    )
  end

  def create_from_failure(name, description, failure_context, opts \\ []) do
    content =
      "## Failure Recovery: #{description}\n\n#{failure_context}\n\n## Guidelines\n\n- Identify the failure pattern early\n- Apply the recovery steps systematically\n- Validate the fix before proceeding\n"

    Worth.Skill.Service.install(
      %{type: :content, name: name, content: content},
      description: "Learned from failure: #{description}",
      trust_level: :learned,
      provenance: :agent
    )
  end

  def promote(skill_name) do
    case Worth.Skill.Service.read(skill_name) do
      {:ok, skill} ->
        next_levels = Worth.Skill.Trust.promotion_path(skill.trust_level)

        case next_levels do
          [target | _] ->
            if Worth.Skill.Trust.meets_promotion_criteria?(skill, target) do
              {:ok, :needs_user_approval, target}
            else
              {:error, "Skill does not meet promotion criteria for #{target}"}
            end

          [] ->
            {:error, "Skill is already at highest trust level"}
        end

      error ->
        error
    end
  end

  defp build_skill_content(experience, nil) do
    @create_prompt <> experience <> "\n\n## Instructions\n\n[Agent-generated skill from experience]"
  end

  defp build_skill_content(experience, llm_fn) do
    prompt = @create_prompt <> experience

    try do
      case llm_fn.([%{role: "user", content: prompt}]) do
        {:ok, %{"content" => content}} -> content
        {:ok, %{content: content}} -> content
        _ -> build_skill_content(experience, nil)
      end
    rescue
      _ -> build_skill_content(experience, nil)
    end
  end
end
