defmodule Worth.Mcp.Server.Tools.MemoryWrite do
  @moduledoc "Store a fact in worth's knowledge store"
  use Hermes.Server.Component, type: :tool

  schema do
    field(:content, :string, required: true, description: "The fact or knowledge to store")
    field(:entry_type, :string, description: "Entry type: note, observation, decision", default: "note")
    field(:workspace, :string, description: "Optional workspace to tag the entry with")
    field(:confidence, :float, description: "Confidence level 0.0-1.0", default: 0.8)
  end

  @impl true
  def execute(%{"content" => content} = params, frame) do
    opts = [
      entry_type: params["entry_type"] || "note",
      source: "mcp_client",
      confidence: params["confidence"] || 0.8
    ]

    opts = if params["workspace"], do: Keyword.put(opts, :workspace, params["workspace"]), else: opts

    case Worth.Memory.Manager.remember(content, opts) do
      {:ok, _} ->
        {:reply, "Fact stored successfully.", frame}

      {:error, reason} ->
        {:error, inspect(reason), frame}
    end
  rescue
    e -> {:error, Exception.message(e), frame}
  end
end
