defmodule Worth.Repo do
  @moduledoc """
  Ecto Repository for Worth.

  Uses libSQL (SQLite) as the database backend.
  """

  use Ecto.Repo,
    otp_app: :worth,
    adapter: Ecto.Adapters.LibSql

  @doc """
  Raw SQL query compatible with the Postgrex-style `repo.query/2` API.
  The LibSQL adapter doesn't inject this automatically, so we provide
  it here for compatibility with Mneme and other raw-SQL callers.
  """
  def query(sql, params \\ []) do
    Ecto.Adapters.SQL.query(__MODULE__, sql, params)
  end

  @doc """
  Returns the installed extensions.
  libSQL has native vector support, no extensions needed.
  """
  def installed_extensions, do: []

  @doc "Returns the configured database adapter."
  def adapter, do: Ecto.Adapters.LibSql

  @doc "Returns true if using libSQL backend."
  def libsql?, do: true
end
