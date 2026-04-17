defmodule Recollect.Repo.Migrations.CreateRecollectTables do
  @moduledoc """
  Creates all Recollect tables.

  This migration supports multiple database backends:
  - PostgreSQL with pgvector extension
  - SQLite with sqlite-vec extension
  - libSQL with native vector support
  """

  use Ecto.Migration

  def up do
    adapter = detect_adapter()

    # Create extension for PostgreSQL only
    if adapter == :postgres do
      execute("CREATE EXTENSION IF NOT EXISTS vector")
    end

    # ── Tier 1: Full Pipeline ──────────────────────────────────────────

    create table(:recollect_collections, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string, null: false)
      add(:collection_type, :string, null: false, default: "user")
      add(:owner_id, uuid_type(adapter), null: false)
      add(:scope_id, uuid_type(adapter))
      add(:metadata, :map, default: %{})
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:recollect_collections, [:owner_id, :name, :collection_type]))
    create(index(:recollect_collections, [:scope_id]))

    create table(:recollect_documents, primary_key: false) do
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
      add(:owner_id, uuid_type(adapter), null: false)
      add(:scope_id, uuid_type(adapter))

      add(
        :collection_id,
        references(:recollect_collections, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:recollect_documents, [:collection_id, :source_type, :source_id]))
    create(index(:recollect_documents, [:owner_id]))
    create(index(:recollect_documents, [:scope_id]))

    # Create chunks table with adapter-specific vector handling
    create_chunks_table(adapter)

    # Create entities table with adapter-specific vector handling
    create_entities_table(adapter)

    create table(:recollect_relations, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:relation_type, :string, null: false)
      add(:weight, :float, default: 1.0)
      add(:properties, :map, default: %{})
      add(:owner_id, uuid_type(adapter), null: false)
      add(:scope_id, uuid_type(adapter))

      add(:from_entity_id, references(:recollect_entities, type: :binary_id, on_delete: :delete_all), null: false)

      add(:to_entity_id, references(:recollect_entities, type: :binary_id, on_delete: :delete_all), null: false)

      add(:source_chunk_id, references(:recollect_chunks, type: :binary_id, on_delete: :nilify_all))
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:recollect_relations, [:from_entity_id, :to_entity_id, :relation_type]))
    create(index(:recollect_relations, [:owner_id]))
    create(index(:recollect_relations, [:scope_id]))

    # Self-relation constraint (PostgreSQL only)
    if adapter == :postgres do
      execute(
        "ALTER TABLE recollect_relations ADD CONSTRAINT no_self_relation CHECK (from_entity_id != to_entity_id)",
        "ALTER TABLE recollect_relations DROP CONSTRAINT no_self_relation"
      )
    end

    create table(:recollect_pipeline_runs, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:status, :string, null: false, default: "pending")
      add(:step_details, :map, default: %{})
      add(:error, :text)
      add(:tokens_used, :integer, default: 0)
      add(:cost_usd, :float, default: 0.0)
      add(:started_at, :utc_datetime_usec)
      add(:completed_at, :utc_datetime_usec)
      add(:owner_id, uuid_type(adapter), null: false)
      add(:scope_id, uuid_type(adapter))

      add(:document_id, references(:recollect_documents, type: :binary_id, on_delete: :delete_all), null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:recollect_pipeline_runs, [:document_id]))
    create(index(:recollect_pipeline_runs, [:scope_id]))

    # ── Tier 2: Lightweight Knowledge ──────────────────────────────────

    # Create entries table with adapter-specific vector handling
    create_entries_table(adapter)

    create table(:recollect_edges, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:relation, :string, null: false)
      add(:weight, :float, default: 1.0)
      add(:metadata, :map, default: %{})

      add(:source_entry_id, references(:recollect_entries, type: :binary_id, on_delete: :delete_all), null: false)

      add(:target_entry_id, references(:recollect_entries, type: :binary_id, on_delete: :delete_all), null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:recollect_edges, [:source_entry_id, :target_entry_id, :relation]))
  end

  def down do
    drop(table(:recollect_edges))
    drop(table(:recollect_entries))
    drop(table(:recollect_pipeline_runs))
    drop(table(:recollect_relations))
    drop(table(:recollect_entities))
    drop(table(:recollect_chunks))
    drop(table(:recollect_documents))
    drop(table(:recollect_collections))
  end

  # ── Helper Functions ────────────────────────────────────────────────

  defp detect_adapter do
    repo = Application.get_env(:recollect, :repo, Worth.Repo)

    adapter =
      cond do
        config = Application.get_env(:worth, repo) ->
          Keyword.get(config, :adapter, Ecto.Adapters.SQLite3)

        config = Application.get_env(:recollect, :database_adapter) ->
          case config do
            Recollect.DatabaseAdapter.Postgres -> Ecto.Adapters.Postgres
            Recollect.DatabaseAdapter.LibSQL -> Ecto.Adapters.LibSQL
            Recollect.DatabaseAdapter.SQLiteVec -> Ecto.Adapters.SQLite3
            _ -> Ecto.Adapters.SQLite3
          end

        true ->
          Ecto.Adapters.SQLite3
      end

    cond do
      adapter == Ecto.Adapters.Postgres -> :postgres
      adapter == Ecto.Adapters.LibSQL -> :libsql
      adapter == Ecto.Adapters.SQLite3 -> :sqlite
      # Fallback for unknown adapters
      true -> :sqlite
    end
  end

  defp uuid_type(:postgres), do: :uuid
  defp uuid_type(_), do: :string

  defp create_chunks_table(adapter) do
    create table(:recollect_chunks, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:sequence, :integer)
      add(:content, :text)
      add(:embedding_model_id, :string)
      add(:token_count, :integer, default: 0)
      add(:start_offset, :integer, default: 0)
      add(:end_offset, :integer, default: 0)
      add(:metadata, :map, default: %{})
      add(:owner_id, uuid_type(adapter), null: false)
      add(:scope_id, uuid_type(adapter))

      add(:document_id, references(:recollect_documents, type: :binary_id, on_delete: :delete_all), null: false)

      timestamps(updated_at: false)
    end

    # Add vector column and indexes based on adapter
    case adapter do
      :postgres ->
        execute("ALTER TABLE recollect_chunks ADD COLUMN embedding vector(768)")

        execute("""
        CREATE INDEX recollect_chunks_embedding_idx ON recollect_chunks
        USING hnsw (embedding vector_cosine_ops)
        WITH (m = 16, ef_construction = 64)
        """)

      :libsql ->
        execute("ALTER TABLE recollect_chunks ADD COLUMN embedding F32_BLOB(768)")
        execute("CREATE INDEX recollect_chunks_embedding_idx ON recollect_chunks (libsql_vector_idx(embedding))")

      :sqlite ->
        # sqlite-vec: store embeddings as TEXT (JSON arrays)
        execute("ALTER TABLE recollect_chunks ADD COLUMN embedding TEXT")
    end

    create(index(:recollect_chunks, [:document_id]))
    create(index(:recollect_chunks, [:owner_id]))
    create(index(:recollect_chunks, [:scope_id]))
  end

  defp create_entities_table(adapter) do
    create table(:recollect_entities, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string, null: false)
      add(:entity_type, :string, null: false)
      add(:description, :text)
      add(:properties, :map, default: %{})
      add(:mention_count, :integer, default: 1)
      add(:first_seen_at, :utc_datetime_usec)
      add(:last_seen_at, :utc_datetime_usec)
      add(:embedding_model_id, :string)
      add(:owner_id, uuid_type(adapter), null: false)
      add(:scope_id, uuid_type(adapter))

      add(
        :collection_id,
        references(:recollect_collections, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      timestamps(type: :utc_datetime_usec)
    end

    # Add vector column and indexes based on adapter
    case adapter do
      :postgres ->
        execute("ALTER TABLE recollect_entities ADD COLUMN embedding vector(768)")

        execute("""
        CREATE INDEX recollect_entities_embedding_idx ON recollect_entities
        USING hnsw (embedding vector_cosine_ops)
        WITH (m = 16, ef_construction = 64)
        """)

      :libsql ->
        execute("ALTER TABLE recollect_entities ADD COLUMN embedding F32_BLOB(768)")
        execute("CREATE INDEX recollect_entities_embedding_idx ON recollect_entities (libsql_vector_idx(embedding))")

      :sqlite ->
        execute("ALTER TABLE recollect_entities ADD COLUMN embedding TEXT")
    end

    create(unique_index(:recollect_entities, [:collection_id, :name, :entity_type]))
    create(index(:recollect_entities, [:owner_id]))
    create(index(:recollect_entities, [:scope_id]))
  end

  defp create_entries_table(adapter) do
    create table(:recollect_entries, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:scope_id, uuid_type(adapter))
      add(:owner_id, uuid_type(adapter))
      add(:entry_type, :string, null: false, default: "note")
      add(:content, :text, null: false)
      add(:summary, :text)
      add(:source, :string, default: "system")
      add(:source_id, :string)
      add(:metadata, :map, default: %{})
      add(:access_count, :integer, default: 0)
      add(:last_accessed_at, :utc_datetime_usec)
      add(:confidence, :float, default: 1.0)
      add(:embedding_model_id, :string)
      timestamps(type: :utc_datetime_usec)
    end

    # Add vector column and indexes based on adapter
    case adapter do
      :postgres ->
        execute("ALTER TABLE recollect_entries ADD COLUMN embedding vector(768)")

        execute("""
        CREATE INDEX recollect_entries_embedding_idx ON recollect_entries
        USING hnsw (embedding vector_cosine_ops)
        WITH (m = 16, ef_construction = 64)
        """)

      :libsql ->
        execute("ALTER TABLE recollect_entries ADD COLUMN embedding F32_BLOB(768)")
        execute("CREATE INDEX recollect_entries_embedding_idx ON recollect_entries (libsql_vector_idx(embedding))")

      :sqlite ->
        execute("ALTER TABLE recollect_entries ADD COLUMN embedding TEXT")
    end

    create(index(:recollect_entries, [:scope_id]))
    create(index(:recollect_entries, [:owner_id]))
    create(index(:recollect_entries, [:scope_id, :last_accessed_at]))
  end
end
