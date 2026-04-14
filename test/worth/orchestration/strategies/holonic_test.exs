defmodule Worth.Orchestration.Strategies.HolonicTest do
  use ExUnit.Case, async: true

  alias Worth.Orchestration.Strategies.Holonic

  describe "init/1" do
    test "initializes with default capacity" do
      assert {:ok, state} = Holonic.init(workspace: "test")
      assert state.workspace == "test"
      assert state.holon_capacity == 3
      assert state.active_holons == 0
    end

    test "accepts custom holon_capacity" do
      assert {:ok, state} = Holonic.init(workspace: "test", holon_capacity: 5)
      assert state.holon_capacity == 5
    end
  end

  describe "prepare_run/2" do
    test "appends holonic overlay to system prompt" do
      {:ok, state} = Holonic.init(workspace: "test")
      opts = [system_prompt: "Base prompt", prompt: "Do something"]

      assert {:ok, prepared, ^state} = Holonic.prepare_run(opts, state)
      assert prepared[:system_prompt] =~ "Holonic Decomposition"
      assert prepared[:system_prompt] =~ "Base prompt"
    end
  end

  describe "handle_result/3" do
    test "success returns {:done, result, state}" do
      {:ok, state} = Holonic.init(workspace: "test")
      result = %{text: "done", cost: 0.1, tokens: 100, steps: 2}

      assert {:done, ^result, new_state} = Holonic.handle_result({:ok, result}, [], state)
      assert is_list(new_state.holon_history)
    end

    test "error returns {:done, {:error, reason}, state}" do
      {:ok, state} = Holonic.init(workspace: "test")
      state = %{state | active_holons: 2}

      assert {:done, {:error, :timeout}, new_state} =
               Holonic.handle_result({:error, :timeout}, [], state)

      assert new_state.active_holons == 1
    end

    test "error with zero active_holons does not go negative" do
      {:ok, state} = Holonic.init(workspace: "test")
      assert state.active_holons == 0

      assert {:done, {:error, :fail}, new_state} =
               Holonic.handle_result({:error, :fail}, [], state)

      assert new_state.active_holons == 0
    end
  end
end
