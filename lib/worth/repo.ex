defmodule Worth.Repo do
  @moduledoc """
  Ecto Repository for Worth.

  Uses libSQL (SQLite) as the database backend.
  """

  use Ecto.Repo,
    otp_app: :worth,
    adapter: Ecto.Adapters.LibSql

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
