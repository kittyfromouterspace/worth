defmodule Recollect.Repo.Migrations.AddMemoryEnhancements do
  use Ecto.Migration

  def change do
    alter table(:recollect_entries) do
      add(:half_life_days, :float, default: 7.0, null: false)
      add(:pinned, :boolean, default: false, null: false)
      add(:emotional_valence, :string, default: "neutral", null: false)
      add(:schema_fit, :float, default: 0.5, null: false)
      add(:outcome_score, :integer)
      add(:confidence_state, :string, default: "active", null: false)
    end

    create(index(:recollect_entries, [:half_life_days]))
    create(index(:recollect_entries, [:emotional_valence]))
    create(index(:recollect_entries, [:schema_fit]))
    create(index(:recollect_entries, [:confidence_state]))
  end
end
