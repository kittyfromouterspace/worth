defmodule Worth.LLM.RouterTest do
  use ExUnit.Case

  describe "route/2" do
    test "routes to primary by default" do
      config = %{
        llm: %{
          default_provider: :anthropic,
          providers: %{anthropic: %{api_key: "test"}}
        }
      }

      {provider, _config} = Worth.LLM.Router.route(:primary, config)
      assert provider == :anthropic
    end

    test "falls back to default when lightweight not available" do
      config = %{
        llm: %{
          default_provider: :anthropic,
          providers: %{anthropic: %{api_key: "test"}}
        }
      }

      {provider, _config} = Worth.LLM.Router.route(:lightweight, config)
      assert provider == :anthropic
    end

    test "routes to lightweight when configured" do
      config = %{
        llm: %{
          default_provider: :anthropic,
          providers: %{
            anthropic: %{api_key: "test"},
            openai: %{api_key: "test", tier: :lightweight}
          }
        }
      }

      {provider, _config} = Worth.LLM.Router.route(:lightweight, config)
      assert provider == :openai
    end
  end
end
