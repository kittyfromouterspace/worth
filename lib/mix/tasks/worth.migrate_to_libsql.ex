defmodule Mix.Tasks.Worth.MigrateToLibSQL do
  @moduledoc """
  Migrate Worth data from PostgreSQL to libSQL.

  This task automates the process of:
  1. Exporting data from PostgreSQL
  2. Creating a new libSQL database
  3. Importing data into libSQL

  ## Prerequisites

  Before running this task:
  1. Backup your existing data
  2. Ensure PostgreSQL is running and accessible
  3. Configure libSQL database path in config

  ## Usage

      mix worth.migrate_to_libsql --pg-database worth_dev --libsql-db ~/.worth/worth.db

  ## Options

  - `--pg-database` — PostgreSQL database name (required)
  - `--pg-user` — PostgreSQL username (default: postgres)
  - `--pg-password` — PostgreSQL password (default: postgres)
  - `--pg-host` — PostgreSQL host (default: localhost)
  - `--libsql-db` — Path for new libSQL database (required)
  - `--temp-file` — Temporary export file path (default: /tmp/worth_migration.jsonl)

  ## Example

      # Simple migration
      mix worth.migrate_to_libsql --pg-database worth_dev --libsql-db ~/.worth/worth.db

      # With custom PostgreSQL credentials
      mix worth.migrate_to_libsql \\
        --pg-database worth_prod \\
        --pg-user worth \\
        --pg-password secret \\
        --pg-host db.example.com \\
        --libsql-db ~/.worth/worth_prod.db
  """

  use Mix.Task

  @impl true
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          pg_database: :string,
          pg_user: :string,
          pg_password: :string,
          pg_host: :string,
          libsql_db: :string,
          temp_file: :string
        ]
      )

    pg_database = Keyword.get(opts, :pg_database)
    libsql_db = Keyword.get(opts, :libsql_db)

    unless pg_database do
      Mix.raise("Missing required option: --pg-database")
    end

    unless libsql_db do
      Mix.raise("Missing required option: --libsql-db")
    end

    temp_file = Keyword.get(opts, :temp_file, "/tmp/worth_migration.jsonl")

    Mix.shell().info("""
    Worth PostgreSQL → libSQL Migration
    ===================================

    Source (PostgreSQL): #{pg_database}
    Target (libSQL): #{libsql_db}
    Temp file: #{temp_file}

    This will:
    1. Export data from PostgreSQL
    2. Create new libSQL database at #{libsql_db}
    3. Import data into libSQL

    WARNING: This operation will create a NEW libSQL database.
    Any existing data at the target path may be affected.
    """)

    unless Mix.shell().yes?("Do you want to continue?") do
      Mix.shell().info("Migration cancelled.")
      exit(0)
    end

    # Step 1: Export from PostgreSQL
    Mix.shell().info("\n[Step 1/3] Exporting from PostgreSQL...")

    export_result =
      System.cmd("mix", ["worth.export", "--output", temp_file],
        env: [
          {"WORTH_DATABASE_BACKEND", "postgres"},
          {"WORTH_DB_NAME", pg_database},
          {"WORTH_DB_USER", Keyword.get(opts, :pg_user, "postgres")},
          {"WORTH_DB_PASSWORD", Keyword.get(opts, :pg_password, "postgres")},
          {"WORTH_DB_HOST", Keyword.get(opts, :pg_host, "localhost")}
        ],
        into: IO.stream(:stdio, :line)
      )

    case export_result do
      {_, 0} ->
        Mix.shell().info("✓ Export successful\n")

      {_, code} ->
        Mix.raise("Export failed with exit code #{code}")
    end

    # Step 2: Create libSQL database
    Mix.shell().info("[Step 2/3] Setting up libSQL database...")

    # Ensure directory exists
    libsql_db |> Path.dirname() |> File.mkdir_p!()

    # Remove existing file if present
    if File.exists?(libsql_db) do
      Mix.shell().info("Removing existing database at #{libsql_db}")
      File.rm!(libsql_db)
    end

    Mix.shell().info("✓ libSQL database ready\n")

    # Step 3: Import to libSQL
    Mix.shell().info("[Step 3/3] Importing to libSQL...")

    import_result =
      System.cmd("mix", ["worth.import", "--input", temp_file],
        env: [
          {"WORTH_DATABASE_BACKEND", "libsql"},
          {"WORTH_HOME", Path.dirname(libsql_db)}
        ],
        into: IO.stream(:stdio, :line)
      )

    case import_result do
      {_, 0} ->
        Mix.shell().info("✓ Import successful\n")

      {_, code} ->
        Mix.raise("Import failed with exit code #{code}")
    end

    # Cleanup
    Mix.shell().info("Cleaning up temporary file...")
    File.rm(temp_file)

    Mix.shell().info("""
    ===================================
    Migration completed successfully!

    Your data has been migrated from PostgreSQL to libSQL.

    New database: #{libsql_db}

    Next steps:
    1. Update your config to use libSQL:
       config :worth, Worth.Repo,
         adapter: Ecto.Adapters.LibSQL,
         database: "#{libsql_db}"

    2. Set the environment variable:
       export WORTH_DATABASE_BACKEND=libsql

    3. Restart your application

    4. Optionally, you can now remove PostgreSQL if no longer needed.
    """)
  end
end
