defmodule Worth.ConfigTest do
  use ExUnit.Case, async: true

  test "get returns config values" do
    assert Worth.Config.get(:cost_limit)
  end

  test "get returns default for missing keys" do
    assert Worth.Config.get(:nonexistent_key, "default") == "default"
  end

  test "get_all returns all config" do
    config = Worth.Config.get_all()
    assert is_map(config)
  end
end

defmodule Worth.Config.SetupTest do
  use Worth.DataCase

  alias Worth.Config.Setup

  test "needs_setup? does not require embedding_model" do
    # With workspace_directory and openrouter_key set, setup should not be needed
    # even without an embedding_model configured
    has_workspace = not is_nil(Setup.workspace_directory())
    has_key = not is_nil(Setup.openrouter_key())

    if has_workspace and has_key do
      refute Setup.needs_setup?()
    end
  end

  test "needs_setup? requires workspace_directory" do
    original = Worth.Config.get(:workspace_directory)

    on_exit(fn ->
      Worth.Config.put_setting([:workspace_directory], original)
    end)

    Worth.Config.put_setting([:workspace_directory], nil)

    if Worth.Settings.has_password?() do
      Worth.Repo.delete_all(Worth.Settings.MasterPassword)
    end

    assert Setup.needs_setup?()
  end

  test "default_embedding_model is openai/text-embedding-3-small" do
    assert Setup.default_embedding_model() == "openai/text-embedding-3-small"
  end
end
