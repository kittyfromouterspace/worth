defmodule Worth.Workspace.Scanner do
  @moduledoc """
  Scans a workspace directory to detect new, modified, and deleted content.

  Compares current filesystem state with the index to determine what needs
  to be learned or re-indexed.
  """

  require Logger

  alias Worth.Workspace.IndexEntry
  alias Worth.Repo

  import Ecto.Query

  @doc """
  Scans a workspace and returns a report of what needs indexing.

  Returns:
    {:ok, %{
      workspace: String.t(),
      new: [%{path: String.t(), type: atom(), size: integer(), modified: DateTime.t()}],
      modified: [%{path: String.t(), type: atom(), old_hash: String.t(), new_hash: String.t()}],
      deleted: [%{path: String.t(), type: atom()}],
      unchanged: [%{path: String.t(), type: atom()}],
      total_new_bytes: integer(),
      total_modified_bytes: integer()
    }}
  """
  def scan(workspace_name, opts \\ []) do
    workspace_path = Worth.Workspace.Service.resolve_path(workspace_name)

    if File.dir?(workspace_path) do
      # Get all current index entries for this workspace
      existing_entries =
        from(e in IndexEntry, where: e.workspace_name == ^workspace_name)
        |> Repo.all()
        |> Map.new(fn e -> {e.source_path, e} end)

      # Scan different content types
      discoveries =
        []
        |> scan_git_history(workspace_path, opts)
        |> scan_coding_agent_history(workspace_path, opts)
        |> scan_source_files(workspace_path, opts)
        |> scan_documentation(workspace_path, opts)
        |> scan_workspace_skills(workspace_path, opts)

      # Compare discoveries with existing index
      {new, modified, unchanged} = compare_with_index(discoveries, existing_entries)

      # Find deleted items (in index but not on disk)
      discovered_paths = MapSet.new(discoveries, & &1.path)

      deleted =
        existing_entries
        |> Enum.reject(fn {path, _entry} -> MapSet.member?(discovered_paths, path) end)
        |> Enum.map(fn {path, entry} -> %{path: path, type: String.to_atom(entry.source_type)} end)

      total_new = Enum.reduce(new, 0, fn item, acc -> acc + (item.size || 0) end)
      total_modified = Enum.reduce(modified, 0, fn item, acc -> acc + (item.new_size || 0) end)

      report = %{
        workspace: workspace_name,
        workspace_path: workspace_path,
        new: new,
        modified: modified,
        deleted: deleted,
        unchanged: unchanged,
        total_new_bytes: total_new,
        total_modified_bytes: total_modified,
        new_count: length(new),
        modified_count: length(modified),
        deleted_count: length(deleted),
        has_changes: new != [] or modified != [] or deleted != []
      }

      {:ok, report}
    else
      {:error, :workspace_not_found}
    end
  end

  @doc """
  Returns true if the workspace has never been indexed (is "new").
  """
  def new_workspace?(workspace_name) do
    count =
      from(e in IndexEntry, where: e.workspace_name == ^workspace_name)
      |> Repo.aggregate(:count, :id)

    count == 0
  end

  @doc """
  Returns summary statistics about a workspace's indexed content.
  """
  def index_stats(workspace_name) do
    stats =
      from(e in IndexEntry,
        where: e.workspace_name == ^workspace_name,
        group_by: e.source_type,
        select: {e.source_type, count(e.id), sum(e.file_size)}
      )
      |> Repo.all()
      |> Map.new(fn {type, count, size} ->
        {String.to_atom(type), %{count: count, total_bytes: size || 0}}
      end)

    total_entries =
      from(e in IndexEntry, where: e.workspace_name == ^workspace_name)
      |> Repo.aggregate(:count, :id)

    last_indexed =
      from(e in IndexEntry,
        where: e.workspace_name == ^workspace_name,
        order_by: [desc: e.indexed_at],
        limit: 1,
        select: e.indexed_at
      )
      |> Repo.one()

    %{
      workspace: workspace_name,
      total_entries: total_entries,
      by_type: stats,
      last_indexed_at: last_indexed
    }
  end

  # Private functions

  defp scan_git_history(acc, workspace_path, _opts) do
    git_dir = Path.join(workspace_path, ".git")

    if File.dir?(git_dir) do
      log_path = Path.join(workspace_path, ".worth/git_history.txt")

      entries =
        if File.exists?(log_path) do
          [{:git_history, log_path}]
        else
          [{:git_history, Path.join(workspace_path, ".git")}]
        end

      Enum.reduce(entries, acc, fn {type, path}, acc ->
        case file_info(path) do
          {:ok, info} -> [Map.put(info, :type, type) | acc]
          :error -> acc
        end
      end)
    else
      acc
    end
  end

  defp scan_coding_agent_history(acc, workspace_path, _opts) do
    agent_dirs = [
      {".claude", "claude"},
      {".anthropic", "claude"},
      {".opencode", "opencode"},
      {".worth/opencode", "opencode"},
      {".codex", "codex"},
      {".gemini", "gemini"}
    ]

    agent_dirs
    |> Enum.flat_map(fn {dir, agent} ->
      full = Path.join(workspace_path, dir)
      if File.dir?(full), do: [{full, agent}], else: []
    end)
    |> Enum.flat_map(fn {dir, agent} ->
      dir
      |> scan_directory()
      |> Enum.map(&Map.put(&1, :agent, agent))
    end)
    |> Enum.reduce(acc, fn info, acc ->
      [Map.put(info, :type, :coding_agent_history) | acc]
    end)
  end

  defp scan_source_files(acc, workspace_path, opts) do
    max_files = Keyword.get(opts, :max_source_files, 1000)

    extensions = [
      ".ex",
      ".exs",
      ".rb",
      ".py",
      ".js",
      ".ts",
      ".jsx",
      ".tsx",
      ".java",
      ".go",
      ".rs",
      ".c",
      ".cpp",
      ".h",
      ".hpp",
      ".swift",
      ".kt",
      ".scala",
      ".php",
      ".cs",
      ".fs",
      ".fsx",
      ".ml",
      ".mli",
      ".elm",
      ".clj",
      ".cljs"
    ]

    workspace_path
    |> scan_for_extensions(extensions, max_files)
    |> Enum.reduce(acc, fn info, acc ->
      [Map.put(info, :type, :source_files) | acc]
    end)
  end

  defp scan_documentation(acc, workspace_path, _opts) do
    doc_files = [
      "README.md",
      "README",
      "CONTRIBUTING.md",
      "CHANGELOG.md",
      "ARCHITECTURE.md",
      "AGENTS.md",
      "IDENTITY.md",
      "docs/",
      "doc/"
    ]

    doc_files
    |> Enum.flat_map(fn pattern ->
      full_path = Path.join(workspace_path, pattern)

      cond do
        File.regular?(full_path) ->
          case file_info(full_path) do
            {:ok, info} -> [info]
            :error -> []
          end

        File.dir?(full_path) ->
          scan_directory(full_path)

        true ->
          []
      end
    end)
    |> Enum.reduce(acc, fn info, acc ->
      [Map.put(info, :type, :documentation) | acc]
    end)
  end

  defp scan_workspace_skills(acc, workspace_path, _opts) do
    # Look for skills in workspace .worth/skills/ directory
    worth_skills_dir = Path.join(workspace_path, ".worth/skills")

    # Also look for skills in workspace root skills/ directory
    root_skills_dir = Path.join(workspace_path, "skills")

    skill_dirs =
      [worth_skills_dir, root_skills_dir]
      |> Enum.filter(&File.dir?/1)

    skill_dirs
    |> Enum.flat_map(fn dir ->
      # Find all SKILL.md files in skill directories
      dir
      |> File.ls!()
      |> Enum.map(&Path.join(dir, &1))
      |> Enum.filter(&File.dir?/1)
      |> Enum.map(&Path.join(&1, "SKILL.md"))
      |> Enum.filter(&File.regular?/1)
    end)
    |> Enum.map(&file_info/1)
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, info} -> info end)
    |> Enum.reduce(acc, fn info, acc ->
      [Map.put(info, :type, :workspace_skills) | acc]
    end)
  end

  defp scan_directory(dir_path) do
    dir_path
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&file_info/1)
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, info} -> info end)
  rescue
    _ -> []
  end

  defp scan_for_extensions(dir_path, extensions, max_files) do
    extensions
    |> Enum.flat_map(fn ext ->
      dir_path
      |> Path.join("**/*#{ext}")
      |> Path.wildcard()
    end)
    |> Enum.take(max_files)
    |> Enum.map(&file_info/1)
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, info} -> info end)
  rescue
    _ -> []
  end

  defp file_info(path) do
    case File.stat(path) do
      {:ok, stat} ->
        content = File.read!(path)
        hash = IndexEntry.calculate_hash(content)

        # stat.mtime is an Erlang datetime tuple, convert it properly
        modified =
          case stat.mtime do
            {{y, m, d}, {h, min, s}} ->
              NaiveDateTime.from_erl!({{y, m, d}, {h, min, s}})

            unix_timestamp when is_integer(unix_timestamp) ->
              DateTime.from_unix!(unix_timestamp)
          end

        {:ok, %{path: path, size: stat.size, modified: modified, hash: hash}}

      {:error, _} ->
        :error
    end
  end

  defp compare_with_index(discoveries, existing_entries) do
    discoveries
    |> Enum.reduce({[], [], []}, fn discovered, {new_acc, modified_acc, unchanged_acc} ->
      case Map.get(existing_entries, discovered.path) do
        nil ->
          new_item = %{
            path: discovered.path,
            type: discovered.type,
            size: discovered.size,
            modified: discovered.modified,
            hash: discovered.hash
          }

          {[new_item | new_acc], modified_acc, unchanged_acc}

        entry ->
          if entry.content_hash != discovered.hash do
            modified_item = %{
              path: discovered.path,
              type: discovered.type,
              old_hash: entry.content_hash,
              new_hash: discovered.hash,
              old_size: entry.file_size,
              new_size: discovered.size,
              last_indexed: entry.indexed_at
            }

            {new_acc, [modified_item | modified_acc], unchanged_acc}
          else
            unchanged_item = %{path: discovered.path, type: discovered.type, indexed_at: entry.indexed_at}
            {new_acc, modified_acc, [unchanged_item | unchanged_acc]}
          end
      end
    end)
  end
end
