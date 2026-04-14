defmodule Worth.Orchestration.Strategies.SwarmTest do
  use ExUnit.Case, async: true

  alias Worth.Orchestration.Strategies.Swarm

  describe "init/1" do
    test "initializes with defaults" do
      assert {:ok, state} = Swarm.init(workspace: "test")
      assert state.workspace == "test"
      assert state.max_iterations == 3
      assert state.particles == []
      assert state.personal_bests == %{}
      assert state.global_best == nil
    end

    test "accepts custom max_iterations" do
      assert {:ok, state} = Swarm.init(workspace: "test", max_iterations: 5)
      assert state.max_iterations == 5
    end
  end

  describe "prepare_run/2" do
    test "generates particles on first run" do
      {:ok, state} = Swarm.init(workspace: "test")
      opts = [system_prompt: "Base", prompt: "Solve this"]

      assert {:ok, prepared, new_state} = Swarm.prepare_run(opts, state)
      assert prepared[:system_prompt] =~ "Swarm Mode"
      assert length(new_state.particles) == 3
      assert new_state.current_particle == 0
      assert new_state.current_iteration == 1
    end

    test "uses existing particles for subsequent particles" do
      {:ok, state} = Swarm.init(workspace: "test")
      state = %{state | particles: ["a", "b", "c"], current_particle: 1, current_iteration: 1}
      opts = [system_prompt: "Base", prompt: "Solve this"]

      assert {:ok, prepared, ^state} = Swarm.prepare_run(opts, state)
      assert prepared[:prompt] == "b"
    end
  end

  describe "handle_result/3" do
    test "success advances to next particle when particles remain" do
      {:ok, state} = Swarm.init(workspace: "test")
      state = %{state | particles: ["a", "b", "c"], current_particle: 0, current_iteration: 1}

      result = %{text: "ok", cost: 0.1, tokens: 50, steps: 1}
      assert {:ok, new_state} = Swarm.handle_result({:ok, result}, [], state)
      assert new_state.current_particle == 1
      assert new_state.global_best == result
      assert new_state.global_best_cost == 0.1
    end

    test "success triggers rerun when all particles done and iterations remain" do
      {:ok, state} = Swarm.init(workspace: "test")

      state = %{
        state
        | particles: ["a", "b"],
          current_particle: 1,
          current_iteration: 1,
          max_iterations: 3,
          personal_bests: %{
            0 => %{prompt: "a", cost: 0.1, result: %{cost: 0.1}}
          },
          base_prompt: "base"
      }

      result = %{text: "ok", cost: 0.05, tokens: 50, steps: 1}
      opts = [prompt: "Solve this"]

      assert {:rerun, ^opts, new_state} = Swarm.handle_result({:ok, result}, opts, state)
      assert new_state.current_iteration == 2
      assert new_state.current_particle == 0
    end

    test "success returns :done when all iterations exhausted" do
      {:ok, state} = Swarm.init(workspace: "test")

      state = %{
        state
        | particles: ["a"],
          current_particle: 0,
          current_iteration: 3,
          max_iterations: 3
      }

      result = %{text: "final", cost: 0.01, tokens: 10, steps: 1}
      assert {:done, best, _new_state} = Swarm.handle_result({:ok, result}, [], state)
      assert best == result
    end

    test "error advances to next particle" do
      {:ok, state} = Swarm.init(workspace: "test")
      state = %{state | particles: ["a", "b"], current_particle: 0}

      assert {:ok, new_state} = Swarm.handle_result({:error, :timeout}, [], state)
      assert new_state.current_particle == 1
    end

    test "error returns :done with fallback when last particle" do
      {:ok, state} = Swarm.init(workspace: "test")
      state = %{state | particles: ["a"], current_particle: 0}

      assert {:done, best, _state} = Swarm.handle_result({:error, :timeout}, [], state)
      assert best.text == "No successful solution found"
    end
  end
end
