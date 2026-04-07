defmodule Worth.LLM do
  @moduledoc false

  def chat(params, config \\ %{}) do
    provider = config[:llm][:default_provider] || :anthropic
    providers = config[:llm][:providers] || %{}

    case Map.get(providers, provider) do
      nil ->
        {:error, "No provider configured for #{provider}"}

      provider_config ->
        adapter = adapter_for(provider)
        adapter.chat(params, provider_config)
    end
  end

  def adapter_for(:anthropic), do: Worth.LLM.Anthropic
  def adapter_for(:openai), do: Worth.LLM.OpenAI
  def adapter_for(:openrouter), do: Worth.LLM.OpenRouter
  def adapter_for(_other), do: Worth.LLM.Anthropic
end
