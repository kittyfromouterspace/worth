defmodule Worth.Settings.MasterPassword do
  @moduledoc """
  Ecto schema for the master password record.

  Only one row should exist. Stores the password hash (for verification)
  and the key derivation salt (for computing the Cloak cipher key).
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "worth_master_password" do
    field(:password_hash, :string)
    field(:key_salt, :binary)
    timestamps()
  end

  @type t :: %__MODULE__{}

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:password_hash, :key_salt])
    |> validate_required([:password_hash, :key_salt])
  end
end
