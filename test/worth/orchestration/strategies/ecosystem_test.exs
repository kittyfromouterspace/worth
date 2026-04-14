defmodule Worth.Orchestration.Strategies.EcosystemTest do
  use ExUnit.Case, async: true

  alias Worth.Orchestration.Strategies.Ecosystem

  describe "init/1" do
    test "initializes with defaults" do
      assert {:ok, state} = Ecosystem.init(workspace: "test")
      assert state.workspace == "test"
      assert state.max_iterations == 2
      assert state.role == :builder
      assert state.iteration == 0
    end

    test "accepts custom max_iterations" do
      assert {:ok, state} = Ecosystem.init(workspace: "test", max_iterations: 4)
      assert state.max_iterations == 4
    end
  end

  describe "prepare_run/2" do
    test "builder role appends builder overlay" do
      {:ok, state} = Ecosystem.init(workspace: "test")
      opts = [system_prompt: "Base", prompt: "Build this"]

      assert {:ok, prepared, ^state} = Ecosystem.prepare_run(opts, state)
      assert prepared[:system_prompt] =~ "Builder"
      assert prepared[:mode] == :agentic
    end

    test "predator role appends predator overlay" do
      {:ok, state} = Ecosystem.init(workspace: "test")
      state = %{state | role: :predator, builder_results: [{:ok, %{text: "some output"}}]}
      opts = [system_prompt: "Base", prompt: "Review"]

      assert {:ok, prepared, ^state} = Ecosystem.prepare_run(opts, state)
      assert prepared[:system_prompt] =~ "Predator"
      assert prepared[:mode] == :conversational
    end
  end

  describe "handle_result/3" do
    test "builder success switches to predator when iterations remain" do
      {:ok, state} = Ecosystem.init(workspace: "test")
      result = %{text: "built", cost: 0.1, tokens: 50, steps: 1}
      opts = [prompt: "Build"]

      assert {:rerun, ^opts, new_state} = Ecosystem.handle_result({:ok, result}, opts, state)
      assert new_state.role == :predator
      assert new_state.iteration == 1
    end

    test "builder success returns :done when max iterations reached" do
      {:ok, state} = Ecosystem.init(workspace: "test")
      state = %{state | iteration: 2, max_iterations: 2}
      result = %{text: "final", cost: 0.1, tokens: 50, steps: 1}

      assert {:done, ^result, _new_state} = Ecosystem.handle_result({:ok, result}, [], state)
    end

    test "predator success switches back to builder" do
      {:ok, state} = Ecosystem.init(workspace: "test")
      state = %{state | role: :predator}
      result = %{text: "- found bug\n- missing edge case", cost: 0.05, tokens: 20, steps: 1}
      opts = [prompt: "Review"]

      assert {:rerun, ^opts, new_state} = Ecosystem.handle_result({:ok, result}, opts, state)
      assert new_state.role == :builder
      assert length(new_state.predator_findings) > 0
    end

    test "builder error returns :done with failure message" do
      {:ok, state} = Ecosystem.init(workspace: "test")

      assert {:done, result, _state} = Ecosystem.handle_result({:error, :timeout}, [], state)
      assert result.text =~ "Builder failed"
    end

    test "predator error switches back to builder" do
      {:ok, state} = Ecosystem.init(workspace: "test")
      state = %{state | role: :predator}

      assert {:rerun, [], new_state} = Ecosystem.handle_result({:error, :timeout}, [], state)
      assert new_state.role == :builder
    end
  end
end
