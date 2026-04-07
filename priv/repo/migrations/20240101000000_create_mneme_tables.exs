defmodule Mneme.Repo.Migrations.CreateMnemeTables do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS vector")

    create table(:mneme_collections, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string, null: false)
      add(:collection_type, :string, null: false, default: "user")
      add(:owner_id, :uuid, null: false)
      add(:scope_id, :uuid)
      add(:metadata, :map, default: %{})
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:mneme_collections, [:owner_id, :name, :collection_type]))
    create(index(:mneme_collections, [:scope_id]))

    create table(:mneme_documents, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:title, :string)
      add(:content, :text)
      add(:content_hash, :string)
      add(:source_type, :string, null: false, default: "manual")
      add(:source_id, :string)
      add(:source_version, :string)
      add(:status, :string, null: false, default: "pending")
      add(:token_count, :integer, default: 0)
      add(:metadata, :map, default: %{})
      add(:owner_id, :uuid, null: false)
      add(:scope_id, :uuid)

      add(
        :collection_id,
        references(:mneme_collections, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:mneme_documents, [:collection_id, :source_type, :source_id]))
    create(index(:mneme_documents, [:owner_id]))
    create(index(:mneme_documents, [:scope_id]))

    create table(:mneme_chunks, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:sequence, :integer)
      add(:content, :text)
      add(:embedding, :vector, size: 768)
      add(:token_count, :integer, default: 0)
      add(:start_offset, :integer, default: 0)
      add(:end_offset, :integer, default: 0)
      add(:metadata, :map, default: %{})
      add(:owner_id, :uuid, null: false)
      add(:scope_id, :uuid)

      add(:document_id, references(:mneme_documents, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:inserted_at, :utc_datetime_usec, null: false, default: fragment("now()"))
    end

    create(index(:mneme_chunks, [:document_id]))
    create(index(:mneme_chunks, [:owner_id]))
    create(index(:mneme_chunks, [:scope_id]))

    execute("""
    CREATE INDEX mneme_chunks_embedding_idx ON mneme_chunks
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64)
    """)

    create table(:mneme_entities, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string, null: false)
      add(:entity_type, :string, null: false)
      add(:description, :text)
      add(:properties, :map, default: %{})
      add(:mention_count, :integer, default: 1)
      add(:first_seen_at, :utc_datetime_usec)
      add(:last_seen_at, :utc_datetime_usec)
      add(:embedding, :vector, size: 768)
      add(:owner_id, :uuid, null: false)
      add(:scope_id, :uuid)

      add(
        :collection_id,
        references(:mneme_collections, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:mneme_entities, [:collection_id, :name, :entity_type]))
    create(index(:mneme_entities, [:owner_id]))
    create(index(:mneme_entities, [:scope_id]))

    execute("""
    CREATE INDEX mneme_entities_embedding_idx ON mneme_entities
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64)
    """)

    create table(:mneme_relations, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:relation_type, :string, null: false)
      add(:weight, :float, default: 1.0)
      add(:properties, :map, default: %{})
      add(:owner_id, :uuid, null: false)
      add(:scope_id, :uuid)

      add(:from_entity_id, references(:mneme_entities, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:to_entity_id, references(:mneme_entities, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:source_chunk_id, references(:mneme_chunks, type: :binary_id, on_delete: :nilify_all))
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:mneme_relations, [:from_entity_id, :to_entity_id, :relation_type]))
    create(index(:mneme_relations, [:owner_id]))
    create(index(:mneme_relations, [:scope_id]))

    execute(
      """
      ALTER TABLE mneme_relations ADD CONSTRAINT no_self_relation CHECK (from_entity_id != to_entity_id)
      """,
      """
      ALTER TABLE mneme_relations DROP CONSTRAINT no_self_relation
      """
    )

    create table(:mneme_pipeline_runs, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:status, :string, null: false, default: "pending")
      add(:step_details, :map, default: %{})
      add(:error, :text)
      add(:tokens_used, :integer, default: 0)
      add(:cost_usd, :float, default: 0.0)
      add(:started_at, :utc_datetime_usec)
      add(:completed_at, :utc_datetime_usec)
      add(:owner_id, :uuid, null: false)
      add(:scope_id, :uuid)

      add(:document_id, references(:mneme_documents, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:mneme_pipeline_runs, [:document_id]))
    create(index(:mneme_pipeline_runs, [:scope_id]))

    create table(:mneme_entries, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:scope_id, :uuid)
      add(:owner_id, :uuid)
      add(:entry_type, :string, null: false, default: "note")
      add(:content, :text, null: false)
      add(:summary, :text)
      add(:source, :string, default: "system")
      add(:source_id, :string)
      add(:embedding, :vector, size: 768)
      add(:metadata, :map, default: %{})
      add(:access_count, :integer, default: 0)
      add(:last_accessed_at, :utc_datetime_usec)
      add(:confidence, :float, default: 1.0)
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:mneme_entries, [:scope_id]))
    create(index(:mneme_entries, [:owner_id]))
    create(index(:mneme_entries, [:scope_id, :last_accessed_at]))

    execute("""
    CREATE INDEX mneme_entries_embedding_idx ON mneme_entries
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64)
    """)

    create table(:mneme_edges, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:relation, :string, null: false)
      add(:weight, :float, default: 1.0)
      add(:metadata, :map, default: %{})

      add(:source_entry_id, references(:mneme_entries, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:target_entry_id, references(:mneme_entries, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:mneme_edges, [:source_entry_id, :target_entry_id, :relation]))
  end

  def down do
    drop(table(:mneme_edges))
    drop(table(:mneme_entries))
    drop(table(:mneme_pipeline_runs))
    drop(table(:mneme_relations))
    drop(table(:mneme_entities))
    drop(table(:mneme_chunks))
    drop(table(:mneme_documents))
    drop(table(:mneme_collections))
  end
end
