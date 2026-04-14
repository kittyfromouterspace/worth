defmodule Worth.UI.CommandsTest do
  use ExUnit.Case, async: true

  alias Worth.UI.Commands

  describe "parse/1 strategy commands" do
    test "parses /strategy as list" do
      assert Commands.parse("/strategy") == {:command, {:strategy, :list}}
    end

    test "parses /strategy <name> as switch" do
      assert Commands.parse("/strategy foo") == {:command, {:strategy, {:switch, "foo"}}}
    end

    test "parses /strategy with known strategy name" do
      assert Commands.parse("/strategy default") == {:command, {:strategy, {:switch, "default"}}}
    end
  end
end
