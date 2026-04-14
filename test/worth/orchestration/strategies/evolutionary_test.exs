defmodule Worth.Orchestration.Strategies.EvolutionaryTest do
  use ExUnit.Case, async: true

  alias Worth.Orchestration.Strategies.Evolutionary

  describe "init/1" do
    test "initializes with defaults" do
      assert {:ok, state} = Evolutionary.init(workspace: "test")
      assert state.workspace == "test"
      assert state.population_size == 3
      assert state.max_generations == 2
      assert state.generation == 0
      assert state.population == []
    end

    test "accepts custom population_size and max_generations" do
      assert {:ok, state} =
               Evolutionary.init(workspace: "test", population_size: 5, max_generations: 4)

      assert state.population_size == 5
      assert state.max_generations == 4
    end
  end

  describe "prepare_run/2" do
    test "seeds population on first run" do
      {:ok, state} = Evolutionary.init(workspace: "test")
      opts = [system_prompt: "Base", prompt: "Solve this"]

      assert {:ok, prepared, new_state} = Evolutionary.prepare_run(opts, state)
      assert prepared[:system_prompt] =~ "Evolutionary Mode"
      assert length(new_state.population) == 3
      assert new_state.current_candidate == 0
      assert new_state.base_prompt == "Solve this"
    end

    test "uses existing population for subsequent candidates" do
      {:ok, state} = Evolutionary.init(workspace: "test")
      state = %{state | population: ["a", "b", "c"], current_candidate: 1}
      opts = [system_prompt: "Base", prompt: "Solve this"]

      assert {:ok, prepared, ^state} = Evolutionary.prepare_run(opts, state)
      assert prepared[:prompt] == "b"
    end
  end

  describe "handle_result/3" do
    test "success advances to next candidate when population remains" do
      {:ok, state} = Evolutionary.init(workspace: "test")
      state = %{state | population: ["a", "b", "c"], current_candidate: 0, results: []}

      result = %{text: "ok", cost: 0.1, tokens: 50, steps: 1}
      assert {:ok, new_state} = Evolutionary.handle_result({:ok, result}, [], state)
      assert new_state.current_candidate == 1
    end

    test "success triggers evolution when all candidates done and generations remain" do
      {:ok, state} = Evolutionary.init(workspace: "test")

      state = %{
        state
        | population: ["a", "b", "c"],
          current_candidate: 2,
          generation: 0,
          max_generations: 2,
          results: [
            {0, {:ok, %{cost: 0.1}}},
            {1, {:ok, %{cost: 0.2}}}
          ]
      }

      result = %{text: "ok", cost: 0.05, tokens: 50, steps: 1}
      opts = [prompt: "Solve this"]

      assert {:rerun, ^opts, new_state} = Evolutionary.handle_result({:ok, result}, opts, state)
      assert new_state.generation == 1
      assert new_state.current_candidate == 0
      assert new_state.results == []
    end

    test "success returns :done with best result when all generations exhausted" do
      {:ok, state} = Evolutionary.init(workspace: "test")

      state = %{
        state
        | population: ["a"],
          current_candidate: 0,
          generation: 2,
          max_generations: 2,
          results: []
      }

      result = %{text: "final", cost: 0.01, tokens: 10, steps: 1}
      assert {:done, best, _new_state} = Evolutionary.handle_result({:ok, result}, [], state)
      assert best == result
    end

    test "error advances to next candidate" do
      {:ok, state} = Evolutionary.init(workspace: "test")
      state = %{state | population: ["a", "b"], current_candidate: 0, results: []}

      assert {:ok, new_state} = Evolutionary.handle_result({:error, :timeout}, [], state)
      assert new_state.current_candidate == 1
    end

    test "error returns :done with fallback when last candidate" do
      {:ok, state} = Evolutionary.init(workspace: "test")
      state = %{state | population: ["a"], current_candidate: 0, results: []}

      assert {:done, best, _state} = Evolutionary.handle_result({:error, :timeout}, [], state)
      assert best.text == "No successful solution found"
    end
  end
end
