defmodule Worth.UI.Message do
  @moduledoc """
  Pure render functions for chat message tuples.

  Each message in `state.messages` is a tagged tuple (`{:user, text}`,
  `{:assistant, text}`, `{:tool_call, map}`, etc.). `to_blocks/1` converts
  one message into a list of `RenderNode`s ready to be placed inside a
  vertical stack.
  """

  import TermUI.Component.Helpers
  alias Worth.UI.Theme

  def to_blocks({:user, text}) do
    [text("> #{text}", Theme.style_for(:user_input))]
  end

  def to_blocks({:assistant, text}) do
    split_lines(text, Theme.style_for(:assistant))
  end

  def to_blocks({:system, text}) do
    split_lines(text, Theme.style_for(:system), "[system] ")
  end

  def to_blocks({:error, text}) do
    split_lines(text, Theme.style_for(:error), "[error] ")
  end

  def to_blocks({:tool_call, %{name: name, input: input}}) do
    input_str = if is_map(input), do: Jason.encode!(input, pretty: false), else: inspect(input)
    [text("┌ #{name}: #{String.slice(input_str, 0, 60)}", Theme.style_for(:tool_call))]
  end

  def to_blocks({:tool_result, %{name: _name, output: output}}) do
    preview = String.slice(output || "", 0, 80)
    [text("└ #{preview}", Theme.style_for(:tool_result))]
  end

  def to_blocks({:thinking, text}) do
    [text("(thinking: #{String.slice(text, 0, 50)}...)", Theme.style_for(:thinking))]
  end

  def to_blocks(_), do: []

  defp split_lines(content, style, prefix \\ "") do
    content
    |> String.split("\n")
    |> Enum.map(&text("#{prefix}#{&1}", style))
  end
end
