defmodule WorthWeb.CommandHandler do
  @moduledoc """
  Routes slash commands to namespace-specific handler modules.
  """

  alias WorthWeb.Commands.McpCommands
  alias WorthWeb.Commands.MemoryCommands
  alias WorthWeb.Commands.ModelCommands
  alias WorthWeb.Commands.ProviderCommands
  alias WorthWeb.Commands.SettingsCommands
  alias WorthWeb.Commands.SkillCommands
  alias WorthWeb.Commands.SystemCommands
  alias WorthWeb.Commands.WorkspaceCommands

  def handle(cmd, _text, socket) do
    dispatch(cmd, socket)
  end

  # System commands (simple atoms)
  defp dispatch(:quit, socket), do: SystemCommands.handle(:quit, socket)
  defp dispatch(:clear, socket), do: SystemCommands.handle(:clear, socket)
  defp dispatch(:cost, socket), do: SystemCommands.handle(:cost, socket)
  defp dispatch(:help, socket), do: SystemCommands.handle(:help, socket)
  defp dispatch(:usage, socket), do: ProviderCommands.handle(:usage, socket)
  defp dispatch(:settings, socket), do: SettingsCommands.handle(:settings, socket)

  # Namespaced commands
  defp dispatch({:mode, _} = cmd, socket), do: SystemCommands.handle(cmd, socket)
  defp dispatch({:status, _} = cmd, socket), do: SystemCommands.handle(cmd, socket)
  defp dispatch({:strategy, _} = cmd, socket), do: SystemCommands.handle(cmd, socket)
  defp dispatch({:unknown, _} = cmd, socket), do: SystemCommands.handle(cmd, socket)

  defp dispatch({:model, _} = cmd, socket), do: ModelCommands.handle(cmd, socket)
  defp dispatch({:memory, _} = cmd, socket), do: MemoryCommands.handle(cmd, socket)
  defp dispatch({:skill, _} = cmd, socket), do: SkillCommands.handle(cmd, socket)
  defp dispatch({:mcp, _} = cmd, socket), do: McpCommands.handle(cmd, socket)

  defp dispatch({:provider, _} = cmd, socket), do: ProviderCommands.handle(cmd, socket)
  defp dispatch({:catalog, _} = cmd, socket), do: ProviderCommands.handle(cmd, socket)
  defp dispatch({:usage, _} = cmd, socket), do: ProviderCommands.handle(cmd, socket)

  defp dispatch({:workspace, _} = cmd, socket), do: WorkspaceCommands.handle(cmd, socket)
  defp dispatch({:agent, _} = cmd, socket), do: WorkspaceCommands.handle(cmd, socket)
  defp dispatch({:session, _} = cmd, socket), do: WorkspaceCommands.handle(cmd, socket)
  defp dispatch({:kit, _} = cmd, socket), do: WorkspaceCommands.handle(cmd, socket)
  defp dispatch({:setup, _} = cmd, socket), do: WorkspaceCommands.handle(cmd, socket)
end
