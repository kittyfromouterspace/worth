defmodule Worth.Skill.Migration do
  @moduledoc """
  One-time migration utility to import filesystem-based skills into the database.

  Run via: `mix run -e "Worth.Skill.Migration.run()"`

  This reads all skills from:
  - priv/core_skills/ (core)
  - ~/.worth/skills/ (installed)
  - ~/.worth/skills/learned/ (learned)

  And inserts them into the `skills` table.
  """

  alias Worth.Repo
  alias Worth.Skill.Parser
  alias Worth.Skill.Paths
  alias Worth.Skill.Schema

  require Logger

  def run do
    Logger.info("Starting skill migration from filesystem to database...")

    migrated =
      []
      |> migrate_core_skills()
      |> migrate_workspace_skills()

    Logger.info("Migration complete. Migrated #{length(migrated)} skills.")
    {:ok, migrated}
  end

  defp migrate_core_skills(acc) do
    dir = Paths.core_dir()

    if File.dir?(dir) do
      skills =
        dir
        |> File.ls!()
        |> Enum.filter(&File.dir?(Path.join(dir, &1)))
        |> Enum.map(fn name ->
          path = Path.join(dir, name)
          parse_and_insert(path, name, "global", :core)
        end)
        |> Enum.reject(&is_nil/1)

      acc ++ skills
    else
      acc
    end
  end

  defp migrate_workspace_skills(acc) do
    workspaces = Worth.Workspace.Service.list()

    for workspace <- workspaces, reduce: acc do
      acc ->
        acc = migrate_workspace_dir(acc, workspace, Paths.user_dir(workspace), :installed)
        migrate_workspace_dir(acc, workspace, Paths.learned_dir(workspace), :learned)
    end
  end

  defp migrate_workspace_dir(acc, workspace, dir, trust_level) do
    if File.dir?(dir) do
      skills =
        dir
        |> File.ls!()
        |> Enum.filter(&File.dir?(Path.join(dir, &1)))
        |> Enum.reject(&(&1 == "learned"))
        |> Enum.map(fn name ->
          path = Path.join(dir, name)
          parse_and_insert(path, name, workspace, trust_level)
        end)
        |> Enum.reject(&is_nil/1)

      acc ++ skills
    else
      acc
    end
  end

  defp parse_and_insert(path, name, workspace, trust_level) do
    skill_md = Path.join(path, "SKILL.md")

    if File.exists?(skill_md) do
      case Parser.parse_file(skill_md) do
        {:ok, skill} ->
          attrs = %{
            name: skill.name || name,
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
            source_path: path
          }

          case %Schema{}
               |> Schema.changeset(attrs)
               |> Repo.insert() do
            {:ok, record} ->
              Logger.info("Migrated skill: #{record.name} (#{record.trust_level}) in #{record.workspace}")
              record

            {:error, changeset} ->
              Logger.warning("Failed to migrate skill #{name}: #{inspect(changeset.errors)}")
              nil
          end

        {:error, reason} ->
          Logger.warning("Failed to parse skill #{name} at #{path}: #{reason}")
          nil
      end
    else
      Logger.warning("No SKILL.md found for skill #{name} at #{path}")
      nil
    end
  end

  defp evolution_to_map(nil), do: %{}

  defp evolution_to_map(evolution) when is_map(evolution) do
    Map.new(evolution, fn {k, v} -> {to_string(k), v} end)
  end

  defp evolution_to_map(_), do: %{}
end
