defmodule Worth.BrainTest do
  use ExUnit.Case

  @workspace "personal"

  test "brain starts and responds to get_status" do
    status = Worth.Brain.get_status(@workspace)
    assert Map.has_key?(status, :status)
    assert Map.has_key?(status, :cost)
    assert Map.has_key?(status, :workspace)
    assert Map.has_key?(status, :mode)
  end

  test "switch_mode changes the mode" do
    :ok = Worth.Brain.switch_mode(@workspace, :research)
    status = Worth.Brain.get_status(@workspace)
    assert status.mode == :research

    Worth.Brain.switch_mode(@workspace, :code)
  end

  test "switch_strategy to a registered strategy succeeds" do
    result = Worth.Brain.switch_strategy(@workspace, :default)
    assert result == :ok

    status = Worth.Brain.get_status(@workspace)
    assert status.strategy == :default
  end

  test "switch_strategy to an unknown strategy returns error" do
    result = Worth.Brain.switch_strategy(@workspace, :nonexistent_strategy_xyz)
    assert result == {:error, :unknown_strategy}
  end

  test "get_status includes strategy field" do
    status = Worth.Brain.get_status(@workspace)
    assert Map.has_key?(status, :strategy)
  end

  test "list_strategies returns a list" do
    strategies = Worth.Brain.list_strategies()
    assert is_list(strategies) or is_map(strategies)
  end
end
