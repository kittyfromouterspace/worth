defmodule Worth.Memory.GraphNotifier do
  @moduledoc false

  alias Worth.PubSub

  def notify(%{type: type, operation: operation} = event) when type in [:entity, :relation] do
    Phoenix.PubSub.broadcast(PubSub, "worth_graph_change", {:graph, operation, event})
    :ok
  end

  def notify(_event), do: :ok
end
