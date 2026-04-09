defmodule WorthWeb.Commands.Helpers do
  import Phoenix.LiveView, only: [stream_insert: 3]

  def append_system(socket, msg) do
    WorthWeb.ChatLive.append_system_message(socket, msg)
  end

  def append_error(socket, msg) do
    stream_insert(socket, :messages, %{
      id: System.unique_integer([:positive]) |> to_string(),
      type: :error,
      content: msg
    })
  end
end
