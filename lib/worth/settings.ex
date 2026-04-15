defmodule Worth.Settings do
  @moduledoc """
  Service facade for application settings.

  Two storage tiers:

    * **Preferences** (`category: "preference"`) — stored as plaintext in the
      `value` column. Always readable, no vault unlock required. Used for
      theme, workspace directory, memory settings, model routing, etc.

    * **Secrets** (`category: "secret"`) — encrypted at rest via Cloak/AES-GCM
      in the `encrypted_value` column. Requires vault unlock to read/write.
      Used for API keys and other sensitive data.
  """

  import Ecto.Query

  alias Worth.Repo
  alias Worth.Settings.MasterPassword
  alias Worth.Settings.Setting
  alias Worth.Vault
  alias Worth.Vault.Password

  # ── Password management ─────────────────────────────────────────

  @doc "True if a master password has been set."
  def has_password? do
    Repo.exists?(MasterPassword)
  end

  @doc "True if the vault is locked (no cipher key loaded)."
  def locked? do
    Vault.locked?()
  end

  @doc """
  First-time setup: hash the password, generate a key-derivation salt,
  store both in the DB, and unlock the vault.
  """
  def setup_password(password) when is_binary(password) and password != "" do
    if has_password?() do
      {:error, :already_set}
    else
      salt = Password.generate_salt()
      hash = Password.hash_password(password)

      case Repo.insert(
             MasterPassword.changeset(%MasterPassword{}, %{
               password_hash: hash,
               key_salt: salt
             })
           ) do
        {:ok, _record} ->
          derived = Password.derive_key(password, salt)
          Vault.configure_key(derived)
          :ok

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  def setup_password(_), do: {:error, :empty_password}

  @doc """
  Unlock the vault with the master password. Verifies the password
  against the stored hash, derives the key, and configures the Vault.
  """
  def unlock(password) when is_binary(password) do
    case Repo.one(from(mp in MasterPassword, limit: 1)) do
      nil ->
        {:error, :no_password_set}

      %MasterPassword{password_hash: hash, key_salt: salt} ->
        if Password.verify_password(password, hash) do
          derived = Password.derive_key(password, salt)
          Vault.configure_key(derived)
          :ok
        else
          {:error, :invalid_password}
        end
    end
  end

  @doc """
  Change the master password. Requires the current password for verification.
  Re-encrypts all existing secret settings with the new key.
  """
  def change_password(current_password, new_password)
      when is_binary(current_password) and is_binary(new_password) and new_password != "" do
    case Repo.one(from(mp in MasterPassword, limit: 1)) do
      nil ->
        {:error, :no_password_set}

      %MasterPassword{password_hash: hash} = record ->
        if Password.verify_password(current_password, hash) do
          # Decrypt all secret settings with the current key first
          all_secrets =
            from(s in Setting, where: s.category == "secret")
            |> Repo.all()
            |> Enum.map(fn s -> {s.key, s.encrypted_value, s.category} end)

          # Generate new salt and derive new key
          new_salt = Password.generate_salt()
          new_hash = Password.hash_password(new_password)
          new_key = Password.derive_key(new_password, new_salt)

          Repo.transaction(fn ->
            # Update the master password record
            record
            |> MasterPassword.changeset(%{password_hash: new_hash, key_salt: new_salt})
            |> Repo.update!()

            # Configure vault with the new key
            Vault.configure_key(new_key)

            # Re-encrypt all secret settings with the new key
            for {key, value, category} <- all_secrets do
              case Repo.get_by(Setting, key: key) do
                nil ->
                  :ok

                setting ->
                  setting
                  |> Setting.changeset(%{encrypted_value: value, category: category})
                  |> Repo.update!()
              end
            end

            :ok
          end)
        else
          {:error, :invalid_password}
        end
    end
  end

  def change_password(_, _), do: {:error, :empty_password}

  @doc "Lock the vault, clearing the cipher key from memory and purging cached credentials."
  def lock do
    Vault.lock()
    clear_credentials()
  end

  defp clear_credentials do
    for {key, "secret"} <- list_keys() do
      AgentEx.LLM.Credentials.delete(key)
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  # ── Settings CRUD ───────────────────────────────────────────────

  @doc """
  Get a setting value by key.

  Preferences are returned from the plaintext `value` column (always available).
  Secrets are returned from the encrypted `encrypted_value` column (requires
  vault unlock — returns nil if locked).
  """
  def get(key) when is_binary(key) do
    case Repo.get_by(Setting, key: key) do
      nil ->
        nil

      %Setting{category: "preference", value: value} ->
        value

      %Setting{category: "secret", encrypted_value: value} ->
        value

      %Setting{value: value} when not is_nil(value) ->
        value

      %Setting{encrypted_value: value} ->
        value
    end
  end

  @doc """
  Get a preference value (plaintext only, never touches encryption).
  Safe to call even when vault is locked.
  """
  def get_preference(key) when is_binary(key) do
    case Repo.get_by(Setting, key: key) do
      nil -> nil
      %Setting{value: value} -> value
    end
  end

  @doc """
  Store (upsert) a setting. Preferences are stored as plaintext in `value`.
  Secrets are encrypted in `encrypted_value`.
  """
  def put(key, value, category \\ "secret") when is_binary(key) and is_binary(value) do
    attrs =
      case category do
        "preference" -> %{key: key, value: value, category: category}
        _ -> %{key: key, encrypted_value: value, category: category}
      end

    case Repo.get_by(Setting, key: key) do
      nil ->
        %Setting{}
        |> Setting.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> Setting.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc "Delete a setting by key."
  def delete(key) when is_binary(key) do
    case Repo.get_by(Setting, key: key) do
      nil -> {:error, :not_found}
      setting -> Repo.delete(setting)
    end
  end

  @doc "List all settings in a category."
  def all_by_category(category) when is_binary(category) do
    Repo.all(from(s in Setting, where: s.category == ^category, order_by: s.key))
  end

  @doc "List all setting keys (no decryption needed for keys)."
  def list_keys do
    Repo.all(from(s in Setting, select: {s.key, s.category}, order_by: s.key))
  end
end
