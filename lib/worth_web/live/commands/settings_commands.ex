defmodule WorthWeb.Commands.SettingsCommands do
  import Phoenix.Component, only: [assign: 2]

  def handle(:settings, socket) do
    if socket.assigns[:view] == :settings do
      assign(socket, view: :chat)
    else
      # Reload settings data each time we open
      socket
      |> assign(view: :settings)
      |> WorthWeb.ChatLive.refresh_settings_form()
    end
  end
end
