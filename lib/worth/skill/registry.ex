defmodule Worth.Skill.Registry do
  @moduledoc """
  In-memory cache of skill metadata for fast access.

  Reads from the database-backed Worth.Skill.Service and caches
  results in persistent_term for O(1) lookups.
  """

  @registry_key :worth_skill_metadata

  def init do
    refresh()
  end

  def refresh do
    skills = Worth.Skill.Service.list()

    index =
      Map.new(skills, fn s -> {s.name, s} end)

    :persistent_term.put(@registry_key, index)
    {:ok, length(skills)}
  end

  def all do
    @registry_key
    |> :persistent_term.get(%{})
    |> Map.values()
  end

  def get(name) do
    @registry_key
    |> :persistent_term.get(%{})
    |> Map.get(name)
  end

  def always_loaded do
    Enum.filter(all(), &(&1.loading == :always))
  end

  def on_demand do
    Enum.filter(all(), &(&1.loading == :on_demand))
  end

  def metadata_for_prompt do
    always = always_loaded()
    on_demand_skills = on_demand()

    parts = []

    parts =
      if always == [] do
        parts
      else
        skills_text =
          Enum.map_join(always, "\n", fn s -> "- #{s.name}: #{s.description}" end)

        ["## Active Skills\n\n#{skills_text}" | parts]
      end

    parts =
      if on_demand_skills == [] do
        parts
      else
        available_text =
          Enum.map_join(on_demand_skills, "\n", fn s ->
            "- #{s.name}: #{s.description} (use skill_read to load)"
          end)

        ["## Available Skills (On Demand)\n\n#{available_text}" | parts]
      end

    if parts == [], do: nil, else: Enum.join(parts, "\n\n")
  end
end
