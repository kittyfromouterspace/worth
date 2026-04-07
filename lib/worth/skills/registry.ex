defmodule Worth.Skill.Registry do
  @registry_key :worth_skill_metadata

  def init do
    refresh()
  end

  def refresh do
    skills = Worth.Skill.Service.list()

    index =
      skills
      |> Enum.map(fn s -> {s.name, s} end)
      |> Enum.into(%{})

    :persistent_term.put(@registry_key, index)
    {:ok, length(skills)}
  end

  def all do
    :persistent_term.get(@registry_key, %{})
    |> Map.values()
  end

  def get(name) do
    :persistent_term.get(@registry_key, %{})
    |> Map.get(name)
  end

  def always_loaded do
    all()
    |> Enum.filter(&(&1.loading == :always))
  end

  def on_demand do
    all()
    |> Enum.filter(&(&1.loading == :on_demand))
  end

  def metadata_for_prompt do
    always = always_loaded()
    on_demand_skills = on_demand()

    parts = []

    parts =
      if always != [] do
        skills_text =
          always
          |> Enum.map(fn s -> "- #{s.name}: #{s.description}" end)
          |> Enum.join("\n")

        ["## Active Skills\n\n#{skills_text}" | parts]
      else
        parts
      end

    parts =
      if on_demand_skills != [] do
        available_text =
          on_demand_skills
          |> Enum.map(fn s -> "- #{s.name}: #{s.description} (use skill_read to load)" end)
          |> Enum.join("\n")

        ["## Available Skills (On Demand)\n\n#{available_text}" | parts]
      else
        parts
      end

    if parts != [], do: Enum.join(parts, "\n\n"), else: nil
  end
end
