defmodule Worth.Orchestration.Strategies.Swarm do
  @moduledoc """
  Swarm intelligence strategy using Particle Swarm Optimization (PSO).

  Multiple agent runs with slightly different system prompts or tool
  permissions. Results update personal and global bests. Prompt
  variations converge toward the global best over iterations.
  """

  @behaviour AgentEx.Strategy

  defstruct [
    :workspace,
    :base_prompt,
    particles: [],
    personal_bests: %{},
    global_best: nil,
    global_best_cost: nil,
    inertia: 0.7,
    cognitive_weight: 1.5,
    social_weight: 1.5,
    max_iterations: 3,
    current_iteration: 0,
    current_particle: 0
  ]

  @impl true
  def id, do: :swarm

  @impl true
  def display_name, do: "Swarm (PSO)"

  @impl true
  def description, do: "Particle Swarm Optimization with concurrent prompt variation and convergence"

  @impl true
  def init(opts) do
    workspace = Keyword.get(opts, :workspace)
    max_iter = Keyword.get(opts, :max_iterations, 3)
    {:ok, %__MODULE__{workspace: workspace, max_iterations: max_iter}}
  end

  @impl true
  def prepare_run(opts, state) do
    case state.particles do
      [] ->
        particles = generate_particles(opts, 3)
        system_prompt = Keyword.get(opts, :system_prompt, "")
        overlay = build_swarm_overlay(state, "Initial swarm")

        prepared =
          opts
          |> Keyword.put(:system_prompt, system_prompt <> overlay)
          |> Keyword.put(:prompt, hd(particles))

        {:ok, prepared,
         %{state | particles: particles, base_prompt: opts[:prompt], current_particle: 0, current_iteration: 1}}

      _ when state.current_particle < length(state.particles) ->
        system_prompt = Keyword.get(opts, :system_prompt, "")
        overlay = build_swarm_overlay(state, "Iteration #{state.current_iteration}")

        prepared =
          opts
          |> Keyword.put(:system_prompt, system_prompt <> overlay)
          |> Keyword.put(:prompt, Enum.at(state.particles, state.current_particle))

        {:ok, prepared, state}

      _ ->
        {:ok, opts, state}
    end
  end

  @impl true
  def handle_result({:ok, result}, opts, state) do
    cost = result[:cost] || 0.0

    personal_bests =
      Map.put(state.personal_bests, state.current_particle, %{
        prompt: Enum.at(state.particles, state.current_particle),
        cost: cost,
        result: result
      })

    {global_best, global_best_cost} =
      if is_nil(state.global_best_cost) or cost < state.global_best_cost do
        {result, cost}
      else
        {state.global_best, state.global_best_cost}
      end

    next_particle = state.current_particle + 1

    cond do
      next_particle < length(state.particles) ->
        {:ok,
         %{
           state
           | current_particle: next_particle,
             personal_bests: personal_bests,
             global_best: global_best,
             global_best_cost: global_best_cost
         }}

      state.current_iteration < state.max_iterations ->
        new_particles = converge_particles(state.particles, personal_bests, global_best, state)

        {:rerun, opts,
         %{
           state
           | particles: new_particles,
             current_iteration: state.current_iteration + 1,
             current_particle: 0,
             personal_bests: personal_bests,
             global_best: global_best,
             global_best_cost: global_best_cost
         }}

      true ->
        {:done, global_best || result,
         %{
           state
           | personal_bests: personal_bests,
             global_best: global_best,
             global_best_cost: global_best_cost
         }}
    end
  end

  @impl true
  def handle_result({:error, _reason}, _opts, state) do
    next_particle = state.current_particle + 1

    if next_particle < length(state.particles) do
      {:ok, %{state | current_particle: next_particle}}
    else
      {:done, state.global_best || %{text: "No successful solution found", cost: 0, tokens: 0, steps: 0}, state}
    end
  end

  def handle_event(_event, state), do: {:ok, state}

  @impl true
  def telemetry_tags, do: [orchestration_type: :swarm]

  defp generate_particles(opts, count) do
    base = opts[:prompt] || ""

    variants = [
      "",
      "\n\n[Swarm particle: Focus on correctness over speed.]",
      "\n\n[Swarm particle: Explore creative approaches.]"
    ]

    for i <- 0..(count - 1) do
      base <> Enum.at(variants, i, "")
    end
  end

  defp converge_particles(old_particles, personal_bests, _global_best, state) do
    best_prompt =
      personal_bests
      |> Enum.sort_by(fn {_idx, data} -> data.cost end)
      |> List.first()
      |> case do
        {idx, _} -> Enum.at(old_particles, idx) || hd(old_particles)
        nil -> hd(old_particles)
      end

    base = state.base_prompt || ""

    for i <- 0..(length(old_particles) - 1) do
      if i == 0 do
        best_prompt
      else
        personal = Map.get(personal_bests, i)

        if personal do
          personal.prompt
        else
          "#{base}\n\n[Swarm converged particle: Follow the best-known approach.]"
        end
      end
    end
  end

  defp build_swarm_overlay(state, phase) do
    best_cost = if state.global_best_cost, do: "$#{Float.round(state.global_best_cost, 4)}", else: "N/A"

    "\n\n## Swarm Mode — #{phase}\n" <>
      "Iteration: #{state.current_iteration}/#{state.max_iterations}\n" <>
      "Particle: #{state.current_particle + 1}/#{length(state.particles)}\n" <>
      "Global best cost: #{best_cost}\n" <>
      "Explore the solution space efficiently. Learn from previous attempts."
  end
end
