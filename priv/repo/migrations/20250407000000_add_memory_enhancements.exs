defmodule Mneme.Repo.Migrations.AddMemoryEnhancements do
  use Ecto.Migration

  def change do
    alter table(:mneme_entries) do
      add(:half_life_days, :float, default: 7.0, null: false)
      add(:pinned, :boolean, default: false, null: false)
      add(:emotional_valence, :string, default: "neutral", null: false)
      add(:schema_fit, :float, default: 0.5, null: false)
      add(:outcome_score, :integer)
      add(:confidence_state, :string, default: "active", null: false)
    end

    create(index(:mneme_entries, [:half_life_days]))
    create(index(:mneme_entries, [:emotional_valence]))
    create(index(:mneme_entries, [:schema_fit]))
    create(index(:mneme_entries, [:confidence_state]))
  end
end
