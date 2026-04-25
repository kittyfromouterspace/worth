defmodule Worth.LLM.PathwayPreferencesTest do
  @moduledoc """
  Round-trip tests for the per-provider economics + per-canonical
  preferred-pathway storage that feeds the multi-pathway router.
  """

  use Worth.DataCase, async: false

  alias Worth.LLM.PathwayPreferences
  alias Worth.Settings

  setup do
    # Each test starts with an empty preference table — clear stale
    # rows from previous suites in case they didn't roll back.
    Repo.delete_all(Settings.Setting)
    :ok
  end

  describe "account_for/2 — defaults" do
    test "returns CLI subscription default with no settings stored" do
      assert %{cost_profile: :subscription_included, subscription: nil} =
               PathwayPreferences.account_for(:claude_code)
    end

    test "returns pay_per_token default for HTTP providers with no settings stored" do
      assert %{cost_profile: :pay_per_token, subscription: nil} =
               PathwayPreferences.account_for(:anthropic)
    end

    test "returns free default for Ollama" do
      assert %{cost_profile: :free} = PathwayPreferences.account_for(:ollama)
    end
  end

  describe "put_account/2 + account_for/1" do
    test "round-trips a stored cost_profile override" do
      :ok = PathwayPreferences.put_account(:anthropic, %{cost_profile: :subscription_metered})

      assert %{cost_profile: :subscription_metered} =
               PathwayPreferences.account_for(:anthropic)
    end

    test "stores plan + monthly_fee and reconstructs Money on read" do
      fee = Money.new(:USD, "20.00")

      :ok =
        PathwayPreferences.put_account(:claude_code, %{
                 cost_profile: :subscription_included,
                 plan: "Pro",
                 monthly_fee: fee
               })

      account = PathwayPreferences.account_for(:claude_code)
      assert account.cost_profile == :subscription_included
      assert account.subscription.plan == "Pro"
      assert %Money{} = account.subscription.monthly_fee
      assert account.subscription.monthly_fee.currency == :USD
      assert Decimal.equal?(account.subscription.monthly_fee.amount, Decimal.new("20.00"))
    end

    test "preserves currency when monthly_fee is in CNY" do
      fee = Money.new(:CNY, "150.00")

      :ok =
        PathwayPreferences.put_account(:zai, %{
          cost_profile: :subscription_included,
          plan: "Developer",
          monthly_fee: fee
        })

      account = PathwayPreferences.account_for(:zai)
      assert account.subscription.monthly_fee.currency == :CNY
    end
  end

  describe "preferred pathway round-trip" do
    test "put + read + clear" do
      assert PathwayPreferences.preferred_pathway("claude-sonnet-4") == nil

      assert {:ok, _} =
               PathwayPreferences.put_preferred_pathway("claude-sonnet-4", :claude_code)

      assert PathwayPreferences.preferred_pathway("claude-sonnet-4") == :claude_code

      _ = PathwayPreferences.clear_preferred_pathway("claude-sonnet-4")
      assert PathwayPreferences.preferred_pathway("claude-sonnet-4") == nil
    end

    test "all_pathway_preferences/0 returns a canonical → atom map" do
      PathwayPreferences.put_preferred_pathway("claude-sonnet-4", :claude_code)
      PathwayPreferences.put_preferred_pathway("gpt-5.5", :codex)

      prefs = PathwayPreferences.all_pathway_preferences()
      assert prefs["claude-sonnet-4"] == :claude_code
      assert prefs["gpt-5.5"] == :codex
    end
  end
end
