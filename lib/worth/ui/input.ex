defmodule Worth.UI.Input do
  @moduledoc """
  Single-line input prompt at the bottom of the TUI.

  This is currently a plain text node — when we adopt TermUI's `TextInput`
  widget the cursor and history affordances will move here.
  """

  import TermUI.Component.Helpers
  alias Worth.UI.Theme

  def render(state) do
    text("> #{state.input_text}", Theme.style_for(:user_input))
  end
end
