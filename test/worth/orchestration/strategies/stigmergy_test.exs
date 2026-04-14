defmodule Worth.Orchestration.Strategies.StigmergyTest do
  use ExUnit.Case, async: true

  alias Worth.Orchestration.Strategies.Stigmergy

  describe "init/1" do
    test "initializes with workspace from opts" do
      assert {:ok, %Stigmergy{workspace: "test-ws"}} = Stigmergy.init(workspace: "test-ws")
    end

    test "initializes with nil workspace when not provided" do
      assert {:ok, %Stigmergy{workspace: nil}} = Stigmergy.init([])
    end

    test "sets default values for trails and decay" do
      {:ok, state} = Stigmergy.init(workspace: "ws")
      assert state.active_trails == []
      assert state.deposited_pheromones == []
      assert state.trail_decay == 0.95
      assert state.max_trails == 10
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

    test "stores pheromone context in strategy_opts" do
      {:ok, state} = Stigmergy.init([])
      opts = [system_prompt: "base"]

      {:ok, prepared, _state} = Stigmergy.prepare_run(opts, state)
      strategy_opts = Keyword.get(prepared, :strategy_opts, [])
      assert Keyword.get(strategy_opts, :pheromone_context) == []
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

    test "accumulates deposited pheromones up to 50" do
      {:ok, state} = Stigmergy.init([])
      state = %{state | deposited_pheromones: Enum.map(1..49, &%{id: &1})}
      result = %{text: "new"}

      {:done, _result, new_state} = Stigmergy.handle_result({:ok, result}, [], state)
      assert length(new_state.deposited_pheromones) == 50
    end

    test "success with nil workspace deposits placeholder pheromone" do
      {:ok, state} = Stigmergy.init([])
      result = %{text: "done"}

      {:done, ^result, new_state} = Stigmergy.handle_result({:ok, result}, [], state)
      [pheromone | _] = new_state.deposited_pheromones
      assert pheromone == %{content: "", metadata: %{}}
    end
  end

  describe "build_pheromone_overlay/1" do
    test "returns empty string for empty list" do
      assert Stigmergy.build_pheromone_overlay([]) == ""
    end

    test "handles struct-style results with atom keys" do
      pheromones = [
        %{content: "using read_file", metadata: %{signal: :intention}},
        %{content: "task done", metadata: %{signal: :completion}}
      ]

      overlay = Stigmergy.build_pheromone_overlay(pheromones)
      assert overlay =~ "Active Pheromone Trails"
      assert overlay =~ "intention: using read_file"
      assert overlay =~ "completion: task done"
    end

    test "handles map-style results with string keys" do
      pheromones = [
        %{"content" => "string content", "metadata" => %{"signal" => "intention"}}
      ]

      overlay = Stigmergy.build_pheromone_overlay(pheromones)
      assert overlay =~ "intention: string content"
    end

    test "handles missing metadata gracefully" do
      pheromones = [%{content: "no meta"}]

      overlay = Stigmergy.build_pheromone_overlay(pheromones)
      assert overlay =~ "unknown: no meta"
    end

    test "handles missing content gracefully" do
      pheromones = [%{metadata: %{signal: :failure}}]

      overlay = Stigmergy.build_pheromone_overlay(pheromones)
      assert overlay =~ "failure: "
    end
  end

  describe "id/0, display_name/0, description/0" do
    test "returns expected identifiers" do
      assert Stigmergy.id() == :stigmergy
      assert Stigmergy.display_name() == "Stigmergy (Ant Colony)"
      assert is_binary(Stigmergy.description())
    end
  end

  describe "telemetry_tags/0" do
    test "returns stigmergy tag" do
      assert Stigmergy.telemetry_tags() == [orchestration_type: :stigmergy]
    end
  end
end
