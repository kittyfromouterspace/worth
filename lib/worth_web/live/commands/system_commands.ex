defmodule WorthWeb.Commands.SystemCommands do
  @moduledoc false
  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [stream: 4]
  import WorthWeb.Commands.Helpers

  def handle(:quit, socket) do
    append_system(socket, "Use Ctrl+C in the terminal to stop Worth.")
  end

  def handle(:clear, socket) do
    Worth.Metrics.reset()

    socket
    |> stream(:messages, [], reset: true)
    |> assign(streaming_text: "", cost: 0.0, turn: 0)
  end

  def handle(:cost, socket) do
    append_system(socket, "Session cost: $#{Float.round(socket.assigns.cost, 4)} | Turns: #{socket.assigns.turn}")
  end

  def handle(:help, socket) do
    append_system(socket, Worth.UI.Commands.help_text())
  end

  def handle({:mode, mode}, socket) do
    Worth.Brain.switch_mode(socket.assigns.workspace, mode)
    append_system(assign(socket, mode: mode), "Switched to #{mode} mode")
  end

  def handle({:strategy, :list}, socket) do
    strategies =
      AgentEx.Strategy.Registry.all()
      |> Enum.map(fn {id, mod} -> "  #{id} — #{mod.display_name()}" end)
      |> Enum.join("\n")

    append_system(socket, "Available strategies:\n#{strategies}")
  end

  def handle({:strategy, {:switch, name}}, socket) do
    strategy_id = String.to_atom(name)

    case Worth.Brain.switch_strategy(socket.assigns.workspace, strategy_id) do
      :ok ->
        append_system(assign(socket, strategy: strategy_id), "Switched to #{name} strategy")

      {:error, :unknown_strategy} ->
        append_system(socket, "Unknown strategy: #{name}. Type /strategy to list available strategies.")

      {:error, reason} ->
        append_system(socket, "Failed to switch strategy: #{inspect(reason)}")
    end
  end

  def handle({:status, _}, socket) do
    status = Worth.Brain.get_status(socket.assigns.workspace)

    msg =
      "Mode: #{status.mode} | Profile: #{status.profile} | Workspace: #{status.workspace} | Cost: $#{Float.round(status.cost, 3)}"

    append_system(socket, msg)
  end

  def handle({:unknown, cmd}, socket) do
    append_system(socket, "Unknown command: #{cmd}. Type /help for available commands.")
  end
end
