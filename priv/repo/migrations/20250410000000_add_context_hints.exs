defmodule Recollect.Repo.Migrations.AddContextHints do
  use Ecto.Migration

  def change do
    alter table(:recollect_entries) do
      add(:context_hints, :map, default: %{}, null: false)
    end

    create(index(:recollect_entries, [:context_hints]))
  end
end
