defmodule Worth.Workspace.Learning do
  @moduledoc """
  Manages learning pipelines for workspace content.

  When a workspace is switched to or created, this module:
  1. Scans for new/changed content
  2. Reports findings to the user
  3. If approved, ingests content into Mneme
  4. Tracks what has been indexed
  """

  import Ecto.Query

  alias Worth.Learning.Checkpoint
  alias Worth.Learning.Permissions
  alias Worth.Learning.ProjectMapping
  alias Worth.Repo
  alias Worth.Workspace.IndexEntry
  alias Worth.Workspace.Scanner

  require Logger

  @doc """
  Analyzes a workspace and returns a learning opportunity report.

  Includes permission status and project mapping status for coding agents.
  """
  def analyze(workspace_name, opts \\ []) do
    case Scanner.scan(workspace_name, opts) do
      {:ok, scan_report} ->
        is_new = Scanner.new_workspace?(workspace_name)
        opportunities = build_opportunities(scan_report)

        unasked_agents = Permissions.unasked_agents()
        needs_mapping = ProjectMapping.needs_mapping?(workspace_name)
        discovered_projects = ProjectMapping.discover()

        recommendation =
          cond do
            unasked_agents != [] ->
              names = Enum.map_join(unasked_agents, ", ", & &1.agent)
              "Found coding agents that need permission before learning: #{names}"

            needs_mapping ->
              "Coding agent projects found — select which ones to learn from."

            is_new and scan_report.new_count > 0 ->
              "This appears to be a new workspace with #{scan_report.new_count} items that could be learned."

            scan_report.modified_count > 0 ->
              "Found #{scan_report.modified_count} modified items that could be re-learned."

            true ->
              "No new content detected."
          end

        report = %{
          workspace: workspace_name,
          is_new: is_new,
          opportunities: opportunities,
          total_items: scan_report.new_count + scan_report.modified_count,
          total_new_bytes: scan_report.total_new_bytes,
          total_modified_bytes: scan_report.total_modified_bytes,
          recommendation: recommendation,
          has_learning_opportunity: scan_report.has_changes,
          unasked_agents: unasked_agents,
          needs_project_mapping: needs_mapping,
          discovered_projects: discovered_projects
        }

        {:ok, report}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Ingests content from a workspace into Mneme memory.

  This should be called after the user approves learning. It:
  1. Processes each new/modified item through the appropriate pipeline
  2. Creates IndexEntry records to track what was indexed
  3. Returns a summary of what was learned

  Returns:
    {:ok, %{ingested: integer(), errors: integer(), details: [...]}}
  """
  def ingest(workspace_name, _opts \\ []) do
    scope_id = workspace_scope_id(workspace_name)

    git_checkpoint = Checkpoint.load_git(workspace_name)
    git_since = Map.get(git_checkpoint, "latest_sha", "7 days ago")

    project_mapping = ProjectMapping.get(workspace_name)
    agent_checkpoints = Checkpoint.load_agents(workspace_name)

    Logger.info("[Learning] Starting ingestion for #{workspace_name} (git since: #{git_since})")

    git_result = run_git_learning(scope_id, git_since)
    agent_result = run_agent_learning(scope_id, project_mapping, agent_checkpoints)

    if git_result[:latest_git_sha] do
      Checkpoint.save_git(workspace_name, git_result[:latest_git_sha])
    end

    new_agent_checkpoints = compute_agent_checkpoints(agent_result)
    Checkpoint.save_agents(workspace_name, new_agent_checkpoints)

    summary = %{
      workspace: workspace_name,
      ingested: (git_result[:learned] || 0) + (agent_result[:learned] || 0),
      errors: 0,
      git: git_result,
      agents: agent_result
    }

    Logger.info("[Learning] Ingestion complete: #{summary.ingested} learned")

    {:ok, summary}
  end

  defp run_git_learning(scope_id, since) do
    result =
      Mneme.learn(
        scope_id: scope_id,
        sources: [Mneme.Learner.Git],
        since: since
      )

    case result do
      {:ok, %{results: %{git: r}}} -> r
      {:ok, _} -> %{fetched: 0, learned: 0, skipped: 0}
      {:error, reason} -> %{fetched: 0, learned: 0, skipped: 0, error: inspect(reason)}
    end
  rescue
    e ->
      Logger.error("[Learning] Git learning failed: #{Exception.message(e)}")
      %{fetched: 0, learned: 0, skipped: 0, error: Exception.message(e)}
  end

  defp run_agent_learning(scope_id, project_mapping, agent_checkpoints) do
    filter_fn = fn provider ->
      Permissions.check(provider.agent_name()) == :granted
    end

    agent_configs = Worth.Learning.AgentConfig.build_provider_configs()

    {:ok, events} =
      coding_agent_module().fetch_authorized_events(filter_fn,
        projects: project_mapping,
        since: agent_checkpoints,
        agent_configs: agent_configs
      )

    {:ok, run_result} =
      Mneme.learn(
        scope_id: scope_id,
        sources: [coding_agent_module()]
      )

    coding_agents_result = Map.get(run_result.results, :coding_agents, %{})
    Map.put(coding_agents_result, :events, events)
  rescue
    e ->
      Logger.error("[Learning] Agent learning failed: #{Exception.message(e)}")
      %{fetched: 0, learned: 0, error: Exception.message(e)}
  end

  defp compute_agent_checkpoints(agent_result) do
    events = Map.get(agent_result, :events, [])

    events
    |> Enum.group_by(&{Map.get(&1, :agent), Map.get(&1, :project)})
    |> Map.new(fn {{agent, project}, _evts} ->
      now = DateTime.to_iso8601(DateTime.utc_now())
      {to_string(agent), %{to_string(project) => now}}
    end)
  end

  @doc """
  Ingests a specific type of content only.

  Useful for targeted learning, e.g., `ingest_type(workspace, :git_history)`.
  """
  def ingest_type(workspace_name, type, opts \\ []) do
    {:ok, scan_report} = Scanner.scan(workspace_name, opts)

    items = Enum.filter(scan_report.new ++ scan_report.modified, &(&1.type == type))

    results = Enum.map(items, &process_item(&1, workspace_name, opts))

    successful = Enum.filter(results, &match?({:ok, _}, &1))
    failed = Enum.filter(results, &match?({:error, _}, &1))

    {:ok,
     %{
       type: type,
       ingested: length(successful),
       errors: length(failed)
     }}
  end

  @doc """
  Clears all indexed entries for a workspace, effectively marking everything
  as needing re-learning.
  """
  def reset_workspace(workspace_name) do
    {deleted, _} = Repo.delete_all(from(e in IndexEntry, where: e.workspace_name == ^workspace_name))

    Logger.info("[Learning] Reset workspace #{workspace_name}: #{deleted} entries removed")
    {:ok, deleted}
  end

  # Private functions

  defp build_opportunities(scan_report) do
    opportunities = []

    opportunities =
      if scan_report.new_count > 0 do
        new_by_type =
          scan_report.new
          |> Enum.group_by(& &1.type)
          |> Enum.map(fn {type, items} ->
            total_bytes = Enum.sum(Enum.map(items, & &1.size))

            %{
              type: type,
              description: describe_type(type, :new),
              item_count: length(items),
              total_bytes: total_bytes
            }
          end)

        opportunities ++ new_by_type
      else
        opportunities
      end

    opportunities =
      if scan_report.modified_count > 0 do
        modified_by_type =
          scan_report.modified
          |> Enum.group_by(& &1.type)
          |> Enum.map(fn {type, items} ->
            total_bytes = Enum.sum(Enum.map(items, & &1.new_size))

            %{
              type: type,
              description: describe_type(type, :modified),
              item_count: length(items),
              total_bytes: total_bytes
            }
          end)

        opportunities ++ modified_by_type
      else
        opportunities
      end

    opportunities
  end

  defp describe_type(:git_history, :new), do: "Git commit history"
  defp describe_type(:git_history, :modified), do: "Updated git history"
  defp describe_type(:coding_agent_history, :new), do: "Coding agent conversation history"
  defp describe_type(:coding_agent_history, :modified), do: "Updated coding agent conversations"
  defp describe_type(:source_files, :new), do: "Source code files"
  defp describe_type(:source_files, :modified), do: "Modified source files"
  defp describe_type(:documentation, :new), do: "Documentation files"
  defp describe_type(:documentation, :modified), do: "Updated documentation"
  defp describe_type(:workspace_skills, :new), do: "Workspace skills to install"
  defp describe_type(:workspace_skills, :modified), do: "Updated workspace skills"
  defp describe_type(type, _), do: "#{type} content"

  # Install the skill from the workspace
  defp process_item(%{type: :workspace_skills} = item, workspace_name, _opts) do
    _skill_name = item.path |> Path.dirname() |> Path.basename()

    case Worth.Skill.Service.install(%{type: :local, path: Path.dirname(item.path)}, workspace: workspace_name) do
      {:ok, installed_name} ->
        # Record that we indexed this
        entry_attrs = %{
          workspace_name: workspace_name,
          source_type: "workspace_skills",
          source_path: item.path,
          content_hash: item.hash,
          file_size: item.size,
          last_modified: item.modified,
          mneme_entry_ids: [],
          indexed_at: DateTime.utc_now(),
          status: "installed"
        }

        existing =
          Repo.one(from(e in IndexEntry, where: e.workspace_name == ^workspace_name and e.source_path == ^item.path))

        if existing do
          existing
          |> IndexEntry.changeset(entry_attrs)
          |> Repo.update!()
        else
          %IndexEntry{}
          |> IndexEntry.changeset(entry_attrs)
          |> Repo.insert!()
        end

        {:ok, %{path: item.path, type: item.type, skill_name: installed_name}}

      {:error, reason} ->
        {:error, %{path: item.path, type: item.type, reason: reason}}
    end
  rescue
    e ->
      Logger.error("[Learning] Failed to install skill #{item.path}: #{Exception.message(e)}")
      {:error, %{path: item.path, type: item.type, reason: Exception.message(e)}}
  end

  defp process_item(item, workspace_name, _opts) do
    case ingest_by_type(item, workspace_name) do
      {:ok, mneme_entries} ->
        # Record that we indexed this
        entry_attrs = %{
          workspace_name: workspace_name,
          source_type: to_string(item.type),
          source_path: item.path,
          content_hash: item.hash,
          file_size: item.size,
          last_modified: item.modified,
          mneme_entry_ids: mneme_entries,
          indexed_at: DateTime.utc_now(),
          status: "indexed"
        }

        # Update or create index entry
        existing =
          Repo.one(from(e in IndexEntry, where: e.workspace_name == ^workspace_name and e.source_path == ^item.path))

        if existing do
          existing
          |> IndexEntry.changeset(entry_attrs)
          |> Repo.update!()
        else
          %IndexEntry{}
          |> IndexEntry.changeset(entry_attrs)
          |> Repo.insert!()
        end

        {:ok, %{path: item.path, type: item.type, entries: mneme_entries}}

      {:error, reason} ->
        {:error, %{path: item.path, type: item.type, reason: reason}}
    end
  rescue
    e ->
      Logger.error("[Learning] Failed to process #{item.path}: #{Exception.message(e)}")
      {:error, %{path: item.path, type: item.type, reason: Exception.message(e)}}
  end

  defp ingest_by_type(%{type: :source_files} = item, workspace_name) do
    # Read and process source file
    case File.read(item.path) do
      {:ok, content} ->
        # Store in Mneme as a document
        {:ok, doc} =
          Mneme.ingest(Path.basename(item.path), content,
            source_type: "artifact",
            source_id: item.path,
            owner_id: workspace_scope_id(workspace_name)
          )

        # Process through pipeline
        {:ok, _run} = Mneme.process(doc)

        # Return entry IDs (in a real implementation, we'd get these from Mneme)
        {:ok, [doc.id]}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ingest_by_type(%{type: :documentation} = item, workspace_name) do
    case File.read(item.path) do
      {:ok, content} ->
        result =
          Mneme.ingest(Path.basename(item.path), content,
            source_type: "manual",
            source_id: item.path,
            owner_id: workspace_scope_id(workspace_name)
          )

        case result do
          {:ok, :unchanged} ->
            {:ok, []}

          {:ok, doc} ->
            {:ok, _run} = Mneme.process(doc)
            {:ok, [doc.id]}

          {:error, _} = error ->
            error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ingest_by_type(%{type: :coding_agent_history} = item, workspace_name) do
    case File.read(item.path) do
      {:ok, _content} ->
        result =
          Mneme.learn(
            scope_id: workspace_scope_id(workspace_name),
            sources: [item.path]
          )

        case result do
          {:ok, entries} -> {:ok, Enum.map(entries, & &1.id)}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ingest_by_type(%{type: :git_history} = _item, workspace_name) do
    # Use Mneme's git learning capabilities
    result =
      Mneme.learn(
        scope_id: workspace_scope_id(workspace_name),
        sources: [:git]
      )

    case result do
      {:ok, entries} -> {:ok, Enum.map(entries, & &1.id)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ingest_by_type(item, workspace_name) do
    # Generic fallback - store as a knowledge entry
    case File.read(item.path) do
      {:ok, content} ->
        result =
          Mneme.remember(content,
            scope_id: workspace_scope_id(workspace_name),
            entry_type: to_string(item.type),
            source: item.path
          )

        case result do
          {:ok, entry} -> {:ok, [entry.id]}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Generate a deterministic UUID scope for a workspace name."
  def workspace_scope_id(workspace_name) do
    # Generate a deterministic UUID for the workspace scope
    # In production, you might want to store this in a workspace record
    base = "workspace:#{workspace_name}"

    <<uuid::128>> = :crypto.hash(:md5, base)

    uuid
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(32, "0")
    |> then(fn hex ->
      <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4), e::binary-size(12)>> = hex
      "#{a}-#{b}-#{c}-#{d}-#{e}"
    end)
  end

  defp coding_agent_module do
    Mneme.Learner.CodingAgent
  end
end
