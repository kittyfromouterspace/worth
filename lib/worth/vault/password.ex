defmodule Worth.Vault.Password do
  @moduledoc """
  Master password hashing and key derivation.

  Uses Pbkdf2 for password verification and PBKDF2 (via :crypto) for
  deriving the 32-byte AES key that backs the Cloak Vault.
  """

  @key_length 32
  @pbkdf2_iterations 100_000
  @pbkdf2_hash :sha256

  @doc "Hash a password for storage (verification on unlock)."
  def hash_password(password) when is_binary(password) do
    Pbkdf2.hash_pwd_salt(password)
  end

  @doc "Verify a password against a stored hash."
  def verify_password(password, hash) when is_binary(password) and is_binary(hash) do
    Pbkdf2.verify_pass(password, hash)
  end

  @doc "Generate a random 32-byte salt for key derivation."
  def generate_salt do
    :crypto.strong_rand_bytes(@key_length)
  end

  @doc """
  Derive a 32-byte AES key from a password and salt using PBKDF2.
  This key is used to configure the Cloak Vault cipher.
  """
  def derive_key(password, salt) when is_binary(password) and is_binary(salt) do
    :crypto.pbkdf2_hmac(@pbkdf2_hash, password, salt, @pbkdf2_iterations, @key_length)
  end
end
