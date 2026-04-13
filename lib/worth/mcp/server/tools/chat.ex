defmodule Worth.Mcp.Server.Tools.Chat do
  @moduledoc "Send a message to worth and get a response"
  use Hermes.Server.Component, type: :tool

  schema do
    field(:message, :string, required: true, description: "The message to send to worth")
  end

  @impl true
  def execute(%{"message" => message}, frame) do
    workspace = Worth.Config.get(:current_workspace, "personal")

    case Worth.Brain.send_message(message, workspace) do
      {:ok, response} ->
        text = response[:text] || response.text || inspect(response)
        {:reply, text, frame}

      {:error, reason} ->
        {:error, reason, frame}
    end
  catch
    :exit, {:timeout, _} ->
      {:error, "Brain request timed out", frame}

    :exit, reason ->
      {:error, "Brain unavailable: #{inspect(reason)}", frame}
  end
end
