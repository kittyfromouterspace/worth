defmodule Worth.Tools.Memory do
  @moduledoc false

  alias Worth.Memory.Manager

  def definitions do
    [
      %{
        name: "memory_query",
        description: "Search the global knowledge store for relevant memories and facts",
        input_schema: %{
          type: "object",
          properties: %{
            query: %{type: "string", description: "Search query for memory retrieval"},
            limit: %{type: "integer", description: "Max results (default: 5)", default: 5}
          },
          required: ["query"]
        }
      },
      %{
        name: "memory_write",
        description: "Store a fact or observation in the global knowledge store",
        input_schema: %{
          type: "object",
          properties: %{
            content: %{type: "string", description: "The fact or observation to remember"},
            entry_type: %{
              type: "string",
              description: "Type: note, observation, decision, event, hypothesis",
              default: "note"
            },
            confidence: %{type: "number", description: "Confidence 0.0-1.0 (default: 0.8)"}
          },
          required: ["content"]
        }
      },
      %{
        name: "memory_note",
        description: "Add a session-local note to working memory (ephemeral, not persisted until flush)",
        input_schema: %{
          type: "object",
          properties: %{
            content: %{type: "string", description: "The note content"},
            importance: %{type: "number", description: "Importance 0.0-1.0 (default: 0.5)"}
          },
          required: ["content"]
        }
      },
      %{
        name: "memory_recall",
        description: "Read all entries in the current session's working memory",
        input_schema: %{
          type: "object",
          properties: %{}
        }
      }
    ]
  end

  def execute("memory_query", %{"query" => query} = args, workspace) do
    opts = [
      workspace: workspace,
      limit: args["limit"] || 5
    ]

    case Manager.search(query, opts) do
      {:ok, %{entries: entries}} ->
        formatted = format_entries(entries)
        {:ok, formatted}

      {:ok, %{}} ->
        {:ok, "No memories found."}

      {:error, reason} ->
        {:error, "Memory query failed: #{inspect(reason)}"}
    end
  end

  def execute("memory_write", %{"content" => content} = args, workspace) do
    opts = [
      workspace: workspace,
      entry_type: args["entry_type"] || "note",
      source: "agent",
      confidence: args["confidence"] || 0.8
    ]

    case Manager.remember(content, opts) do
      {:ok, _entry} ->
        {:ok, "Fact stored successfully."}

      {:error, reason} ->
        {:error, "Failed to store fact: #{inspect(reason)}"}
    end
  end

  def execute("memory_note", %{"content" => content} = args, workspace) do
    opts = [
      workspace: workspace,
      importance: args["importance"] || 0.5,
      metadata: %{entry_type: "note", role: "working"}
    ]

    case Manager.working_push(content, opts) do
      {:ok, _} ->
        {:ok, "Note added to working memory."}

      {:error, reason} ->
        {:error, "Failed to add note: #{inspect(reason)}"}
    end
  end

  def execute("memory_recall", _args, workspace) do
    case Manager.working_read(workspace: workspace) do
      {:ok, entries} when is_list(entries) and entries != [] ->
        formatted =
          Enum.map_join(entries, "\n", fn e -> "- [#{Map.get(e, :importance, 0.5)}] #{e.content}" end)

        {:ok, formatted}

      _ ->
        {:ok, "Working memory is empty."}
    end
  end

  def execute(name, _args, _workspace) do
    {:error, "Unknown memory tool: #{name}"}
  end

  defp format_entries(entries) do
    Enum.map_join(entries, "\n", fn e ->
      confidence = Float.round(e.confidence || 0.5, 2)
      workspace_tag = get_in(e, [:metadata, :workspace]) || "global"
      "- [#{confidence}] (#{workspace_tag}) #{e.content}"
    end)
  end
end
