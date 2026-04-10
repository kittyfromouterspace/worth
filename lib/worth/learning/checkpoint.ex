defmodule Worth.Learning.Checkpoint do
  @moduledoc """
  Checkpoint tracking for incremental learning.

  Stores per-workspace, per-source checkpoint data so that subsequent
  learning runs only process new events.

  ## Checkpoint shapes

  - **Git**: `%{"latest_sha" => "abc123..."}`
  - **Coding agents**: `%{"claude_code" => %{"project-slug" => ~U[...]}}, "codex" => %{...}}`
  """

  alias Worth.Learning.State

  @git_key "checkpoint:git"
  @agents_key "checkpoint:coding_agents"

  def load_git(workspace_name) do
    State.load(workspace_name, @git_key) || %{}
  end

  def save_git(workspace_name, sha) when is_binary(sha) do
    State.save(workspace_name, @git_key, %{"latest_sha" => sha})
  end

  def load_agents(workspace_name) do
    State.load(workspace_name, @agents_key) || %{}
  end

  def save_agents(workspace_name, checkpoints) when is_map(checkpoints) do
    State.save(workspace_name, @agents_key, checkpoints)
  end

  def update_agent_timestamp(checkpoints, agent, project, timestamp) when is_map(checkpoints) do
    agent_str = to_string(agent)
    project_str = to_string(project)
    ts_str = if is_binary(timestamp), do: timestamp, else: DateTime.to_iso8601(timestamp)

    agent_map = Map.get(checkpoints, agent_str, %{})
    Map.put(checkpoints, agent_str, Map.put(agent_map, project_str, ts_str))
  end

  def get_agent_timestamp(checkpoints, agent, project) when is_map(checkpoints) do
    agent_str = to_string(agent)
    project_str = to_string(project)

    with {:ok, agent_map} <- Map.fetch(checkpoints, agent_str),
         {:ok, ts_str} <- Map.fetch(agent_map, project_str) do
      case DateTime.from_iso8601(ts_str) do
        {:ok, dt, _} -> dt
        _ -> nil
      end
    else
      _ -> nil
    end
  end
end
