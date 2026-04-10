defmodule WorthWeb.Commands.SystemCommands do
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
