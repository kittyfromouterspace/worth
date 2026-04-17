defmodule Recollect.Repo.Migrations.AddConflictsTable do
  use Ecto.Migration

  def change do
    create table(:recollect_conflicts, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:owner_id, :binary_id, null: false)
      add(:scope_id, :binary_id, null: false)
      add(:entry_a_id, :binary_id, null: false)
      add(:entry_b_id, :binary_id, null: false)
      add(:reason, :string, null: false)
      add(:score, :float, null: false)
      add(:status, :string, default: "open", null: false)
      add(:resolved_by, :binary_id)
      add(:detected_at, :utc_datetime_usec)
      add(:updated_at, :utc_datetime_usec)
    end

    create(index(:recollect_conflicts, [:scope_id, :status]))
    create(index(:recollect_conflicts, [:entry_a_id]))
    create(index(:recollect_conflicts, [:entry_b_id]))
    create(unique_index(:recollect_conflicts, [:entry_a_id, :entry_b_id]))
  end
end
