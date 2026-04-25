defmodule Worth.LLM do
  @moduledoc """
  Thin dispatch layer between Worth and Agentic providers.

  All model selection, route walking, failover, retry/backoff, and error
  classification live in `Agentic.Loop.Stages.LLMCall` and
  `Agentic.ModelRouter`. This module only:
  1. Extracts the route from params (injected by Agentic's LLMCall stage)
  2. Resolves the provider module and credentials
  3. Dispatches to `Agentic.LLM.Provider`

  For background tasks (fact extraction, skill refinement) that need
  tier-based dispatch with failover, use `chat_tier/2` which delegates
  to `Agentic.LLM.chat_tier/3`.
  """

  alias Agentic.LLM.Error
  alias Agentic.LLM.Provider
  alias Agentic.LLM.ProviderRegistry

  # ----- stream_chat/2: streaming dispatch -----

  @doc """
  Streaming dispatch for a single route. Agentic's LLMCall stage
  resolves routes and injects `_route` into params; this function
  dispatches to the matching provider with credentials. No retry
  logic here — LLMCall owns it.
  """
  def stream_chat(params, on_chunk) do
    case route_from_params(params) do
      nil -> stream_chat_default(params, on_chunk)
      route -> do_stream_chat_route(params, route, on_chunk)
    end
  end

  defp do_stream_chat_route(params, %{provider_name: name} = route, on_chunk) do
    case resolve_provider(name) do
      nil ->
        {:error, %Error{message: "Unknown route provider: #{name}", classification: :permanent}}

      provider_module ->
        opts =
          [model: route.model_id, on_chunk: on_chunk] ++
            credential_opts(provider_module) ++ preference_opts(params)

        Provider.stream_chat(provider_module, strip_route(params), opts)
    end
  end

  defp stream_chat_default(params, on_chunk) do
    {provider_module, model} = default_provider_and_model()

    opts = [model: model, on_chunk: on_chunk] ++ credential_opts(provider_module) ++ preference_opts(params)
    Provider.stream_chat(provider_module, strip_route(params), opts)
  end

  # ----- chat/1: non-streaming dispatch -----

  @doc """
  Non-streaming dispatch for a single route. Used by session resume
  and other callers that don't need streaming. No retry logic — LLMCall owns it.
  """
  def chat(params) do
    case route_from_params(params) do
      nil -> chat_default(params)
      route -> do_chat_route(params, route)
    end
  end

  defp do_chat_route(params, %{provider_name: name} = route) do
    case resolve_provider(name) do
      nil ->
        {:error, %Error{message: "Unknown route provider: #{name}", classification: :permanent}}

      provider_module ->
        opts = [model: route.model_id] ++ credential_opts(provider_module) ++ preference_opts(params)
        Provider.chat(provider_module, strip_route(params), opts)
    end
  end

  defp chat_default(params) do
    {provider_module, model} = default_provider_and_model()

    opts = [model: model] ++ credential_opts(provider_module) ++ preference_opts(params)
    Provider.chat(provider_module, strip_route(params), opts)
  end

  # ----- chat_tier/2: delegate to Agentic -----

  @doc """
  Tier-based chat with full failover. Delegates to `Agentic.LLM.chat_tier/3`
  which handles route resolution, walking, error classification, and health
  reporting. The `llm_chat` callback routes through this module so credentials
  are injected per-call.

  Used by background callers: fact extraction, skill refinement.
  """
  def chat_tier(params, tier) when tier in [:primary, :lightweight, :any] do
    creds_cache = build_creds_cache()

    Agentic.LLM.chat_tier(params, tier, llm_chat: fn p -> dispatch_with_cache(p, creds_cache) end)
  end

  # ----- provider resolution -----

  defp resolve_provider(name) do
    ProviderRegistry.get(name)
  end

  defp default_provider_and_model do
    provider_id = Worth.Config.get([:llm, :default_provider]) || :anthropic
    provider_module = ProviderRegistry.get(provider_id) || Agentic.LLM.Provider.Anthropic

    model =
      Worth.Config.get([:llm, :providers, provider_id, :default_model]) ||
        default_model_for(provider_module)

    {provider_module, model}
  end

  defp default_model_for(module) do
    module.default_models()
    |> Enum.find(&(&1.tier_hint == :primary))
    |> case do
      nil -> (List.first(module.default_models()) || %{id: "unknown"}).id
      model -> model.id
    end
  end

  # ----- helpers -----

  defp build_creds_cache do
    Enum.reduce(ProviderRegistry.enabled(), %{}, fn %{id: id, module: module}, acc ->
      case credential_opts(module) do
        [api_key: key] -> Map.put(acc, Atom.to_string(id), {module, key})
        [] -> Map.put(acc, Atom.to_string(id), {module, nil})
      end
    end)
  end

  defp dispatch_with_cache(params, creds_cache) do
    case route_from_params(params) do
      nil ->
        chat_default(params)

      route ->
        result = dispatch_route_cached(params, route, creds_cache)

        case result do
          {:error, %Agentic.LLM.Error{} = error} ->
            require Logger

            Logger.warning(
              "Worth.LLM.dispatch_with_cache: #{route.provider_name}/#{route.model_id} failed " <>
                "status=#{inspect(error.status)} classification=#{inspect(error.classification)} " <>
                "message=#{inspect(error.message)} raw=#{inspect(error.raw, limit: 500)}"
            )

          _ ->
            :ok
        end

        result
    end
  end

  defp dispatch_route_cached(params, %{provider_name: name, model_id: model_id}, creds_cache) do
    case Map.get(creds_cache, name) do
      nil ->
        {:error, %Error{message: "Unknown route provider: #{name}", classification: :permanent}}

      {provider_module, api_key} ->
        opts =
          [model: model_id] ++
            if(api_key, do: [api_key: api_key], else: []) ++ preference_opts(params)

        Provider.chat(provider_module, strip_route(params), opts)
    end
  end

  defp route_from_params(params) when is_map(params) do
    case params["_route"] || params[:_route] do
      %{provider_name: _, model_id: _} = route -> route
      _ -> nil
    end
  end

  defp route_from_params(_), do: nil

  defp preference_opts(params) when is_map(params) do
    case params["model_preference"] || params[:model_preference] do
      nil -> []
      pref when is_atom(pref) -> [preference: pref]
      pref when is_binary(pref) -> [preference: String.to_atom(pref)]
    end
  end

  defp strip_route(params) when is_map(params) do
    params
    |> Map.delete("_route")
    |> Map.delete(:_route)
    |> Map.delete("model_preference")
    |> Map.delete(:model_preference)
  end

  defp credential_opts(provider_module) do
    case resolve_api_key(provider_module) do
      key when is_binary(key) and key != "" -> [api_key: key]
      _ -> []
    end
  end

  defp resolve_api_key(provider_module) do
    Enum.find_value(provider_module.env_vars(), fn var ->
      case Worth.Settings.get(var) do
        key when is_binary(key) and key != "" -> key
        _ -> nil
      end
    end)
  end
end
