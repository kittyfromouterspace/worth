defmodule Worth.Skill.Service do
  @moduledoc """
  Skill management service backed by the database.

  Reads skills from the database with fallback to filesystem for core skills
  that haven't been migrated yet.
  """

  alias Worth.Repo
  alias Worth.Skill.Parser
  alias Worth.Skill.Paths
  alias Worth.Skill.Schema
  alias Worth.Workspace.Service

  require Logger

  # --- Public API ---

  @doc """
  List skills for a workspace.
  Returns skills from DB (global + workspace-scoped) with filesystem fallback.
  """
  def list(opts \\ []) do
    workspace = opts[:workspace] || current_workspace()
    db_skills = list_from_db(workspace)

    # If DB is empty, fall back to filesystem (migration not run yet)
    if db_skills == [] do
      list_from_filesystem(workspace)
    else
      db_skills
    end
  end

  @doc """
  Read a single skill by name.
  Tries DB first, falls back to filesystem.
  """
  def read(name, opts \\ []) do
    workspace = opts[:workspace] || current_workspace()

    try do
      case Schema.find(name, workspace) do
        nil -> read_from_filesystem(name, workspace)
        skill -> {:ok, db_skill_to_map(skill)}
      end
    rescue
      _ -> read_from_filesystem(name, workspace)
    catch
      :exit, _ -> read_from_filesystem(name, workspace)
    end
  end

  @doc """
  Read just the body of a skill.
  """
  def read_body(name, opts \\ []) do
    case read(name, opts) do
      {:ok, skill} -> {:ok, skill.body}
      error -> error
    end
  end

  @doc """
  Install a skill from a source.
  """
  def install(source, opts \\ [])

  def install(%{type: :local, path: path}, opts) do
    workspace = opts[:workspace] || current_workspace()
    name = Path.basename(path)

    # Read from filesystem source
    case Parser.parse_file(Path.join(path, "SKILL.md")) do
      {:ok, skill} ->
        attrs = skill_map_to_db_attrs(skill, workspace, :installed)
        do_insert(attrs, name)

      error ->
        error
    end
  end

  def install(%{type: :content, name: name, content: content}, opts) do
    workspace = opts[:workspace] || current_workspace()
    trust_level = Keyword.get(opts, :trust_level, :learned)
    provenance = Keyword.get(opts, :provenance, :agent)

    skill = %{
      name: name,
      description: Keyword.get(opts, :description, "Agent-created skill"),
      body: content,
      loading: :on_demand,
      model_tier: :any,
      provenance: provenance,
      trust_level: trust_level,
      license: nil,
      allowed_tools: nil,
      metadata: %{},
      evolution: %{
        created_at: DateTime.to_iso8601(DateTime.utc_now()),
        created_by: Atom.to_string(provenance),
        version: 1,
        refinement_count: 0,
        success_count: 0,
        success_rate: 0.0,
        usage_count: 0,
        last_used: nil,
        last_refined: nil,
        superseded_by: nil,
        superseded_from: [],
        feedback_summary: nil
      }
    }

    case Worth.Skill.Validator.validate(skill) do
      {:ok, _} ->
        attrs = skill_map_to_db_attrs(skill, workspace, trust_level)
        do_insert(attrs, name)

      {:error, errors} ->
        {:error, "Validation failed: #{Enum.join(errors, ", ")}"}
    end
  end

  @doc """
  Remove a skill by name.
  """
  def remove(name, opts \\ []) do
    workspace = opts[:workspace] || current_workspace()

    # Check if it's a core skill first
    if core_skill?(name, workspace) do
      {:error, "Cannot remove core skill '#{name}'"}
    else
      try do
        import Ecto.Query

        query =
          from(s in Schema,
            where: s.name == ^name and s.workspace == ^workspace
          )

        case Repo.delete_all(query) do
          {1, _} ->
            Worth.Skill.Registry.refresh()
            {:ok, name}

          {0, _} ->
            # Not in DB, try filesystem
            remove_from_filesystem(name, workspace)
        end
      rescue
        _ -> remove_from_filesystem(name, workspace)
      catch
        :exit, _ -> remove_from_filesystem(name, workspace)
      end
    end
  end

  defp core_skill?(name, workspace) do
    case Schema.find(name, workspace) do
      nil -> Paths.core?(name)
      skill -> skill.trust_level == "core"
    end
  rescue
    _ -> Paths.core?(name)
  catch
    :exit, _ -> Paths.core?(name)
  end

  defp remove_from_filesystem(name, workspace) do
    case Paths.resolve(name, workspace) do
      nil ->
        {:error, "Skill '#{name}' not found"}

      path ->
        case File.rm_rf(path) do
          {:ok, _} ->
            Worth.Skill.Registry.refresh()
            {:ok, name}

          {:error, reason, _} ->
            {:error, "Failed to remove: #{reason}"}
        end
    end
  end

  @doc """
  Check if a skill exists.
  """
  def exists?(name, opts \\ []) do
    workspace = opts[:workspace] || current_workspace()

    try do
      Schema.find(name, workspace) != nil
    rescue
      _ ->
        case read_from_filesystem(name, workspace) do
          {:error, _} -> false
          _ -> true
        end
    catch
      :exit, _ ->
        case read_from_filesystem(name, workspace) do
          {:error, _} -> false
          _ -> true
        end
    end
  end

  @doc """
  Record skill usage and update statistics.
  """
  def record_usage(name, success?, opts \\ []) do
    workspace = opts[:workspace] || current_workspace()

    try do
      case Schema.find(name, workspace) do
        nil ->
          {:error, "Skill '#{name}' not found"}

        skill ->
          evolution = skill.evolution || %{}
          usage_count = (evolution["usage_count"] || 0) + 1
          success_count = (evolution["success_count"] || 0) + if(success?, do: 1, else: 0)
          success_rate = Float.round(success_count / usage_count, 4)

          updated_evolution =
            Map.merge(evolution, %{
              "usage_count" => usage_count,
              "success_count" => success_count,
              "success_rate" => success_rate,
              "last_used" => DateTime.to_iso8601(DateTime.utc_now())
            })

          changeset = Schema.changeset(skill, %{evolution: updated_evolution})

          case Repo.update(changeset) do
            {:ok, updated} ->
              Worth.Skill.Registry.refresh()
              {:ok, db_skill_to_map(updated)}

            {:error, changeset} ->
              {:error, "Failed to record usage: #{inspect(changeset.errors)}"}
          end
      end
    rescue
      _ -> record_usage_fs(name, success?, opts)
    catch
      :exit, _ -> record_usage_fs(name, success?, opts)
    end
  end

  # --- AgentFS Materializer API ---

  @doc """
  List skills for AgentFS materialization.
  Returns skills as %{name: ..., content: ...} maps for the given workspace.
  """
  def materialize_for_agentfs(workspace) do
    [workspace: workspace]
    |> list()
    |> Enum.map(fn skill ->
      %{
        name: skill.name,
        content: skill.body
      }
    end)
  end

  @doc """
  Sync back skills created by an agent during a session.
  """
  def sync_back_from_agentfs(skills_data, workspace) do
    for %{name: name, content: content, is_new: true} <- skills_data do
      install(
        %{type: :content, name: name, content: content},
        workspace: workspace,
        trust_level: :learned,
        provenance: :agent,
        description: "Agent-created skill during session"
      )
    end

    :ok
  end

  # --- Private helpers ---

  defp list_from_db(workspace) do
    workspace
    |> Schema.for_workspace()
    |> Enum.map(&db_skill_to_map/1)
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  defp list_from_filesystem(workspace) do
    core = list_core_skills_fs()
    user = list_workspace_skills_fs(workspace)
    all = core ++ user

    if workspace do
      filter_for_workspace(all, workspace)
    else
      all
    end
  end

  defp read_from_filesystem(name, workspace) do
    case Paths.resolve(name, workspace) do
      nil -> {:error, "Skill '#{name}' not found"}
      dir -> Parser.parse_file(Path.join(dir, "SKILL.md"))
    end
  end

  defp do_insert(attrs, name) do
    case %Schema{}
         |> Schema.changeset(attrs)
         |> Repo.insert() do
      {:ok, _} ->
        Worth.Skill.Registry.refresh()
        {:ok, name}

      {:error, %{errors: [name: {"has already been taken", _}]}} ->
        {:error, "Skill '#{name}' already installed in this workspace"}

      {:error, changeset} ->
        {:error, "Failed to install: #{inspect(changeset.errors)}"}
    end
  end

  defp skill_map_to_db_attrs(skill, workspace, trust_level) do
    %{
      name: skill.name,
      description: skill.description || "",
      body: skill.body || "",
      license: skill.license,
      compatibility: skill.compatibility,
      metadata: skill.metadata || %{},
      loading: Atom.to_string(skill.loading || :on_demand),
      model_tier: Atom.to_string(skill.model_tier || :any),
      provenance: Atom.to_string(skill.provenance || :human),
      trust_level: Atom.to_string(trust_level),
      allowed_tools: skill.allowed_tools,
      evolution: evolution_to_map(skill.evolution),
      workspace: workspace,
      installed_at: DateTime.utc_now()
    }
  end

  defp db_skill_to_map(skill) do
    evolution = skill.evolution || %{}

    %{
      name: skill.name,
      description: skill.description || "",
      body: skill.body,
      license: skill.license,
      compatibility: skill.compatibility,
      metadata: skill.metadata || %{},
      loading: parse_loading(skill.loading),
      model_tier: parse_model_tier(skill.model_tier),
      provenance: parse_provenance(skill.provenance),
      trust_level: parse_trust_level(skill.trust_level),
      allowed_tools: skill.allowed_tools,
      evolution: %{
        created_at: evolution["created_at"],
        created_by: evolution["created_by"],
        version: evolution["version"] || 1,
        refinement_count: evolution["refinement_count"] || 0,
        success_count: evolution["success_count"] || 0,
        success_rate: evolution["success_rate"] || 0.0,
        usage_count: evolution["usage_count"] || 0,
        last_used: evolution["last_used"],
        last_refined: evolution["last_refined"],
        superseded_by: evolution["superseded_by"],
        superseded_from: evolution["superseded_from"] || [],
        feedback_summary: evolution["feedback_summary"]
      },
      workspace: skill.workspace
    }
  end

  defp evolution_to_map(evolution) when is_map(evolution) do
    Map.new(evolution, fn {k, v} -> {to_string(k), v} end)
  end

  defp parse_loading("always"), do: :always
  defp parse_loading("on_demand"), do: :on_demand
  defp parse_loading(_), do: :on_demand

  defp parse_model_tier("primary"), do: :primary
  defp parse_model_tier("lightweight"), do: :lightweight
  defp parse_model_tier(_), do: :any

  defp parse_provenance("agent"), do: :agent
  defp parse_provenance("hybrid"), do: :hybrid
  defp parse_provenance(_), do: :human

  defp parse_trust_level("core"), do: :core
  defp parse_trust_level("installed"), do: :installed
  defp parse_trust_level("learned"), do: :learned
  defp parse_trust_level(_), do: :unverified

  # --- Filesystem fallback (for migration period) ---

  defp list_core_skills_fs do
    dir = Paths.core_dir()

    if File.dir?(dir) do
      dir
      |> File.ls!()
      |> Enum.filter(&File.dir?(Path.join(dir, &1)))
      |> Enum.map(fn name ->
        load_metadata_fs(Path.join(dir, name), name, :core)
      end)
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp list_workspace_skills_fs(workspace) do
    dir = Paths.user_dir(workspace)
    learned_dir = Paths.learned_dir(workspace)

    skills =
      if File.dir?(dir) do
        dir
        |> File.ls!()
        |> Enum.filter(&File.dir?(Path.join(dir, &1)))
        |> Enum.reject(&(&1 == "learned"))
        |> Enum.map(fn name ->
          load_metadata_fs(Path.join(dir, name), name, :installed)
        end)
      else
        []
      end

    learned =
      if File.dir?(learned_dir) do
        learned_dir
        |> File.ls!()
        |> Enum.filter(&File.dir?(Path.join(learned_dir, &1)))
        |> Enum.map(fn name ->
          load_metadata_fs(Path.join(learned_dir, name), name, :learned)
        end)
      else
        []
      end

    skills ++ learned
  end

  defp load_metadata_fs(dir, name, default_trust) do
    skill_md = Path.join(dir, "SKILL.md")

    if File.exists?(skill_md) do
      case Parser.parse_file(skill_md) do
        {:ok, skill} ->
          %{
            name: skill.name || name,
            description: skill.description || "",
            loading: skill.loading,
            trust_level: skill.trust_level || default_trust,
            provenance: skill.provenance,
            path: dir,
            body_length: String.length(skill.body || "")
          }

        _ ->
          %{
            name: name,
            description: "(parse error)",
            loading: :on_demand,
            trust_level: default_trust,
            provenance: :human,
            path: dir,
            body_length: 0
          }
      end
    end
  end

  defp filter_for_workspace(skills, workspace) do
    ws_path = Service.resolve_path(workspace)
    manifest_path = Path.join(ws_path, ".worth/skills.json")

    active =
      if File.exists?(manifest_path) do
        case File.read(manifest_path) do
          {:ok, json} ->
            case Jason.decode(json) do
              {:ok, %{"active" => active}} -> MapSet.new(active)
              _ -> nil
            end

          _ ->
            nil
        end
      end

    case active do
      nil -> skills
      active_set -> Enum.filter(skills, &(&1.trust_level == :core or MapSet.member?(active_set, &1.name)))
    end
  end

  defp record_usage_fs(name, success?, opts) do
    workspace = opts[:workspace] || current_workspace()

    case read_from_filesystem(name, workspace) do
      {:ok, skill} ->
        evolution = skill.evolution
        now = DateTime.to_iso8601(DateTime.utc_now())

        usage_count = (evolution[:usage_count] || 0) + 1
        success_count = (evolution[:success_count] || 0) + if(success?, do: 1, else: 0)
        success_rate = Float.round(success_count / usage_count, 4)

        updated = %{
          skill
          | evolution:
              Map.merge(evolution, %{
                usage_count: usage_count,
                success_count: success_count,
                success_rate: success_rate,
                last_used: now
              })
        }

        case Paths.resolve(name, workspace) do
          nil ->
            {:error, "Skill '#{name}' not found"}

          path ->
            File.write!(Path.join(path, "SKILL.md"), Parser.to_frontmatter_string(updated))
            Worth.Skill.Registry.refresh()
            {:ok, updated}
        end

      error ->
        error
    end
  end

  defp current_workspace do
    Worth.Config.get(:current_workspace, "personal")
  end
end
