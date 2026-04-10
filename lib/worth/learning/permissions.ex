defmodule Worth.Learning.Permissions do
  @moduledoc """
  Permission gating for reading coding agent data directories.

  Each coding agent provider (Claude Code, Codex, Gemini, OpenCode) reads
  from directories under the user's home directory that may contain sensitive
  data (session transcripts, project context, user preferences). Before
  Worth reads from these directories, the user must explicitly grant
  permission.

  Permissions are persisted in `Worth.Settings` under the `"preference"`
  category as a JSON blob keyed by `"agent_permissions"`. Each agent maps to
  `:granted`, `:denied`, or is absent (never asked).

  ## Flow

  1. Before learning, `check/1` is called for each agent.
  2. If `:granted`, learning proceeds.
  3. If `:denied` or unset, the agent is skipped.
  4. After discovery, `request_permissions/2` returns a list of agents
     that have never been asked. The UI shows a prompt for these.
  5. `grant/1` or `deny/1` persists the decision.

  ## Usage

      # Check if an agent can be read
      :granted = Worth.Learning.Permissions.check(:claude_code)

      # Get all agents needing permission prompts
      Worth.Learning.Permissions.unasked_agents()
      # => [:codex, :gemini]

      # Persist user decision
      Worth.Learning.Permissions.grant(:codex)
      Worth.Learning.Permissions.deny(:gemini)
  """

  @permission_key "agent_permissions"

  @doc "Returns `:granted`, `:denied`, or `:unasked` for the given agent."
  def check(agent) when is_atom(agent) do
    permissions = load_permissions()
    Map.get(permissions, to_string(agent), :unasked)
  end

  @doc "Grant permission for an agent. Persists to encrypted settings."
  def grant(agent) when is_atom(agent) do
    update_permissions(fn perms -> Map.put(perms, to_string(agent), :granted) end)
  end

  @doc "Deny permission for an agent. Persists to encrypted settings."
  def deny(agent) when is_atom(agent) do
    update_permissions(fn perms -> Map.put(perms, to_string(agent), :denied) end)
  end

  @doc """
  Returns agents that are available on disk but have never been asked.

  Each entry includes `:agent` (atom), `:data_paths` (list of strings),
  and `:status` (:unasked).
  """
  def unasked_agents do
    permissions = load_permissions()

    coding_agent_providers()
    |> Enum.filter(fn provider ->
      provider.available?() and
        not Map.has_key?(permissions, to_string(provider.agent_name()))
    end)
    |> Enum.map(fn provider ->
      %{agent: provider.agent_name(), data_paths: provider.data_paths(), status: :unasked}
    end)
  end

  @doc """
  Returns all agents with their current permission status.

  Includes agents that exist on disk and agents that have been previously
  decided (even if no longer installed).
  """
  def all_statuses do
    permissions = load_permissions()

    coding_agent_providers()
    |> Enum.map(fn provider ->
      name = provider.agent_name()
      available = provider.available?()
      status = Map.get(permissions, to_string(name), if(available, do: :unasked, else: :unavailable))

      %{
        agent: name,
        data_paths: provider.data_paths(),
        available: available,
        permission: status
      }
    end)
  end

  defp safe_to_atom(v) when is_binary(v) do
    String.to_existing_atom(v)
  rescue
    ArgumentError -> v
  end

  defp safe_to_atom(v), do: v

  defp load_permissions do
    case Worth.Settings.get(@permission_key) do
      nil ->
        %{}

      json when is_binary(json) ->
        case Jason.decode(json) do
          {:ok, perms} when is_map(perms) ->
            Enum.into(perms, %{}, fn {k, v} ->
              atom_v = if is_atom(v), do: v, else: safe_to_atom(v)
              {k, atom_v}
            end)

          _ ->
            %{}
        end
    end
  rescue
    _ -> %{}
  end

  defp update_permissions(fun) do
    permissions = load_permissions()
    new_permissions = fun.(permissions)
    json = Jason.encode!(new_permissions)
    Worth.Settings.put(@permission_key, json, "preference")
    :ok
  end

  defp coding_agent_providers do
    Mneme.Learner.CodingAgent.providers()
  end
end
