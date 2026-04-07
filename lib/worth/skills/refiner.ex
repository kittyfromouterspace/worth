defmodule Worth.Skill.Refiner do
  @refinement_prompt """
  The following skill has been producing poor results. Analyze the failures and suggest improved instructions.

  Skill: %s
  Current success rate: %s (%d uses)
  Feedback: %s

  Failure patterns:
  %s

  Provide improved skill instructions that address these failures. Keep the same scope and purpose.
  Output ONLY the improved skill body (markdown), no frontmatter.
  """

  def refine(skill_name, opts \\ []) do
    case Worth.Skill.Service.read(skill_name) do
      {:ok, skill} ->
        if should_refine?(skill) do
          perform_refinement(skill, opts)
        else
          {:ok, :no_refinement_needed}
        end

      error ->
        error
    end
  end

  def reactive_refine(skill_name, failure_context, opts \\ []) do
    case Worth.Skill.Service.read(skill_name) do
      {:ok, skill} ->
        perform_reactive_refinement(skill, failure_context, opts)

      error ->
        error
    end
  end

  def proactive_review(skill_name) do
    case Worth.Skill.Service.read(skill_name) do
      {:ok, skill} ->
        evo = skill.evolution
        usage = evo[:usage_count] || 0

        cond do
          usage > 0 and rem(usage, 20) == 0 ->
            {:ok, :review_needed,
             %{
               name: skill.name,
               usage_count: usage,
               success_rate: evo[:success_rate] || 0.0,
               feedback: evo[:feedback_summary]
             }}

          true ->
            {:ok, :no_review_needed}
        end

      error ->
        error
    end
  end

  defp should_refine?(skill) do
    evo = skill.evolution
    usage = evo[:usage_count] || 0
    rate = evo[:success_rate] || 0.0
    usage >= 5 and rate < 0.6
  end

  defp perform_refinement(skill, opts) do
    evo = skill.evolution
    failure_summary = build_failure_summary(skill)

    improved_body =
      case Keyword.get(opts, :llm_fn) do
        nil ->
          "#{skill.body}\n\n## Refined Instructions\n\nAddress these failure patterns:\n#{failure_summary}"

        llm_fn ->
          prompt =
            :io_lib.format(@refinement_prompt, [
              skill.name,
              Float.to_string(evo[:success_rate] || 0.0),
              evo[:usage_count] || 0,
              evo[:feedback_summary] || "No specific feedback",
              failure_summary
            ])
            |> to_string()

          call_llm(llm_fn, prompt, skill.body)
      end

    save_refined_version(skill, improved_body)
  end

  defp perform_reactive_refinement(skill, failure_context, opts) do
    improved_body =
      case Keyword.get(opts, :llm_fn) do
        nil ->
          "#{skill.body}\n\n## Failure Recovery\n\n#{failure_context}\n"

        llm_fn ->
          prompt =
            "The skill '#{skill.name}' failed in this scenario:\n\n#{failure_context}\n\nProvide improved instructions to handle this case. Output ONLY the improved skill body."

          call_llm(llm_fn, prompt, skill.body)
      end

    save_refined_version(skill, improved_body)
  end

  defp call_llm(llm_fn, prompt, fallback) do
    try do
      case llm_fn.([%{role: "user", content: prompt}]) do
        {:ok, %{"content" => [%{"text" => text}]}} -> text
        {:ok, %{"content" => text}} when is_binary(text) -> text
        {:ok, %{content: text}} when is_binary(text) -> text
        _ -> fallback
      end
    rescue
      _ -> fallback
    end
  end

  defp build_failure_summary(skill) do
    evo = skill.evolution
    rate = evo[:success_rate] || 0.0
    usage = evo[:usage_count] || 0
    failures = usage - round(rate * usage)
    feedback = evo[:feedback_summary] || "No detailed feedback available"

    "Success rate: #{Float.round(rate * 100, 1)}% (#{failures} failures out of #{usage} uses)\nFeedback: #{feedback}"
  end

  defp save_refined_version(skill, improved_body) do
    Worth.Skill.Versioner.save_version(skill.name)

    updated = %{
      skill
      | body: improved_body,
        evolution:
          Map.merge(skill.evolution, %{
            version: (skill.evolution[:version] || 1) + 1,
            refinement_count: (skill.evolution[:refinement_count] || 0) + 1,
            last_refined: DateTime.utc_now() |> DateTime.to_iso8601()
          })
    }

    path = Worth.Skill.Service.read(skill.name) |> elem(1) |> get_in([:path])
    resolve_and_save(skill.name, updated)
  end

  defp resolve_and_save(name, skill) do
    case resolve_skill_dir(name) do
      nil ->
        {:error, "Skill directory not found"}

      dir ->
        File.write!(Path.join(dir, "SKILL.md"), Worth.Skill.Parser.to_frontmatter_string(skill))
        Worth.Skill.Registry.refresh()
        {:ok, %{name: name, version: skill.evolution[:version]}}
    end
  end

  defp resolve_skill_dir(name) do
    core = Path.join(:code.priv_dir(:worth), "core_skills")
    user = Path.join(Path.expand("~/.worth/skills"), name)
    learned = Path.join(Path.expand("~/.worth/skills/learned"), name)

    cond do
      File.dir?(Path.join(core, name)) -> Path.join(core, name)
      File.dir?(user) -> user
      File.dir?(learned) -> learned
      true -> nil
    end
  end
end
