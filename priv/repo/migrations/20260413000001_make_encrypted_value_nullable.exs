defmodule Worth.Repo.Migrations.MakeEncryptedValueNullable do
  use Ecto.Migration

  @doc """
  SQLite doesn't support ALTER COLUMN, so we recreate the table.
  Preferences use the plaintext `value` column and don't need encrypted_value.
  """
  def up do
    execute """
    CREATE TABLE worth_settings_new (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      key TEXT NOT NULL,
      encrypted_value BLOB,
      category TEXT NOT NULL DEFAULT 'secret',
      value TEXT,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """

    execute """
    INSERT INTO worth_settings_new (id, key, encrypted_value, category, value, inserted_at, updated_at)
    SELECT id, key, encrypted_value, category, value, inserted_at, updated_at
    FROM worth_settings
    """

    execute "DROP TABLE worth_settings"
    execute "ALTER TABLE worth_settings_new RENAME TO worth_settings"
    execute "CREATE UNIQUE INDEX worth_settings_key_index ON worth_settings (key)"
  end

  def down do
    execute """
    CREATE TABLE worth_settings_old (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      key TEXT NOT NULL,
      encrypted_value BLOB NOT NULL,
      category TEXT NOT NULL DEFAULT 'secret',
      value TEXT,
      inserted_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    """

    execute """
    INSERT INTO worth_settings_old (id, key, encrypted_value, category, value, inserted_at, updated_at)
    SELECT id, key, encrypted_value, category, value, inserted_at, updated_at
    FROM worth_settings
    WHERE encrypted_value IS NOT NULL
    """

    execute "DROP TABLE worth_settings"
    execute "ALTER TABLE worth_settings_old RENAME TO worth_settings"
    execute "CREATE UNIQUE INDEX worth_settings_key_index ON worth_settings (key)"
  end
end
