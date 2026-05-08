defmodule Worth.AgentFS.Materializer do
  @moduledoc """
  Worth-specific implementation for AgentFS materialization.

  Provides callbacks to:
  1. Materialize skills from DB into temp files
  2. Materialize memories from Recollect into temp files
  3. Sync back agent-created skills to DB
  4. Sync back agent-created memories to Recollect

  This module is passed to Agentic.AgentFS via ctx.metadata[:agent_fs_materializer].
  """

  alias Worth.Memory.Manager
  alias Worth.Skill.Service

  require Logger

  # --- Skill Materialization ---

  @doc """
  Materialize skills for AgentFS.
  Returns list of %{name: ..., content: ...} maps.
  """
  def materialize_skills(opts) do
    workspace = opts[:workspace] || current_workspace()

    [workspace: workspace]
    |> Service.list()
    |> Enum.map(fn skill ->
      %{
        name: skill.name,
        content: skill.body
      }
    end)
  end

  @doc """
  Sync back skills created by the agent.
  skills_data is list of %{name: ..., content: ..., is_new: bool}
  """
  def sync_back_skills(skills_data, opts) do
    workspace = opts[:workspace] || current_workspace()

    for %{name: name, content: content, is_new: true} <- skills_data do
      Logger.info("AgentFS: Syncing back skill '#{name}' to workspace '#{workspace}'")

      case Service.install(
             %{type: :content, name: name, content: content},
             workspace: workspace,
             trust_level: :learned,
             provenance: :agent,
             description: "Agent-created skill"
           ) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.warning("AgentFS: Failed to sync skill '#{name}': #{reason}")
      end
    end

    :ok
  end

  # --- Memory Materialization ---

  @doc """
  Materialize memories for AgentFS.
  Returns formatted Markdown string.
  """
  def materialize_memories(opts) do
    workspace = opts[:workspace] || current_workspace()

    entries =
      case Manager.recent(workspace: workspace, limit: 100) do
        {:ok, entries} when is_list(entries) -> entries
        _ -> []
      end

    format_memories(entries)
  end

  @doc """
  Sync back memories modified by the agent.
  memory_content is the full MEMORY.md text.
  """
  def sync_back_memories(memory_content, opts) do
    workspace = opts[:workspace] || current_workspace()

    {:ok, new_memories} = parse_agent_memories(memory_content)

    for memory <- new_memories do
      Manager.remember(memory.content,
        workspace: workspace,
        entry_type: memory.entry_type || "note",
        source: "agent",
        confidence: memory.confidence || 0.8,
        metadata: memory.metadata || %{}
      )
    end

    Logger.info("AgentFS: Synced #{length(new_memories)} memories back to workspace '#{workspace}'")
    :ok
  end

  # --- Formatting ---

  defp format_memories(entries) do
    header = "# Project Memory\n\n"

    sections =
      Enum.map(entries, fn entry ->
        entry_type = entry.entry_type || "note"
        confidence = entry.confidence || 0.5
        workspace_tag = get_in(entry, [:metadata, :workspace]) || "unknown"

        """
        ## #{String.capitalize(entry_type)} [confidence: #{confidence}, workspace: #{workspace_tag}]
        #{entry.content}
        """
      end)

    separator = "\n---\n\n# Agent-created memories below this line will be synced back to the knowledge store.\n"

    header <> Enum.join(sections, "\n\n") <> separator
  end

  defp parse_agent_memories(content) do
    case String.split(content, "---") do
      [_before, after_marker | _] ->
        lines = String.split(after_marker, "\n", trim: true)
        memories = parse_memory_lines(lines)
        {:ok, memories}

      _ ->
        # No separator found, no agent memories
        {:ok, []}
    end
  end

  defp parse_memory_lines(lines, acc \\ []) do
    case lines do
      [] ->
        Enum.reverse(acc)

      ["## " <> _ = header | rest] ->
        case parse_memory_entry(header, rest, []) do
          {memory, remaining} -> parse_memory_lines(remaining, [memory | acc])
          nil -> parse_memory_lines(rest, acc)
        end

      [_ | rest] ->
        parse_memory_lines(rest, acc)
    end
  end

  defp parse_memory_entry(header, lines, content_acc) do
    case lines do
      [] ->
        content = content_acc |> Enum.reverse() |> Enum.join("\n") |> String.trim()

        if content == "" do
          nil
        else
          {build_memory(header, content), []}
        end

      ["## " <> _ | _] ->
        content = content_acc |> Enum.reverse() |> Enum.join("\n") |> String.trim()

        if content == "" do
          nil
        else
          {build_memory(header, content), lines}
        end

      [line | rest] ->
        parse_memory_entry(header, rest, [line | content_acc])
    end
  end

  defp build_memory(header, content) do
    # Parse header like "Observation [confidence: 0.9, workspace: my-project]"
    {entry_type, metadata} = parse_header(header)

    %{
      entry_type: entry_type,
      content: content,
      confidence: metadata[:confidence] || 0.8,
      metadata: %{
        workspace: metadata[:workspace] || "unknown"
      }
    }
  end

  defp parse_header(header) do
    # Extract type before the bracket
    case Regex.run(~r/^(\w+)\s*\[(.*?)\]/, header) do
      [_, type, attrs_str] ->
        attrs = parse_attrs(attrs_str)
        {String.downcase(type), attrs}

      _ ->
        {"note", %{}}
    end
  end

  defp parse_attrs(attrs_str) do
    attrs_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reduce(%{}, fn attr, acc ->
      case String.split(attr, ":", parts: 2) do
        [key, value] ->
          key = key |> String.trim() |> String.to_atom()
          value = String.trim(value)

          value =
            case Float.parse(value) do
              {f, ""} -> f
              _ -> value
            end

          Map.put(acc, key, value)

        _ ->
          acc
      end
    end)
  end

  defp current_workspace do
    Worth.Config.get(:current_workspace, "personal")
  end
end
