defmodule Worth.Skill.Versioner do
  @history_dir ".worth/history"

  def save_version(skill_name) do
    case Worth.Skill.Service.read(skill_name) do
      {:ok, skill} ->
        version = skill.evolution[:version] || 1
        dir = history_dir(skill_name)
        File.mkdir_p!(dir)

        filename = "v#{version}.md"
        path = Path.join(dir, filename)

        if not File.exists?(path) do
          content = Worth.Skill.Parser.to_frontmatter_string(skill)
          File.write!(path, content)
          {:ok, path}
        else
          {:ok, :already_saved}
        end

      error ->
        error
    end
  end

  def list_versions(skill_name) do
    dir = history_dir(skill_name)

    if File.dir?(dir) do
      versions =
        dir
        |> File.ls!()
        |> Enum.filter(&String.starts_with?(&1, "v"))
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.map(fn filename ->
          version = filename |> String.trim_trailing(".md") |> String.trim_leading("v") |> String.to_integer()
          path = Path.join(dir, filename)
          stat = File.stat!(path)
          {version, %{path: path, size: stat.size, modified: stat.mtime}}
        end)
        |> Enum.sort_by(fn {v, _} -> v end, :desc)

      {:ok, versions}
    else
      {:ok, []}
    end
  end

  def rollback(skill_name, target_version) do
    dir = history_dir(skill_name)
    path = Path.join(dir, "v#{target_version}.md")

    with {:ok, _} <- Worth.Skill.Service.read(skill_name),
         true <- File.exists?(path),
         {:ok, _} <- Worth.Skill.Parser.parse_file(path) do
      save_version(skill_name)

      case File.read(path) do
        {:ok, content} ->
          skill_dir = resolve_skill_dir(skill_name)

          if skill_dir do
            File.write!(Path.join(skill_dir, "SKILL.md"), content)
            Worth.Skill.Registry.refresh()
            {:ok, %{name: skill_name, rolled_back_to: target_version}}
          else
            {:error, "Skill directory not found"}
          end

        {:error, reason} ->
          {:error, "Failed to read version file: #{reason}"}
      end
    else
      false -> {:error, "Version v#{target_version} not found for '#{skill_name}'"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp history_dir(skill_name) do
    case resolve_skill_dir(skill_name) do
      nil -> Path.join("/tmp", "worth-skill-history-#{skill_name}")
      dir -> Path.join(dir, @history_dir)
    end
  end

  defp resolve_skill_dir(name) do
    core = Path.join(:code.priv_dir(:worth), "core_skills")
    user = Path.join(Path.expand("~/.worth/skills"), name)
    learned = Path.join(Path.expand("~/.worth/skills/learned"), name)

    cond do
      File.dir?(Path.join(core, name)) -> Path.join(core, name)
      File.dir?(user) -> user
      File.dir?(learned) -> learned
      true -> nil
    end
  end
end
