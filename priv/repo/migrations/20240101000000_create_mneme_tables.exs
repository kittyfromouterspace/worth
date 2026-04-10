defmodule Mneme.Repo.Migrations.CreateMnemeTables do
  @moduledoc """
  Creates all Mneme tables.

  This migration supports both PostgreSQL (with pgvector) and libSQL/SQLite
  (with native vector support). The adapter is detected at runtime.
  """

  use Ecto.Migration

  def up do
    adapter = detect_adapter()

    # Create extension for PostgreSQL only
    if adapter == :postgres do
      execute("CREATE EXTENSION IF NOT EXISTS vector")
    end

    # ── Tier 1: Full Pipeline ──────────────────────────────────────────

    create table(:mneme_collections, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string, null: false)
      add(:collection_type, :string, null: false, default: "user")
      add(:owner_id, uuid_type(adapter), null: false)
      add(:scope_id, uuid_type(adapter))
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
      add(:owner_id, uuid_type(adapter), null: false)
      add(:scope_id, uuid_type(adapter))

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

    # Create chunks table with adapter-specific vector handling
    create_chunks_table(adapter)

    # Create entities table with adapter-specific vector handling
    create_entities_table(adapter)

    create table(:mneme_relations, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:relation_type, :string, null: false)
      add(:weight, :float, default: 1.0)
      add(:properties, :map, default: %{})
      add(:owner_id, uuid_type(adapter), null: false)
      add(:scope_id, uuid_type(adapter))

      add(:from_entity_id, references(:mneme_entities, type: :binary_id, on_delete: :delete_all), null: false)

      add(:to_entity_id, references(:mneme_entities, type: :binary_id, on_delete: :delete_all), null: false)

      add(:source_chunk_id, references(:mneme_chunks, type: :binary_id, on_delete: :nilify_all))
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:mneme_relations, [:from_entity_id, :to_entity_id, :relation_type]))
    create(index(:mneme_relations, [:owner_id]))
    create(index(:mneme_relations, [:scope_id]))

    # Self-relation constraint (PostgreSQL only)
    if adapter == :postgres do
      execute(
        "ALTER TABLE mneme_relations ADD CONSTRAINT no_self_relation CHECK (from_entity_id != to_entity_id)",
        "ALTER TABLE mneme_relations DROP CONSTRAINT no_self_relation"
      )
    end

    create table(:mneme_pipeline_runs, primary_key: false) do
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

      add(:document_id, references(:mneme_documents, type: :binary_id, on_delete: :delete_all), null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:mneme_pipeline_runs, [:document_id]))
    create(index(:mneme_pipeline_runs, [:scope_id]))

    # ── Tier 2: Lightweight Knowledge ──────────────────────────────────

    # Create entries table with adapter-specific vector handling
    create_entries_table(adapter)

    create table(:mneme_edges, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:relation, :string, null: false)
      add(:weight, :float, default: 1.0)
      add(:metadata, :map, default: %{})

      add(:source_entry_id, references(:mneme_entries, type: :binary_id, on_delete: :delete_all), null: false)

      add(:target_entry_id, references(:mneme_entries, type: :binary_id, on_delete: :delete_all), null: false)

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

  # ── Helper Functions ────────────────────────────────────────────────

  defp detect_adapter do
    # Check the repo configuration
    repo = Application.get_env(:mneme, :repo, Worth.Repo)

    # Get adapter from config, defaulting to libSQL
    # Try different config locations
    adapter =
      cond do
        # Try :worth app config
        config = Application.get_env(:worth, repo) ->
          Keyword.get(config, :adapter, Ecto.Adapters.LibSQL)

        # Try :mneme app config
        config = Application.get_env(:mneme, :database_adapter) ->
          case config do
            Mneme.DatabaseAdapter.Postgres -> Ecto.Adapters.Postgres
            Mneme.DatabaseAdapter.LibSQL -> Ecto.Adapters.LibSQL
            _ -> Ecto.Adapters.LibSQL
          end

        # Default
        true ->
          Ecto.Adapters.LibSQL
      end

    cond do
      adapter == Ecto.Adapters.Postgres -> :postgres
      adapter == Ecto.Adapters.LibSQL -> :libsql
      true -> :libsql
    end
  end

  defp uuid_type(:postgres), do: :uuid
  defp uuid_type(_), do: :string

  defp create_chunks_table(adapter) do
    # Common columns
    create table(:mneme_chunks, primary_key: false) do
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

      add(:document_id, references(:mneme_documents, type: :binary_id, on_delete: :delete_all), null: false)

      # Use timestamps without default for libSQL compatibility
      timestamps(updated_at: false)
    end

    # Add vector column and indexes based on adapter
    if adapter == :postgres do
      execute("ALTER TABLE mneme_chunks ADD COLUMN embedding vector(768)")

      execute("""
      CREATE INDEX mneme_chunks_embedding_idx ON mneme_chunks
      USING hnsw (embedding vector_cosine_ops)
      WITH (m = 16, ef_construction = 64)
      """)
    else
      # libSQL uses F32_BLOB for vectors
      execute("ALTER TABLE mneme_chunks ADD COLUMN embedding F32_BLOB(768)")
      execute("CREATE INDEX mneme_chunks_embedding_idx ON mneme_chunks (libsql_vector_idx(embedding))")
    end

    create(index(:mneme_chunks, [:document_id]))
    create(index(:mneme_chunks, [:owner_id]))
    create(index(:mneme_chunks, [:scope_id]))
  end

  defp create_entities_table(adapter) do
    create table(:mneme_entities, primary_key: false) do
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
        references(:mneme_collections, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      timestamps(type: :utc_datetime_usec)
    end

    # Add vector column and indexes based on adapter
    if adapter == :postgres do
      execute("ALTER TABLE mneme_entities ADD COLUMN embedding vector(768)")

      execute("""
      CREATE INDEX mneme_entities_embedding_idx ON mneme_entities
      USING hnsw (embedding vector_cosine_ops)
      WITH (m = 16, ef_construction = 64)
      """)
    else
      execute("ALTER TABLE mneme_entities ADD COLUMN embedding F32_BLOB(768)")
      execute("CREATE INDEX mneme_entities_embedding_idx ON mneme_entities (libsql_vector_idx(embedding))")
    end

    create(unique_index(:mneme_entities, [:collection_id, :name, :entity_type]))
    create(index(:mneme_entities, [:owner_id]))
    create(index(:mneme_entities, [:scope_id]))
  end

  defp create_entries_table(adapter) do
    # Note: Additional columns (half_life_days, pinned, emotional_valence,
    # schema_fit, outcome_score, confidence_state, context_hints) are added
    # by a later migration (20250407000000_add_memory_enhancements.exs)
    create table(:mneme_entries, primary_key: false) do
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
      # Base columns only - enhancements added by 20250407000000_add_memory_enhancements.exs
      add(:embedding_model_id, :string)
      timestamps(type: :utc_datetime_usec)
    end

    # Add vector column and indexes based on adapter
    if adapter == :postgres do
      execute("ALTER TABLE mneme_entries ADD COLUMN embedding vector(768)")

      execute("""
      CREATE INDEX mneme_entries_embedding_idx ON mneme_entries
      USING hnsw (embedding vector_cosine_ops)
      WITH (m = 16, ef_construction = 64)
      """)
    else
      execute("ALTER TABLE mneme_entries ADD COLUMN embedding F32_BLOB(768)")
      execute("CREATE INDEX mneme_entries_embedding_idx ON mneme_entries (libsql_vector_idx(embedding))")
    end

    create(index(:mneme_entries, [:scope_id]))
    create(index(:mneme_entries, [:owner_id]))
    create(index(:mneme_entries, [:scope_id, :last_accessed_at]))
  end
end
