defmodule Worth.LLM.AdminKeysTest do
  use Worth.DataCase, async: false

  alias Worth.LLM.AdminKeys
  alias Worth.Settings.Setting

  setup do
    # Configure a deterministic test cipher so secret-category
    # settings can be encrypted/decrypted in tests. AES-GCM key is
    # 32 bytes; the value doesn't matter as long as it's stable
    # within the test run.
    Worth.Vault.configure_key(:crypto.strong_rand_bytes(32))

    Repo.delete_all(Setting)
    :ok
  end

  describe "put/2" do
    test "saves an Anthropic admin key" do
      assert {:ok, %Setting{}} = AdminKeys.put(:anthropic, "sk-ant-admin-test123")
      assert AdminKeys.has?(:anthropic)
    end

    test "saves an OpenAI admin key" do
      assert {:ok, %Setting{}} = AdminKeys.put(:openai, "sk-admin-test456")
      assert AdminKeys.has?(:openai)
    end

    test "rejects empty key" do
      assert {:error, :empty} = AdminKeys.put(:anthropic, "")
    end
  end

  describe "has?/1" do
    test "returns false when no key stored" do
      refute AdminKeys.has?(:anthropic)
      refute AdminKeys.has?(:openai)
    end

    test "anthropic and openai are independent" do
      AdminKeys.put(:anthropic, "sk-ant-admin-only")

      assert AdminKeys.has?(:anthropic)
      refute AdminKeys.has?(:openai)
    end
  end

  describe "delete/1" do
    test "removes a stored key" do
      AdminKeys.put(:anthropic, "sk-ant-admin-test")
      assert AdminKeys.has?(:anthropic)

      AdminKeys.delete(:anthropic)
      refute AdminKeys.has?(:anthropic)
    end
  end
end
