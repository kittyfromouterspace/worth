defmodule Worth.Mcp.Server.Tools.WorkspaceStatus do
  @moduledoc "Get current workspace status including mode, cost, and active tools"
  use Hermes.Server.Component, type: :tool

  schema do
  end

  @impl true
  def execute(_params, frame) do
    workspace = Application.get_env(:worth, :current_workspace, "personal")
    status = Worth.Brain.get_status(workspace)

    text =
      "Mode: #{status.mode}\n" <>
        "Profile: #{status.profile}\n" <>
        "Workspace: #{status.workspace}\n" <>
        "Cost: $#{Float.round(status.cost, 3)}\n" <>
        "Session: #{status.session_id}\n" <>
        "Status: #{status.status}"

    {:reply, text, frame}
  rescue
    e -> {:error, Exception.message(e), frame}
  end
end
