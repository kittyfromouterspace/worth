defmodule Worth.Orchestration.Strategies.Evolutionary do
  @moduledoc """
  Evolutionary strategy with population-based solution exploration.

  Maintains a population of solution candidates. Uses `{:rerun, opts, state}`
  to run multiple candidates per generation, selecting top performers
  and mutating for subsequent generations.
  """

  @behaviour AgentEx.Strategy

  defstruct [
    :workspace,
    :base_prompt,
    population_size: 3,
    generation: 0,
    max_generations: 2,
    population: [],
    current_candidate: 0,
    results: []
  ]

  @impl true
  def id, do: :evolutionary

  @impl true
  def display_name, do: "Evolutionary"

  @impl true
  def description, do: "Population-based solution exploration with fitness selection and mutation"

  @impl true
  def init(opts) do
    workspace = Keyword.get(opts, :workspace)
    pop_size = Keyword.get(opts, :population_size, 3)
    max_gen = Keyword.get(opts, :max_generations, 2)
    {:ok, %__MODULE__{workspace: workspace, population_size: pop_size, max_generations: max_gen}}
  end

  @impl true
  def prepare_run(opts, state) do
    case state.population do
      [] ->
        seeded = seed_population(opts, state.population_size)
        system_prompt = Keyword.get(opts, :system_prompt, "")
        overlay = build_evolutionary_overlay(state, "Initial population")

        prepared =
          opts
          |> Keyword.put(:system_prompt, system_prompt <> overlay)
          |> Keyword.put(:prompt, hd(seeded))

        {:ok, prepared, %{state | population: seeded, base_prompt: opts[:prompt], current_candidate: 0}}

      candidates when state.current_candidate < length(candidates) ->
        system_prompt = Keyword.get(opts, :system_prompt, "")
        overlay = build_evolutionary_overlay(state, "Generation #{state.generation}")

        prepared =
          opts
          |> Keyword.put(:system_prompt, system_prompt <> overlay)
          |> Keyword.put(:prompt, Enum.at(candidates, state.current_candidate))

        {:ok, prepared, state}

      _ ->
        {:ok, opts, state}
    end
  end

  @impl true
  def handle_result({:ok, result}, opts, state) do
    new_results = [{state.current_candidate, {:ok, result}} | state.results]
    next_candidate = state.current_candidate + 1

    cond do
      next_candidate < length(state.population) ->
        {:ok, %{state | current_candidate: next_candidate, results: new_results}}

      state.generation < state.max_generations ->
        evolved = evolve_population(new_results, state.population, opts)
        {:rerun, opts, %{state | population: evolved, generation: state.generation + 1, current_candidate: 0, results: []}}

      true ->
        best = select_best(new_results)
        {:done, best, %{state | results: new_results}}
    end
  end

  @impl true
  def handle_result({:error, reason}, _opts, state) do
    new_results = [{state.current_candidate, {:error, reason}} | state.results]
    next_candidate = state.current_candidate + 1

    if next_candidate < length(state.population) do
      {:ok, %{state | current_candidate: next_candidate, results: new_results}}
    else
      best = select_best(new_results)
      {:done, best, %{state | results: new_results}}
    end
  end

  def handle_event(_event, state), do: {:ok, state}

  @impl true
  def telemetry_tags, do: [orchestration_type: :evolutionary]

  defp seed_population(opts, size) do
    base = opts[:prompt] || ""

    for i <- 0..(size - 1) do
      case i do
        0 -> base
        1 -> "#{base}\n\n[Evolutionary variant: Focus on simplicity and minimal changes.]"
        _ -> "#{base}\n\n[Evolutionary variant: Explore an alternative approach.]"
      end
    end
  end

  defp evolve_population(results, old_population, opts) do
    base = opts[:prompt] || ""

    successes =
      results
      |> Enum.filter(fn {_idx, r} -> match?({:ok, _}, r) end)
      |> Enum.sort_by(fn {_idx, {:ok, r}} -> r[:cost] || 0 end)

    case successes do
      [{best_idx, {:ok, best_result}} | _] ->
        best_prompt = Enum.at(seed_population(opts, 1), best_idx) || base

        for i <- 0..(length(old_population) - 1) do
          case i do
            0 -> best_prompt
            1 -> "#{base}\n\n[Evolutionary mutation: Refine the best solution further. Previous cost: #{best_result[:cost]}]"
            _ -> "#{base}\n\n[Evolutionary mutation: Try a hybrid approach.]"
          end
        end

      _ ->
        seed_population(opts, length(old_population))
    end
  end

  defp select_best(results) do
    results
    |> Enum.filter(fn {_idx, r} -> match?({:ok, _}, r) end)
    |> Enum.sort_by(fn {_idx, {:ok, r}} -> r[:cost] || 0 end)
    |> List.first()
    |> case do
      nil -> %{text: "No successful solution found", cost: 0, tokens: 0, steps: 0}
      {_idx, {:ok, result}} -> result
    end
  end

  defp build_evolutionary_overlay(state, phase) do
    "\n\n## Evolutionary Mode — #{phase}\n" <>
      "Generation: #{state.generation}/#{state.max_generations}\n" <>
      "Population size: #{state.population_size}\n" <>
      "Candidate: #{state.current_candidate + 1}/#{state.population_size}\n" <>
      "Focus on producing a correct, efficient solution. Multiple variants are being explored."
  end
end
