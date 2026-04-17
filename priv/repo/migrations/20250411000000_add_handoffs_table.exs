defmodule Recollect.Repo.Migrations.AddHandoffsTable do
  use Ecto.Migration

  def change do
    create table(:recollect_handoffs, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:scope_id, :binary_id, null: false)
      add(:session_id, :binary_id)
      add(:what, :text, null: false)
      add(:next, :text)
      add(:artifacts, :text)
      add(:blockers, :text)
      add(:created_at, :utc_datetime_usec)
      add(:updated_at, :utc_datetime_usec)
    end

    create(index(:recollect_handoffs, [:scope_id, :created_at]))
    create(index(:recollect_handoffs, [:session_id]))
  end
end
