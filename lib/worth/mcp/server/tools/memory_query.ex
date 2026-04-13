defmodule Worth.Mcp.Server.Tools.MemoryQuery do
  @moduledoc "Search worth's global knowledge store"
  use Hermes.Server.Component, type: :tool

  schema do
    field(:query, :string, required: true, description: "Search query")
    field(:limit, :integer, description: "Max results to return", default: 5)
    field(:workspace, :string, description: "Optional workspace to boost results from")
  end

  @impl true
  def execute(%{"query" => query} = params, frame) do
    opts = [limit: params["limit"] || 5]
    opts = if params["workspace"], do: Keyword.put(opts, :workspace, params["workspace"]), else: opts

    case Worth.Memory.Manager.search(query, opts) do
      {:ok, %{entries: entries}} ->
        lines =
          Enum.map_join(entries, "\n", fn e ->
            "[#{Float.round(e.confidence || 0.5, 2)}] #{e.content}"
          end)

        {:reply, lines, frame}

      {:error, reason} ->
        {:error, inspect(reason), frame}
    end
  rescue
    e -> {:error, Exception.message(e), frame}
  end
end
