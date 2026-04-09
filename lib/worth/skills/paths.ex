defmodule Worth.Skill.Paths do
  @moduledoc """
  Shared skill path resolution. Single source of truth for locating
  skill directories across core, user, and learned skill stores.
  """

  def core_dir, do: Path.join(:code.priv_dir(:worth), "core_skills")

  def user_dir, do: Path.expand("skills", Worth.Config.Store.home_directory())

  def learned_dir, do: Path.join(user_dir(), "learned")

  @doc """
  Resolves a skill name to its directory path. Checks core, user, then learned
  directories in order. Returns nil if not found.
  """
  def resolve(skill_name) do
    candidates = [
      Path.join(core_dir(), skill_name),
      Path.join(user_dir(), skill_name),
      Path.join(learned_dir(), skill_name)
    ]

    Enum.find(candidates, &File.dir?/1)
  end

  @doc """
  Returns true if the skill lives in the core skills directory.
  """
  def core?(skill_name) do
    case resolve(skill_name) do
      nil -> false
      path -> String.starts_with?(path, core_dir())
    end
  end
end
