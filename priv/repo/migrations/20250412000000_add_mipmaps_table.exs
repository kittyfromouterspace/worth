defmodule Mneme.Repo.Migrations.AddMipmapsTable do
  use Ecto.Migration

  def change do
    create table(:mneme_mipmaps, primary_key: false) do
      add(:entry_id, :binary_id, primary_key: true)
      add(:level, :string, primary_key: true)
      add(:content, :text)
      add(:metadata, :map)
      add(:embedding, :bytea)
    end

    create(index(:mneme_mipmaps, [:level]))
  end
end
