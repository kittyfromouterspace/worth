defmodule Worth.UI.Header do
  @moduledoc """
  Top bar: status indicator, workspace name, current mode, cost, turn count.

  Enhanced with status indicators inspired by amux/lazygit.
  """

  import TermUI.Component.Helpers
  alias Worth.UI.Theme

  def render(state) do
    indicator = status_indicator(state.status)
    mode_badge = mode_badge(state.mode)
    cost = cost_display(state.cost)
    turns = turn_display(state.turn)
    model = model_display(state)

    text(
      "#{indicator} worth | #{state.workspace} | #{mode_badge} | #{turns} | #{cost} #{model}",
      Theme.style_for(:header)
    )
  end

  defp status_indicator(:running), do: "●"
  defp status_indicator(:idle), do: "○"
  defp status_indicator(:error), do: "×"

  defp mode_badge(mode) when is_atom(mode) do
    "[#{Atom.to_string(mode)}]"
  end

  defp cost_display(cost) when is_float(cost) do
    "$#{:erlang.float_to_binary(cost, [{:decimals, 4}])}"
  end

  defp turn_display(turn) when is_integer(turn) do
    "t#{turn}"
  end

  defp model_display(state) do
    primary = Map.get(state.models, :primary, %{})
    label = Map.get(primary, :label, "")
    if label != "", do: "(#{label})", else: ""
  end
end
