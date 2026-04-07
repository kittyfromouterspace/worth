defmodule Worth.Mcp.Server do
  use Hermes.Server,
    name: "worth",
    version: "0.1.0",
    capabilities: [:tools, {:resources, subscribe?: false}]

  component(Worth.Mcp.Server.Tools.Chat)
  component(Worth.Mcp.Server.Tools.MemoryQuery)
  component(Worth.Mcp.Server.Tools.MemoryWrite)
  component(Worth.Mcp.Server.Tools.SkillList)
  component(Worth.Mcp.Server.Tools.SkillRead)
  component(Worth.Mcp.Server.Tools.WorkspaceStatus)

  @impl true
  def init(_client_info, frame) do
    {:ok, frame}
  end

  @impl true
  def handle_info(:check_status, frame) do
    {:noreply, frame}
  end
end
