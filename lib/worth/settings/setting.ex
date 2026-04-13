defmodule Worth.Settings.Setting do
  @moduledoc """
  Ecto schema for settings storage.

  Each row stores a single key-value pair. Settings are grouped by
  `category`:

    * `"secret"` — encrypted at rest via Cloak/AES-GCM (stored in
      `encrypted_value`, requires vault unlock to read/write)
    * `"preference"` — stored as plaintext in `value` (readable without
      vault unlock, used for theme, workspace directory, memory settings, etc.)
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "worth_settings" do
    field(:key, :string)
    field(:encrypted_value, Worth.Encrypted.Binary)
    field(:value, :string)
    field(:category, :string, default: "secret")
    timestamps()
  end

  @type t :: %__MODULE__{}

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :encrypted_value, :value, :category])
    |> validate_required([:key])
    |> unique_constraint(:key)
  end
end
