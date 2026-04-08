defmodule Worth.UI.Message do
  @moduledoc """
  Pure render functions for chat message tuples.

  Each message in `state.messages` is a tagged tuple (`{:user, text}`,
  `{:assistant, text}`, `{:tool_call, map}`, etc.). `to_blocks/1` converts
  one message into a list of `RenderNode`s ready to be placed inside a
  vertical stack.

  Card-based rendering with status indicators inspired by amux/lazygit.
  """

  import TermUI.Component.Helpers
  alias Worth.UI.Theme

  @max_preview_len 120
  @max_input_preview 50

  def to_blocks({:user, text}) do
    header = text("○ you", Theme.user_style())
    content = text("#{text}", Theme.style_for(:user_input))
    [header, content]
  end

  def to_blocks({:assistant, text}) do
    header = text("◉ assistant", Theme.assistant_style())
    content = split_lines(text, Theme.style_for(:assistant))
    [header | content]
  end

  def to_blocks({:system, text}) do
    header = text("⚠ system", Theme.system_style())
    content = split_lines(text, Theme.system_style())
    [header | content]
  end

  def to_blocks({:error, text}) do
    header = text("× error", Theme.error_style())
    content = split_lines(text, Theme.error_style())
    [header | content]
  end

  def to_blocks({:tool_call, %{name: name, input: input, status: status}}) do
    status_indicator = Theme.tool_status(status || :pending)
    status_style = Theme.tool_status_style(status || :pending)

    input_str = format_input(input)
    [text("#{status_indicator} #{name}", status_style), text("  #{input_str}", Theme.style_for(:tool_call))]
  end

  def to_blocks({:tool_call, %{name: name, input: input}}) do
    input_str = format_input(input)
    [text("○ #{name}", Theme.tool_status_style(:pending)), text("  #{input_str}", Theme.style_for(:tool_call))]
  end

  def to_blocks({:tool_result, %{name: _name, output: output, status: status}}) do
    status_indicator = Theme.tool_status(status || :success)
    status_style = Theme.tool_status_style(status || :success)
    preview = String.slice(output || "", 0, @max_preview_len)
    [text("#{status_indicator} result", status_style), text("  #{preview}", Theme.style_for(:tool_result))]
  end

  def to_blocks({:tool_result, %{name: _name, output: output}}) do
    preview = String.slice(output || "", 0, @max_preview_len)
    [text("✓ result", Theme.tool_status_style(:success)), text("  #{preview}", Theme.style_for(:tool_result))]
  end

  def to_blocks({:thinking, text}) do
    [text("○ thinking...", Theme.style_for(:thinking)), text("  #{text}", Theme.style_for(:thinking))]
  end

  def to_blocks({:approval, %{tool_call_id: _id, name: name, input: input}}) do
    input_str = format_input(input)

    [
      text("? approve?", Theme.badge_style()),
      text("  #{name}", Theme.tool_status_style(:warning)),
      text("  #{input_str}", Theme.style_for(:tool_call)),
      text("  [a]pprove [d]eny", Theme.keyhint_style())
    ]
  end

  def to_blocks(_), do: []

  defp split_lines(content, style, prefix \\ "") do
    content
    |> String.split("\n")
    |> Enum.map(&text("#{prefix}#{&1}", style))
  end

  defp format_input(input) when is_map(input) do
    input
    |> Jason.encode!(pretty: false)
    |> String.slice(0, @max_input_preview)
  end

  defp format_input(input) when is_binary(input) do
    String.slice(input, 0, @max_input_preview)
  end

  defp format_input(input) do
    inspect(input) |> String.slice(0, @max_input_preview)
  end
end
