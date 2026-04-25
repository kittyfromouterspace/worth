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

defmodule Worth.Config.RoutingLoadTest do
  use Worth.DataCase

  setup do
    on_exit(fn ->
      for key <- [
            "model_routing_mode",
            "model_routing_preference",
            "model_routing_filter",
            "model_routing_manual_model"
          ] do
            Worth.Settings.put(key, "", "preference")
          end

      Worth.Config.reload()
    end)

    :ok
  end

  defp put_pref(key, value) do
    {:ok, _} = Worth.Settings.put(key, value, "preference")
  end

  test "auto + free_only is loaded into [:model_routing] on reload" do
    put_pref("model_routing_mode", "auto")
    put_pref("model_routing_preference", "optimize_price")
    put_pref("model_routing_filter", "free_only")

    Worth.Config.reload()

    routing = Worth.Config.get([:model_routing])
    assert routing[:mode] == "auto"
    assert routing[:preference] == "optimize_price"
    assert routing[:filter] == "free_only"
  end

  test "manual + manual_model is parsed into provider/model_id map" do
    put_pref("model_routing_mode", "manual")
    put_pref("model_routing_manual_model", "openrouter/google/gemini-2.5-flash")

    Worth.Config.reload()

    routing = Worth.Config.get([:model_routing])
    assert routing[:mode] == "manual"
    assert routing[:manual_model] == %{provider: "openrouter", model_id: "google/gemini-2.5-flash"}
  end

  test "blank/missing routing yields nil so the brain falls back to defaults" do
    put_pref("model_routing_mode", "")

    Worth.Config.reload()

    assert Worth.Config.get([:model_routing]) == nil
  end

  test "manual with no manual_model still preserves filter" do
    put_pref("model_routing_mode", "manual")
    put_pref("model_routing_filter", "free_only")
    put_pref("model_routing_manual_model", "")

    Worth.Config.reload()

    routing = Worth.Config.get([:model_routing])
    assert routing[:mode] == "manual"
    assert routing[:filter] == "free_only"
    assert routing[:manual_model] == nil
  end
end
