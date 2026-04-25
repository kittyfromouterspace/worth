defmodule Worth.LLM.ProviderTaxonomyTest do
  use ExUnit.Case, async: true

  alias Worth.LLM.ProviderTaxonomy

  describe "cli_provider?/1" do
    test "recognizes the supported coding-agent CLIs" do
      assert ProviderTaxonomy.cli_provider?(:claude_code)
      assert ProviderTaxonomy.cli_provider?(:opencode)
      assert ProviderTaxonomy.cli_provider?(:codex)
      assert ProviderTaxonomy.cli_provider?(:cursor)
      assert ProviderTaxonomy.cli_provider?(:gemini)
      assert ProviderTaxonomy.cli_provider?(:goose)
      assert ProviderTaxonomy.cli_provider?(:copilot)
      assert ProviderTaxonomy.cli_provider?(:kimi)
      assert ProviderTaxonomy.cli_provider?(:qwen)
    end

    test "HTTP API providers are not classified as CLI" do
      refute ProviderTaxonomy.cli_provider?(:anthropic)
      refute ProviderTaxonomy.cli_provider?(:openai)
      refute ProviderTaxonomy.cli_provider?(:openrouter)
      refute ProviderTaxonomy.cli_provider?(:groq)
      refute ProviderTaxonomy.cli_provider?(:zai)
      refute ProviderTaxonomy.cli_provider?(:ollama)
    end
  end

  describe "default_cost_profile/1" do
    test "CLI providers default to subscription_included" do
      assert ProviderTaxonomy.default_cost_profile(:claude_code) == :subscription_included
      assert ProviderTaxonomy.default_cost_profile(:cursor) == :subscription_included
    end

    test "Ollama defaults to free (local model server)" do
      assert ProviderTaxonomy.default_cost_profile(:ollama) == :free
    end

    test "HTTP API providers default to pay_per_token" do
      assert ProviderTaxonomy.default_cost_profile(:anthropic) == :pay_per_token
      assert ProviderTaxonomy.default_cost_profile(:openrouter) == :pay_per_token
    end

    test "unknown providers default to pay_per_token" do
      assert ProviderTaxonomy.default_cost_profile(:unknown_provider) == :pay_per_token
    end
  end

  describe "source/1" do
    test "returns :coding_agent_cli for CLI providers" do
      assert ProviderTaxonomy.source(:claude_code) == :coding_agent_cli
    end

    test "returns :http_api for everything else" do
      assert ProviderTaxonomy.source(:anthropic) == :http_api
      assert ProviderTaxonomy.source(:ollama) == :http_api
    end
  end

  describe "cli_providers/0" do
    test "lists every CLI provider id" do
      providers = ProviderTaxonomy.cli_providers()

      Enum.each(
        [:claude_code, :opencode, :codex, :cursor, :gemini, :goose, :copilot, :kimi, :qwen],
        fn p -> assert p in providers end
      )
    end
  end
end
