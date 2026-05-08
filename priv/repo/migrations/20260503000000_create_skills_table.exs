defmodule Worth.Repo.Migrations.CreateSkillsTable do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:skills, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string, null: false)
      add(:description, :text)
      add(:body, :text, null: false)
      add(:license, :string)
      add(:compatibility, :string)
      add(:metadata, :map, default: %{})
      add(:loading, :string, default: "on_demand")
      add(:model_tier, :string, default: "any")
      add(:provenance, :string, default: "human")
      add(:trust_level, :string, default: "installed")
      add(:allowed_tools, {:array, :string})
      add(:evolution, :map, default: %{})
      add(:workspace, :string, default: "global")
      add(:installed_at, :utc_datetime_usec)
      add(:source_path, :string)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:skills, [:name, :workspace]))
    create(index(:skills, [:trust_level]))
    create(index(:skills, [:workspace]))
    create(index(:skills, [:loading]))
  end
end
