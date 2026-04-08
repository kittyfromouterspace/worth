defmodule Worth.UITest do
  use ExUnit.Case, async: true

  alias Worth.UI.Sidebar
  alias TermUI.Component

  defp get_text(render_node), do: render_node.content

  describe "Sidebar" do
    test "workspace_tab/1 returns workspace header and list" do
      result = Sidebar.workspace_tab(%{})
      assert get_text(Enum.at(result, 0)) == "Workspace"
    end

    test "tools_tab/1 returns tools header and list" do
      result = Sidebar.tools_tab(%{})
      assert get_text(Enum.at(result, 0)) == "Tools"
    end

    test "skills_tab/1 returns skills header and list" do
      result = Sidebar.skills_tab(%{})
      assert get_text(Enum.at(result, 0)) == "Skills"
    end

    test "status_tab/1 returns status information" do
      state = %{
        models: %{},
        mode: :code,
        cost: 0.0,
        turn: 0
      }

      result = Sidebar.status_tab(state)
      assert get_text(Enum.at(result, 0)) == "Status"
      assert get_text(Enum.at(result, 1)) == "  Mode:  code"
    end

    test "logs_tab/1 returns logs header when no logs" do
      result = Sidebar.logs_tab(%{})
      assert get_text(Enum.at(result, 0)) == "Logs"
      assert get_text(Enum.at(result, 1)) == "  (no log entries)"
    end
  end
end
