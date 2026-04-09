defmodule Worth.Skill.Versioner do
  alias Worth.Skill.Paths

  @history_dir ".worth/history"

  def save_version(skill_name) do
    with {:ok, skill} <- Worth.Skill.Service.read(skill_name),
         dir when is_binary(dir) <- history_dir(skill_name) do
      version = skill.evolution[:version] || 1
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
    else
      {:error, _} = error -> error
    end
  end

  def list_versions(skill_name) do
    case history_dir(skill_name) do
      {:error, _} = error -> error
      dir -> list_versions_from_dir(dir)
    end
  end

  defp list_versions_from_dir(dir) do
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
    with dir when is_binary(dir) <- history_dir(skill_name),
         path = Path.join(dir, "v#{target_version}.md"),
         {:ok, _} <- Worth.Skill.Service.read(skill_name),
         true <- File.exists?(path),
         {:ok, _} <- Worth.Skill.Parser.parse_file(path) do
      save_version(skill_name)

      case File.read(path) do
        {:ok, content} ->
          case Paths.resolve(skill_name) do
            nil ->
              {:error, "Skill directory not found"}

            skill_dir ->
              File.write!(Path.join(skill_dir, "SKILL.md"), content)
              Worth.Skill.Registry.refresh()
              {:ok, %{name: skill_name, rolled_back_to: target_version}}
          end

        {:error, reason} ->
          {:error, "Failed to read version file: #{reason}"}
      end
    else
      {:error, _} = error -> error
      false -> {:error, "Version v#{target_version} not found for '#{skill_name}'"}
    end
  end

  defp history_dir(skill_name) do
    case Paths.resolve(skill_name) do
      nil -> {:error, :skill_not_found}
      dir -> Path.join(dir, @history_dir)
    end
  end
end
