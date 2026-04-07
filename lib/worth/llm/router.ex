defmodule Worth.LLM.Router do
  def route(tier, config \\ nil) do
    config = config || Worth.Config.get_all()
    providers = config[:llm][:providers] || %{}
    default_provider = config[:llm][:default_provider] || :anthropic

    case tier do
      :primary ->
        resolve_primary(providers, default_provider)

      :lightweight ->
        resolve_lightweight(providers, default_provider)

      :any ->
        resolve_primary(providers, default_provider)
    end
  end

  def chat_with_tier(params, tier, config \\ nil) do
    config = config || Worth.Config.get_all()
    {_provider, provider_config} = route(tier, config)
    adapter = Worth.LLM.adapter_for(config[:llm][:default_provider] || :anthropic)
    adapter.chat(params, provider_config)
  end

  defp resolve_primary(providers, default) do
    primary_key = find_tier_provider(providers, :primary) || default
    {primary_key, providers[primary_key] || hd(Map.values(providers))}
  end

  defp resolve_lightweight(providers, default) do
    lightweight_key = find_tier_provider(providers, :lightweight)

    if lightweight_key do
      {lightweight_key, providers[lightweight_key]}
    else
      resolve_primary(providers, default)
    end
  end

  defp find_tier_provider(providers, tier) do
    Enum.find_value(providers, fn {key, config} ->
      if config[:tier] == tier or config["tier"] == tier, do: key
    end)
  end
end
