defmodule Worth.UI.Header do
  @moduledoc """
  Top bar: status indicator, workspace name, current mode.
  """

  import TermUI.Component.Helpers
  alias Worth.UI.Theme

  def render(state) do
    indicator = Theme.status_indicator(state.status)
    text("[#{indicator}] worth ▸ #{state.workspace} [mode: #{state.mode}]", Theme.style_for(:header))
  end
end
