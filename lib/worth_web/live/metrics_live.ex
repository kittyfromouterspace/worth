defmodule WorthWeb.MetricsLive do
  @moduledoc """
  LiveView for metrics dashboard and analysis.
  """

  use WorthWeb, :live_view

  alias Worth.Metrics.Queries

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      send(self(), :load_data)
    end

    {:ok,
     socket
     |> assign(:strategy_comparison, [])
     |> assign(:tool_analysis, [])
     |> assign(:recent_sessions, [])
     |> assign(:active_tab, "overview")}
  end

  @impl true
  def handle_event("tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_info(:load_data, socket) do
    {:noreply,
     socket
     |> assign(:strategy_comparison, Queries.strategy_comparison())
     |> assign(:tool_analysis, Queries.tool_analysis())
     |> assign(:recent_sessions, Queries.recent_sessions())}
  end

  defp format_float(nil), do: "0"
  defp format_float(v) when is_float(v), do: :erlang.float_to_binary(v, decimals: 4)
  defp format_float(v) when is_integer(v), do: Integer.to_string(v)
  defp format_float(_), do: "0"

  defp format_int(nil), do: "0"
  defp format_int(v) when is_number(v), do: v |> round() |> Integer.to_string()
  defp format_int(_), do: "0"

  defp status_color("completed"), do: "text-green-400"
  defp status_color("running"), do: "text-yellow-400"
  defp status_color("failed"), do: "text-red-400"
  defp status_color("errored"), do: "text-red-400"
  defp status_color(_), do: "text-gray-400"
end
