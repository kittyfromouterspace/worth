defmodule Worth.Skill.Service do
  @skills_dir "~/.worth/skills"
  @core_skills_dir Path.join(:code.priv_dir(:worth), "core_skills")

  def list(opts \\ []) do
    core = list_core_skills()
    user = list_user_skills()

    all = core ++ user

    workspace = opts[:workspace]

    if workspace do
      filter_for_workspace(all, workspace)
    else
      all
    end
  end

  def read(name) do
    case resolve_skill_path(name) do
      nil -> {:error, "Skill '#{name}' not found"}
      dir -> Worth.Skill.Parser.parse_file(Path.join(dir, "SKILL.md"))
    end
  end

  def read_body(name) do
    case read(name) do
      {:ok, skill} -> {:ok, skill.body}
      error -> error
    end
  end

  def install(source, opts \\ [])

  def install(%{type: :local, path: path}, _opts) do
    name = Path.basename(path)
    dest = Path.join([Path.expand(@skills_dir), name])

    if File.dir?(dest) do
      {:error, "Skill '#{name}' already installed"}
    else
      case File.cp_r(path, dest) do
        {:ok, _} ->
          Worth.Skill.Registry.refresh()
          {:ok, name}

        {:error, reason, _} ->
          {:error, "Failed to install: #{reason}"}
      end
    end
  end

  def install(%{type: :content, name: name, content: content}, opts) do
    trust_level = Keyword.get(opts, :trust_level, :learned)
    provenance = Keyword.get(opts, :provenance, :agent)

    dest = Path.join([Path.expand(@skills_dir), name])
    File.mkdir_p!(dest)

    skill_md =
      Worth.Skill.Parser.to_frontmatter_string(%{
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
          created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
          created_by: Atom.to_string(provenance),
          version: 1,
          refinement_count: 0,
          success_rate: 0.0,
          usage_count: 0,
          last_used: nil,
          last_refined: nil,
          superseded_by: nil,
          superseded_from: [],
          feedback_summary: nil
        }
      })

    File.write!(Path.join(dest, "SKILL.md"), skill_md)
    Worth.Skill.Registry.refresh()
    {:ok, name}
  end

  def remove(name) do
    path = resolve_skill_path(name)

    cond do
      path == nil ->
        {:error, "Skill '#{name}' not found"}

      String.starts_with?(path, @core_skills_dir) ->
        {:error, "Cannot remove core skill '#{name}'"}

      true ->
        case File.rm_rf(path) do
          {:ok, _} ->
            Worth.Skill.Registry.refresh()
            {:ok, name}

          {:error, reason, _} ->
            {:error, "Failed to remove: #{reason}"}
        end
    end
  end

  def exists?(name) do
    resolve_skill_path(name) != nil
  end

  def record_usage(name, success?) do
    case read(name) do
      {:ok, skill} ->
        evolution = skill.evolution
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        usage_count = (evolution[:usage_count] || 0) + 1

        success_count =
          (evolution[:success_rate] || 0.0) * (usage_count - 1) + if(success?, do: 1.0, else: 0.0)

        success_rate = Float.round(success_count / usage_count, 4)

        updated = %{
          skill
          | evolution:
              Map.merge(evolution, %{
                usage_count: usage_count,
                success_rate: success_rate,
                last_used: now
              })
        }

        path = resolve_skill_path(name)
        File.write!(Path.join(path, "SKILL.md"), Worth.Skill.Parser.to_frontmatter_string(updated))
        Worth.Skill.Registry.refresh()
        {:ok, updated}

      error ->
        error
    end
  end

  defp list_core_skills do
    if File.dir?(@core_skills_dir) do
      @core_skills_dir
      |> File.ls!()
      |> Enum.filter(&File.dir?(Path.join(@core_skills_dir, &1)))
      |> Enum.map(fn name ->
        load_metadata(Path.join(@core_skills_dir, name), name, :core)
      end)
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp list_user_skills do
    dir = Path.expand(@skills_dir)
    learned_dir = Path.join(dir, "learned")

    skills =
      if File.dir?(dir) do
        dir
        |> File.ls!()
        |> Enum.filter(&File.dir?(Path.join(dir, &1)))
        |> Enum.reject(&(&1 == "learned"))
        |> Enum.map(fn name ->
          load_metadata(Path.join(dir, name), name, :installed)
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
          load_metadata(Path.join(learned_dir, name), name, :learned)
        end)
      else
        []
      end

    skills ++ learned
  end

  defp load_metadata(dir, name, default_trust) do
    skill_md = Path.join(dir, "SKILL.md")

    if File.exists?(skill_md) do
      case Worth.Skill.Parser.parse_file(skill_md) do
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
    else
      nil
    end
  end

  defp resolve_skill_path(name) do
    core_path = Path.join(@core_skills_dir, name)
    user_path = Path.join(Path.expand(@skills_dir), name)
    learned_path = Path.join([Path.expand(@skills_dir), "learned", name])

    cond do
      File.dir?(core_path) -> core_path
      File.dir?(user_path) -> user_path
      File.dir?(learned_path) -> learned_path
      true -> nil
    end
  end

  defp filter_for_workspace(skills, workspace) do
    ws_path = Worth.Workspace.Service.resolve_path(workspace)
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
      else
        nil
      end

    case active do
      nil ->
        skills

      active_set ->
        Enum.filter(skills, fn s ->
          s.trust_level == :core or MapSet.member?(active_set, s.name)
        end)
    end
  end
end
