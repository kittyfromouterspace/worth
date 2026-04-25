defmodule Worth.LLM.ProviderAccountResolverTest do
  use Worth.DataCase, async: false

  alias Agentic.LLM.ProviderAccount
  alias Worth.LLM.ProviderAccountResolver
  alias Worth.Settings.Setting

  setup do
    Repo.delete_all(Setting)
    :ok
  end

  describe "build_all/0" do
    test "returns one ProviderAccount per registered provider" do
      accounts = ProviderAccountResolver.build_all()

      assert is_list(accounts)
      assert Enum.all?(accounts, &match?(%ProviderAccount{}, &1))

      providers = Enum.map(accounts, & &1.provider)
      assert :anthropic in providers
    end

    test "HTTP API providers default to :pay_per_token" do
      accounts = ProviderAccountResolver.build_all()
      anthropic = Enum.find(accounts, &(&1.provider == :anthropic))

      # Without an API key, anthropic comes back :unavailable, but
      # the cost_profile default still reflects taxonomy.
      assert anthropic.cost_profile == :pay_per_token
    end

    test "CLI providers default to :subscription_included" do
      accounts = ProviderAccountResolver.build_all()
      claude_code = Enum.find(accounts, &(&1.provider == :claude_code))

      if claude_code do
        assert claude_code.cost_profile == :subscription_included
      end
    end
  end

  describe "build_for_provider/1" do
    test "atom form returns a ProviderAccount" do
      account = ProviderAccountResolver.build_for_provider(:anthropic)
      assert %ProviderAccount{provider: :anthropic} = account
    end

    test "unknown provider falls back to a sensible default" do
      account = ProviderAccountResolver.build_for_provider(:never_registered)
      assert account.provider == :never_registered
      assert account.cost_profile in [:pay_per_token, :free, :subscription_included]
    end
  end

  describe "build_all_with_metadata/0" do
    test "returns extended view models with source/auto_detected flags" do
      results = ProviderAccountResolver.build_all_with_metadata()

      assert is_list(results)

      Enum.each(results, fn entry ->
        assert is_map(entry)
        assert %ProviderAccount{} = entry.account
        assert entry.source in [:http_api, :coding_agent_cli]
        assert is_boolean(entry.auto_detected)
      end)
    end

    test "auto_detected is true for ready CLI providers when no profile is stored" do
      results = ProviderAccountResolver.build_all_with_metadata()

      cli_entries = Enum.filter(results, &(&1.source == :coding_agent_cli))

      Enum.each(cli_entries, fn entry ->
        if entry.account.availability == :ready do
          assert entry.auto_detected == true
        end
      end)
    end
  end
end
