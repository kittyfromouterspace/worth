defmodule Worth.Workspace.Context do
  @moduledoc false
  alias Worth.Memory.Manager

  @system_prompt_path Path.join(:code.priv_dir(:worth), "prompts/system.md")

  @memory_section_header "\n\n## Memory Context\n\nRelevant knowledge from previous sessions:\n"
  @working_memory_header "\n\n## Working Memory\n\nCurrent session notes:\n"
  @max_memory_chars 4000

  def build_system_prompt(workspace_path, opts \\ []) do
    base = load_base_prompt()
    identity = load_identity(workspace_path)
    agents = load_agents(workspace_path)
    workspace = opts[:workspace] || Path.basename(workspace_path)

    skills = Worth.Skill.Registry.metadata_for_prompt()
    memory_context = load_memory_context(workspace, opts[:user_message])
    working_context = load_working_memory(workspace)

    parts =
      [base, identity, agents, skills, memory_context, working_context]
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    {:ok, parts}
  end

  defp load_base_prompt do
    case File.read(@system_prompt_path) do
      {:ok, content} -> String.trim(content)
      {:error, _} -> "You are Worth, a personal AI assistant that helps with development, research, and automation."
    end
  end

  defp load_identity(workspace_path) do
    case File.read(Path.join(workspace_path, "IDENTITY.md")) do
      {:ok, content} -> String.trim(content)
      {:error, _} -> nil
    end
  end

  defp load_agents(workspace_path) do
    case File.read(Path.join(workspace_path, "AGENTS.md")) do
      {:ok, content} -> String.trim(content)
      {:error, _} -> nil
    end
  end

  defp load_memory_context(workspace, nil) do
    load_recent_memory(workspace)
  end

  defp load_memory_context(workspace, user_message) do
    case Manager.build_memory_context(user_message, workspace: workspace) do
      {:ok, nil} ->
        load_recent_memory(workspace)

      {:ok, text} when byte_size(text) > 0 ->
        truncate(@memory_section_header <> text, @max_memory_chars)

      _ ->
        load_recent_memory(workspace)
    end
  end

  defp load_recent_memory(workspace) do
    case Manager.recent(workspace: workspace, limit: 5) do
      {:ok, entries} when is_list(entries) and entries != [] ->
        lines =
          Enum.map_join(entries, "\n", fn e -> "- #{e.content}" end)

        truncate(@memory_section_header <> lines, @max_memory_chars)

      _ ->
        nil
    end
  end

  defp load_working_memory(workspace) do
    case Manager.working_read(workspace: workspace) do
      {:ok, entries} when is_list(entries) and entries != [] ->
        lines =
          Enum.map_join(entries, "\n", fn e -> "- #{e.content}" end)

        @working_memory_header <> lines

      _ ->
        nil
    end
  end

  defp truncate(text, max_bytes) do
    if byte_size(text) <= max_bytes do
      text
    else
      slice = binary_part(text, 0, max_bytes)
      slice <> "\n... (truncated)"
    end
  end
end
