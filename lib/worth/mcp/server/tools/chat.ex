defmodule Worth.Mcp.Server.Tools.Chat do
  @moduledoc "Send a message to worth and get a response"
  use Hermes.Server.Component, type: :tool

  schema do
    field(:message, :string, required: true, description: "The message to send to worth")
  end

  @impl true
  def execute(%{"message" => message}, frame) do
    workspace = Application.get_env(:worth, :current_workspace, "personal")

    case Worth.Brain.send_message(message, workspace) do
      {:ok, response} ->
        text = response[:text] || response.text || inspect(response)
        {:reply, text, frame}

      {:error, reason} ->
        {:error, reason, frame}
    end
  rescue
    e ->
      {:error, Exception.message(e), frame}
  end
end
