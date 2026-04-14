defmodule Worth.Orchestration.Strategies.StigmergyTest do
  use ExUnit.Case, async: true

  alias Worth.Orchestration.Strategies.Stigmergy

  describe "init/1" do
    test "initializes with workspace from opts" do
      assert {:ok, state} = Stigmergy.init(workspace: "test")
      assert state.workspace == "test"
      assert state.active_trails == []
      assert state.deposited_pheromones == []
      assert state.trail_decay == 0.95
      assert state.max_trails == 10
    end

    test "initializes with nil workspace when not provided" do
      assert {:ok, state} = Stigmergy.init([])
      assert state.workspace == nil
    end
  end

  describe "prepare_run/2" do
    test "preserves system prompt when no pheromones (nil workspace)" do
      {:ok, state} = Stigmergy.init([])
      opts = [system_prompt: "You are helpful.", strategy_opts: []]

      assert {:ok, prepared, new_state} = Stigmergy.prepare_run(opts, state)
      assert Keyword.get(prepared, :system_prompt) == "You are helpful."
      assert new_state.active_trails == []
    end

    test "uses empty string as default system prompt" do
      {:ok, state} = Stigmergy.init([])

      assert {:ok, prepared, _state} = Stigmergy.prepare_run([], state)
      assert Keyword.get(prepared, :system_prompt) == ""
    end
  end

  describe "handle_result/3" do
    test "returns {:done, result, state} on success with nil workspace" do
      {:ok, state} = Stigmergy.init([])
      result = %{text: "hello"}

      assert {:done, ^result, new_state} = Stigmergy.handle_result({:ok, result}, [], state)
      assert length(new_state.deposited_pheromones) == 1
    end

    test "returns {:done, {:error, reason}, state} on error" do
      {:ok, state} = Stigmergy.init([])

      assert {:done, {:error, :timeout}, ^state} =
               Stigmergy.handle_result({:error, :timeout}, [], state)
    end

    test "success with nil workspace deposits placeholder pheromone" do
      {:ok, state} = Stigmergy.init([])
      result = %{text: "done"}

      {:done, ^result, new_state} = Stigmergy.handle_result({:ok, result}, [], state)
      [pheromone | _] = new_state.deposited_pheromones
      assert pheromone == %{content: "", metadata: %{}}
    end
  end
end
