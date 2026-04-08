defmodule Worth.UI.Chat do
  @moduledoc """
  Main conversation area. Renders all message blocks plus any in-flight
  streaming text from the agent.
  """

  import TermUI.Component.Helpers
  alias TermUI.Renderer.Style
  alias Worth.UI.{Message, Theme}

  def render(state) do
    blocks = build_blocks(state)

    blocks =
      if blocks == [] do
        [text("Chat", Style.new(attrs: [:bold, :dim]))]
      else
        blocks
      end

    stack(:vertical, blocks)
  end

  defp build_blocks(state) do
    base = Enum.flat_map(state.messages, &Message.to_blocks/1)

    if state.streaming_text != "" and state.status == :running do
      base ++ [text(state.streaming_text, Theme.style_for(:assistant))]
    else
      base
    end
  end
end
