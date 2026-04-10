defmodule Worth.Learning.ProjectMapping do
  @moduledoc """
  Maps coding agent projects to Worth workspaces.

  Each coding agent stores data under project slugs (e.g. `-home-lenz-code-worth`
  for Claude Code, `worth` for OpenCode). The user selects which agent projects
  are relevant for each workspace. This mapping is persisted and used during
  learning to filter events.

  ## Storage

  Stored as `%{"claude_code" => ["-home-lenz-code-worth"], "opencode" => ["worth"]}`
  in `worth_learning_state` keyed by `"project_mapping"`.
  """

  alias Worth.Learning.State

  @mapping_key "project_mapping"

  def get(workspace_name) do
    State.load(workspace_name, @mapping_key) || %{}
  end

  def get(workspace_name, agent) do
    workspace_mapping = get(workspace_name)
    Map.get(workspace_mapping, to_string(agent), [])
  end

  def set(workspace_name, agent, projects) when is_atom(agent) and is_list(projects) do
    mapping = get(workspace_name)
    updated = Map.put(mapping, to_string(agent), projects)
    State.save(workspace_name, @mapping_key, updated)
  end

  def set_all(workspace_name, mapping) when is_map(mapping) do
    normalized =
      mapping
      |> Enum.into(%{}, fn {k, v} -> {to_string(k), Enum.map(v, &to_string/1)} end)

    State.save(workspace_name, @mapping_key, normalized)
  end

  def mapped?(workspace_name, agent, project) do
    projects = get(workspace_name, agent)
    project_str = to_string(project)

    if projects == [] do
      true
    else
      project_str in projects
    end
  end

  def discover do
    coding_agent_providers()
    |> Enum.filter(& &1.available?())
    |> Enum.map(fn provider ->
      projects = discover_projects(provider)
      {provider.agent_name(), projects}
    end)
    |> Enum.reject(fn {_, projects} -> projects == [] end)
    |> Enum.into(%{})
  end

  def unmapped_for_workspace(workspace_name) do
    current_mapping = get(workspace_name)

    discover()
    |> Enum.flat_map(fn {agent, projects} ->
      mapped = Map.get(current_mapping, to_string(agent), nil)

      if is_nil(mapped) do
        Enum.map(projects, &%{agent: agent, project: &1})
      else
        Enum.map(projects, &%{agent: agent, project: &1})
      end
    end)
  end

  def needs_mapping?(workspace_name) do
    current_mapping = get(workspace_name)
    discovered = discover()

    if map_size(current_mapping) == 0 and map_size(discovered) > 0 do
      true
    else
      Enum.any?(discovered, fn {agent, _projects} ->
        not Map.has_key?(current_mapping, to_string(agent))
      end)
    end
  end

  defp discover_projects(provider) do
    provider.fetch_events()
    |> Enum.map(&Map.get(&1, :project))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp coding_agent_providers do
    Mneme.Learner.CodingAgent.providers()
  end
end
