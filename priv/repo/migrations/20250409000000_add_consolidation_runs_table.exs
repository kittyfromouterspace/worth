defmodule Mneme.Repo.Migrations.AddConsolidationRunsTable do
  use Ecto.Migration

  def change do
    create table(:mneme_consolidation_runs, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:owner_id, :binary_id, null: false)
      add(:scope_id, :binary_id, null: false)
      add(:timestamp, :utc_datetime_usec, null: false)
      add(:decayed, :integer, default: 0)
      add(:removed, :integer, default: 0)
      add(:merged, :integer, default: 0)
      add(:semantic_created, :integer, default: 0)
      add(:conflicts_detected, :integer, default: 0)
      add(:duration_ms, :integer)
    end

    create(index(:mneme_consolidation_runs, [:scope_id, :timestamp]))
  end
end
