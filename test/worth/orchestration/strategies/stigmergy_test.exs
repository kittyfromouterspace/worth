defmodule Worth.Orchestration.Strategies.StigmergyTest do
  use ExUnit.Case, async: true

  alias Worth.Orchestration.Strategies.Stigmergy

  describe "init/1" do
    test "initializes with defaults" do
      assert {:ok, state} = Stigmergy.init(workspace: "test")
      assert state.workspace == "test"
      assert state.active_trails == []
      assert state.deposited_pheromones == []
      assert state.max_trails == 10
    end
  end

  describe "prepare_run/2" do
    test "injects pheromone overlay into system prompt" do
      {:ok, state} = Stigmergy.init(workspace: nil)
      opts = [system_prompt: "Base prompt", prompt: "Do task"]

      assert {:ok, prepared, _new_state} = Stigmergy.prepare_run(opts, state)
      # With nil workspace, no pheromones are fetched, so overlay is empty
      assert prepared[:system_prompt] == "Base prompt"
    end
  end

  describe "handle_result/3" do
    test "success returns {:done, result, state}" do
      {:ok, state} = Stigmergy.init(workspace: nil)
      result = %{text: "done", cost: 0.1, tokens: 100, steps: 2}

      assert {:done, ^result, new_state} = Stigmergy.handle_result({:ok, result}, [], state)
      assert is_list(new_state.deposited_pheromones)
    end

    test "error returns {:done, {:error, reason}, state}" do
      {:ok, state} = Stigmergy.init(workspace: nil)

      assert {:done, {:error, :timeout}, ^state} =
               Stigmergy.handle_result({:error, :timeout}, [], state)
    end
  end
end
