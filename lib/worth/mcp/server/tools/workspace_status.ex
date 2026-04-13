defmodule Worth.Mcp.Server.Tools.WorkspaceStatus do
  @moduledoc "Get current workspace status including mode, cost, and active tools"
  use Hermes.Server.Component, type: :tool

  schema do
  end

  @impl true
  def execute(_params, frame) do
    workspace = Worth.Config.get(:current_workspace, "personal")
    status = Worth.Brain.get_status(workspace)

    text =
      "Mode: #{status.mode}\n" <>
        "Profile: #{status.profile}\n" <>
        "Workspace: #{status.workspace}\n" <>
        "Cost: $#{Float.round(status.cost, 3)}\n" <>
        "Session: #{status.session_id}\n" <>
        "Status: #{status.status}"

    {:reply, text, frame}
  catch
    :exit, reason ->
      {:error, "Brain unavailable: #{inspect(reason)}", frame}
  end
end
