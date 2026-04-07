defmodule Worth.UI.ThemeTest do
  use ExUnit.Case

  describe "current/0" do
    test "returns a map with required keys" do
      theme = Worth.UI.Theme.current()
      assert Map.has_key?(theme, :header)
      assert Map.has_key?(theme, :user_input)
      assert Map.has_key?(theme, :error)
    end
  end

  describe "style_for/1" do
    test "returns a style for known element" do
      style = Worth.UI.Theme.style_for(:header)
      assert style != nil
    end

    test "returns default style for unknown element" do
      style = Worth.UI.Theme.style_for(:nonexistent)
      assert style != nil
    end
  end

  describe "status_indicator/1" do
    test "returns idle indicator" do
      assert Worth.UI.Theme.status_indicator(:idle) == " "
    end

    test "returns running indicator" do
      assert Worth.UI.Theme.status_indicator(:running) == "*"
    end

    test "returns error indicator" do
      assert Worth.UI.Theme.status_indicator(:error) == "!"
    end
  end
end
