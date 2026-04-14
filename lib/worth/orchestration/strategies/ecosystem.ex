defmodule Worth.Orchestration.Strategies.Ecosystem do
  @moduledoc """
  Ecosystem strategy with niche specialization and predator-prey error detection.

  Two agent roles: builder (produces output) and predator (critiques output
  for errors). Predator findings feed back into the next builder run's
  system prompt.
  """

  @behaviour AgentEx.Strategy

  defstruct [
    :workspace,
    :base_prompt,
    niches: [],
    carrying_capacity: 3,
    builder_results: [],
    predator_findings: [],
    role: :builder,
    iteration: 0,
    max_iterations: 2
  ]

  @impl true
  def id, do: :ecosystem

  @impl true
  def display_name, do: "Ecosystem"

  @impl true
  def description, do: "Builder-predator dynamics with niche specialization and error-hunting feedback"

  @impl true
  def init(opts) do
    workspace = Keyword.get(opts, :workspace)
    max_iter = Keyword.get(opts, :max_iterations, 2)
    {:ok, %__MODULE__{workspace: workspace, max_iterations: max_iter}}
  end

  @impl true
  def prepare_run(opts, state) do
    system_prompt = Keyword.get(opts, :system_prompt, "")

    case state.role do
      :builder ->
        feedback = build_predator_feedback(state.predator_findings)
        overlay = build_builder_overlay(state) <> feedback

        prepared =
          opts
          |> Keyword.put(:system_prompt, system_prompt <> overlay)
          |> Keyword.put(:mode, :agentic)

        {:ok, prepared, state}

      :predator ->
        builder_text =
          case List.last(state.builder_results) do
            {:ok, result} -> result[:text] || ""
            _ -> ""
          end

        overlay =
          build_predator_overlay(state, builder_text)

        prepared =
          opts
          |> Keyword.put(:system_prompt, system_prompt <> overlay)
          |> Keyword.put(:prompt, "Review the following output for errors, bugs, or issues:\n\n#{builder_text}")
          |> Keyword.put(:mode, :conversational)

        {:ok, prepared, state}
    end
  end

  @impl true
  def handle_result({:ok, result}, opts, state) do
    case state.role do
      :builder ->
        new_builder = [{:ok, result} | state.builder_results]

        if state.iteration < state.max_iterations do
          {:rerun, opts,
           %{
             state
             | builder_results: new_builder,
               role: :predator,
               iteration: state.iteration + 1
           }}
        else
          {:done, result, %{state | builder_results: new_builder}}
        end

      :predator ->
        findings = extract_findings(result[:text] || "")
        new_findings = findings ++ state.predator_findings |> Enum.take(20)

        {:rerun, opts,
         %{
           state
           | predator_findings: new_findings,
             role: :builder
         }}
    end
  end

  @impl true
  def handle_result({:error, reason}, _opts, state) do
    case state.role do
      :builder ->
        new_builder = [{:error, reason} | state.builder_results]
        {:done, %{text: "Builder failed: #{inspect(reason)}", cost: 0, tokens: 0, steps: 0}, %{state | builder_results: new_builder}}

      :predator ->
        {:rerun, [], %{state | role: :builder}}
    end
  end

  def handle_event(_event, state), do: {:ok, state}

  @impl true
  def telemetry_tags, do: [orchestration_type: :ecosystem]

  defp build_builder_overlay(state) do
    "\n\n## Ecosystem Mode — Builder\n" <>
      "Iteration: #{state.iteration}/#{state.max_iterations}\n" <>
      "You are the builder agent. Produce high-quality output.\n" <>
      "A predator agent will review your work for errors.\n" <>
      "Learn from previous feedback to improve."
  end

  defp build_predator_overlay(_state, builder_text) do
    text_preview = String.slice(builder_text, 0, 500)

    "\n\n## Ecosystem Mode — Predator\n" <>
      "You are the predator (error-hunting) agent.\n" <>
      "Review the builder's output and identify:\n" <>
      "- Logic errors\n" <>
      "- Missing edge cases\n" <>
      "- Potential bugs\n" <>
      "- Security issues\n" <>
      "- Performance concerns\n\n" <>
      "Builder output preview:\n#{text_preview}"
  end

  defp build_predator_feedback([]), do: ""

  defp build_predator_feedback(findings) do
    items = Enum.map_join(findings, "\n- ", & &1)

    "\n\n## Previous Predator Findings\nAddress these issues from the previous review:\n- #{items}"
  end

  defp extract_findings(text) do
    text
    |> String.split("\n")
    |> Enum.filter(&String.match?(&1, ~r/^\s*[-•]\s/i))
    |> Enum.take(10)
    |> Enum.map(&String.trim/1)
  end
end
