defmodule Mneme.Repo.Migrations.AddContextHints do
  use Ecto.Migration

  def change do
    alter table(:mneme_entries) do
      add(:context_hints, :map, default: %{}, null: false)
    end

    create(index(:mneme_entries, [:context_hints]))
  end
end
