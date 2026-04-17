defmodule Worth.Repo.Migrations.CreateWorkspaceIndexEntries do
  use Ecto.Migration

  def change do
    create table(:workspace_index_entries, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:workspace_name, :string, null: false)
      add(:source_type, :string, null: false)
      add(:source_path, :string, null: false)
      add(:content_hash, :string, null: false)
      add(:file_size, :integer)
      add(:last_modified, :utc_datetime_usec)
      add(:recollect_entry_ids, :map, default: %{})
      add(:indexed_at, :utc_datetime_usec, null: false)
      add(:status, :string, default: "indexed")

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:workspace_index_entries, [:workspace_name, :source_path], unique: true))
    create(index(:workspace_index_entries, [:workspace_name, :source_type]))
    create(index(:workspace_index_entries, [:workspace_name, :status]))
    create(index(:workspace_index_entries, [:workspace_name, :indexed_at]))
  end
end
