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

  import Ecto.Query

  alias Worth.Learning.State
  alias Worth.Repo

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
      Map.new(mapping, fn {k, v} -> {to_string(k), Enum.map(v, &to_string/1)} end)

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
    Worth.Learning.AgentConfig.provider_configs_for_recollect()
    |> Enum.filter(fn {mod, config} -> mod.available?(config) end)
    |> Enum.map(fn {mod, config} ->
      projects = discover_projects(mod, config)
      {mod.agent_name(), projects}
    end)
    |> Enum.reject(fn {_, projects} -> projects == [] end)
    |> Map.new()
  end

  def unmapped_for_workspace(workspace_name) do
    current_mapping = get(workspace_name)

    Enum.flat_map(discover(), fn {agent, projects} ->
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

  @doc """
  Returns all project mappings across all workspaces.

  Returns `%{workspace_name => %{agent => [projects]}}`.
  """
  def all_mappings do
    from(s in State, where: s.key == ^@mapping_key, select: {s.workspace_name, s.value})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Returns a map of project => workspace_name for all projects already mapped.

  Only includes the first workspace for each project (in case of duplicates).
  """
  def project_to_workspace_map do
    Enum.reduce(all_mappings(), %{}, fn {workspace_name, agents}, acc ->
      Enum.reduce(agents, acc, fn {agent, projects}, acc2 ->
        Enum.reduce(projects, acc2, fn project, acc3 ->
          Map.put_new(acc3, "#{agent}:#{project}", workspace_name)
        end)
      end)
    end)
  end

  @doc """
  Checks if a project is already mapped to another workspace.

  Returns `{:ok, workspace_name}` if mapped elsewhere, `:ok` if available.
  """
  def mapped_elsewhere?(agent, project, current_workspace) do
    map = project_to_workspace_map()
    key = "#{agent}:#{project}"

    case Map.get(map, key) do
      nil -> :ok
      ^current_workspace -> :ok
      other_workspace -> {:ok, other_workspace}
    end
  end

  @doc """
  Returns true if the project name is similar to the workspace name.

  Uses word-level matching with common path segments filtered out.
  """
  def similar_to_workspace?(workspace_name, project_name) do
    ws = normalize(workspace_name)
    proj = normalize(project_name)

    # Common path segments to filter out
    common = ["home", "lenz", "code", "users", "tmp", "var", "opt", "usr"]

    ws_words = String.split(ws)
    proj_words = String.split(proj)

    # Filter out common path segments
    ws_sig = Enum.reject(ws_words, &(&1 in common))
    proj_sig = Enum.reject(proj_words, &(&1 in common))

    # If workspace name is only common segments, it can't match anything meaningfully
    if ws_sig == [] do
      false
    else
      # Check if any significant word from workspace appears in project
      Enum.any?(ws_sig, &(&1 in proj_sig))
    end
  end

  defp normalize(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[-_]/, " ")
    |> String.trim()
  end

  defp discover_projects(provider, config) do
    config
    |> provider.fetch_events()
    |> Enum.map(&Map.get(&1, :project))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
