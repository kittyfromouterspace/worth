defmodule Worth.Repo do
  @moduledoc """
  Ecto Repository for Worth.

  Supports both PostgreSQL and libSQL backends based on configuration.
  The adapter is determined at compile time from the application config.

  ## Configuration

  Set the database backend via environment variable:

      export WORTH_DATABASE_BACKEND=libsql  # default, single file
      export WORTH_DATABASE_BACKEND=postgres  # PostgreSQL server

  Or in config:

      config :worth, Worth.Repo,
        adapter: Ecto.Adapters.LibSql,  # or Ecto.Adapters.Postgres
        database: "/path/to/worth.db"    # for libSQL
  """

  # Determine adapter at compile time based on config
  @adapter (case Application.compile_env(:worth, [__MODULE__, :adapter], Ecto.Adapters.LibSql) do
              Ecto.Adapters.Postgres -> Ecto.Adapters.Postgres
              _ -> Ecto.Adapters.LibSql
            end)

  # Only use PostgrexTypes for PostgreSQL
  @repo_opts (if @adapter == Ecto.Adapters.Postgres do
                [
                  otp_app: :worth,
                  adapter: @adapter,
                  types: Worth.PostgrexTypes
                ]
              else
                [
                  otp_app: :worth,
                  adapter: @adapter
                ]
              end)

  use Ecto.Repo, @repo_opts

  @doc """
  Returns the installed extensions for PostgreSQL.
  For libSQL, this returns an empty list as vectors are built-in.
  """
  def installed_extensions do
    if @adapter == Ecto.Adapters.Postgres do
      ["vector", "pg_trgm"]
    else
      []
    end
  end

  @doc """
  Returns the configured database adapter.
  """
  def adapter, do: @adapter

  @doc """
  Returns true if using PostgreSQL backend.
  """
  def postgres?, do: @adapter == Ecto.Adapters.Postgres

  @doc """
  Returns true if using libSQL backend.
  """
  def libsql?, do: @adapter == Ecto.Adapters.LibSql
end
