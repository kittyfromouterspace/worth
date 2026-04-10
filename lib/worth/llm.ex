defmodule Worth.LLM do
  @moduledoc """
  Top-level entry point for LLM calls from the agent loop and from
  background callers (fact extraction, skill refinement, etc).

  ## Two entry points

  - `chat/2` is a **pure dispatcher**. It looks at `params["_route"]` and
    invokes the matching provider via `AgentEx.LLM.Provider.chat/3`.
    If no `_route` is present it falls through to the statically
    configured provider. It does **not** silently retry on failure.

  - `chat_tier/3` is for callers that don't have a route yet. It asks
    `AgentEx.ModelRouter.resolve_all/1` for every healthy route in the
    requested tier and walks them in priority order. Only when every
    route has failed does it fall through to `chat_with_configured/2`.
  """

  require Logger

  @providers %{
    "openrouter" => AgentEx.LLM.Provider.OpenRouter,
    "anthropic" => AgentEx.LLM.Provider.Anthropic,
    "openai" => AgentEx.LLM.Provider.OpenAI,
    "groq" => AgentEx.LLM.Provider.Groq
  }

  # ----- stream_chat/3: streaming dispatch -----

  @doc """
  Streaming variant of `chat/2`. Calls `on_chunk.(text_delta)` for each
  text token received. Returns the full response at the end.
  """
  def stream_chat(params, config \\ %{}, on_chunk) do
    case route_from_params(params) do
      nil ->
        stream_chat_with_configured(params, config, on_chunk)

      route ->
        stream_chat_with_route(params, route, on_chunk)
    end
  end

  defp stream_chat_with_route(params, %{provider_name: name} = route, on_chunk) do
    case provider_for_route(name) do
      {:ok, provider_module} ->
        opts = [model: route.model_id, on_chunk: on_chunk]
        result = AgentEx.LLM.Provider.stream_chat(provider_module, strip_route(params), opts)
        project_result(result)

      :error ->
        {:error,
         %AgentEx.LLM.Error{
           message: "Unknown route provider: #{name}",
           classification: :permanent
         }}
    end
  end

  defp stream_chat_with_configured(params, config, on_chunk) do
    provider = get_in(config, [:llm, :default_provider]) || :anthropic
    provider_module = provider_module_for(provider)

    model =
      get_in(config, [:llm, :providers, provider, :default_model]) ||
        default_model_for(provider_module)

    result = AgentEx.LLM.Provider.stream_chat(provider_module, params, model: model, on_chunk: on_chunk)
    project_result(result)
  end

  # ----- chat/2: single dispatch -----

  def chat(params, config \\ %{}) do
    case route_from_params(params) do
      nil ->
        chat_with_configured(params, config)

      route ->
        chat_with_route(params, route)
    end
  end

  # ----- chat_tier/3: resolve, walk, retry, fall back -----

  @doc """
  Resolve every healthy route in `tier` from `AgentEx.ModelRouter` and
  try them in priority order. On each attempt the result is reported
  back to `ModelRouter` so cooldowns advance correctly. The first
  successful response wins. If every route fails, falls through to
  `chat_with_configured/2`.
  """
  def chat_tier(params, tier, config \\ %{}) when tier in [:primary, :lightweight, :any] do
    case safe_resolve_all(tier) do
      {:ok, [_ | _] = routes} ->
        try_routes(routes, params, config, tier)

      _ ->
        Logger.debug("Worth.LLM.chat_tier: no routes for tier #{tier}, using configured provider")
        chat_with_configured(params, config)
    end
  end

  defp try_routes([], params, config, tier) do
    Logger.debug("Worth.LLM.chat_tier: all routes for tier #{tier} exhausted, falling back to configured")

    chat_with_configured(params, config)
  end

  defp try_routes([route | rest], params, config, tier) do
    Logger.debug("Worth.LLM.chat_tier: trying #{route.provider_name}/#{route.model_id} (tier #{tier})")

    case chat_with_route(params, route) do
      {:ok, _} = ok ->
        report_success(route)
        ok

      {:error, reason} = err ->
        failure = classify_error(err)
        retry_after_ms = extract_retry_after(err)

        Logger.warning(
          "Worth.LLM.chat_tier: route #{route.provider_name}/#{route.model_id} failed (#{failure}, retry_after_ms=#{inspect(retry_after_ms)}): #{inspect(reason, limit: 200)}; trying next"
        )

        report_error(route, failure, retry_after_ms)
        try_routes(rest, params, config, tier)
    end
  end

  defp safe_resolve_all(tier) do
    AgentEx.ModelRouter.resolve_all(tier)
  rescue
    _ -> :error
  catch
    :exit, _ -> :error
  end

  defp report_success(route) do
    AgentEx.ModelRouter.report_success(route.provider_name, route.model_id)
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp report_error(route, failure, retry_after_ms) do
    opts = if is_integer(retry_after_ms), do: [retry_after_ms: retry_after_ms], else: []
    AgentEx.ModelRouter.report_error(route.provider_name, route.model_id, failure, opts)
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp classify_error({:error, %AgentEx.LLM.Error{classification: classification}}) do
    legacy_failure(classification)
  end

  defp classify_error({:error, %{classification: classification}}) do
    legacy_failure(classification)
  end

  defp classify_error({:error, %{status: 429}}), do: :rate_limit
  defp classify_error({:error, %{status: status}}) when status in [401, 403], do: :auth_error
  defp classify_error({:error, %{status: status}}) when is_integer(status) and status >= 500, do: :other
  defp classify_error({:error, %{message: msg}}) when is_binary(msg), do: classify_error({:error, msg})

  defp classify_error({:error, reason}) when is_binary(reason) do
    cond do
      String.contains?(reason, "429") or String.contains?(reason, "rate") ->
        :rate_limit

      String.contains?(reason, "401") or String.contains?(reason, "403") or String.contains?(reason, "unauthorized") ->
        :auth_error

      String.contains?(reason, "timeout") or String.contains?(reason, "connection") ->
        :connection_error

      true ->
        :other
    end
  end

  defp classify_error(_), do: :other

  defp legacy_failure(:rate_limit), do: :rate_limit
  defp legacy_failure(:overloaded), do: :rate_limit
  defp legacy_failure(:auth), do: :auth_error
  defp legacy_failure(:auth_permanent), do: :auth_error
  defp legacy_failure(:billing), do: :auth_error
  defp legacy_failure(:timeout), do: :connection_error
  defp legacy_failure(:transient), do: :connection_error
  defp legacy_failure(:permanent), do: :other
  defp legacy_failure(:format), do: :other
  defp legacy_failure(:model_not_found), do: :other
  defp legacy_failure(:context_overflow), do: :other
  defp legacy_failure(:session_expired), do: :auth_error
  defp legacy_failure(_), do: :other

  defp extract_retry_after({:error, %AgentEx.LLM.Error{retry_after_ms: ms}}) when is_integer(ms) and ms > 0, do: ms
  defp extract_retry_after({:error, %{retry_after_ms: ms}}) when is_integer(ms) and ms > 0, do: ms
  defp extract_retry_after(_), do: nil

  # ----- route dispatch -----

  defp route_from_params(params) when is_map(params) do
    case params["_route"] || params[:_route] do
      %{provider_name: _, model_id: _} = route -> route
      _ -> nil
    end
  end

  defp route_from_params(_), do: nil

  defp chat_with_route(params, %{provider_name: name} = route) do
    case provider_for_route(name) do
      {:ok, provider_module} ->
        opts = [model: route.model_id]
        result = AgentEx.LLM.Provider.chat(provider_module, strip_route(params), opts)
        project_result(result)

      :error ->
        {:error,
         %AgentEx.LLM.Error{
           message: "Unknown route provider: #{name}",
           classification: :permanent
         }}
    end
  end

  defp provider_for_route(name) do
    case Map.fetch(@providers, name) do
      {:ok, mod} -> {:ok, mod}
      :error -> :error
    end
  end

  defp strip_route(params) when is_map(params) do
    params
    |> Map.delete("_route")
    |> Map.delete(:_route)
  end

  # ----- configured provider fallback -----

  defp chat_with_configured(params, config) do
    provider = get_in(config, [:llm, :default_provider]) || :anthropic
    provider_module = provider_module_for(provider)

    model =
      get_in(config, [:llm, :providers, provider, :default_model]) ||
        default_model_for(provider_module)

    result = AgentEx.LLM.Provider.chat(provider_module, params, model: model)
    project_result(result)
  end

  defp provider_module_for(provider) do
    key = if is_atom(provider), do: Atom.to_string(provider), else: provider

    case Map.get(@providers, key) do
      nil ->
        case AgentEx.LLM.ProviderRegistry.get(provider) do
          nil -> AgentEx.LLM.Provider.Anthropic
          module -> module
        end

      module ->
        module
    end
  end

  defp default_model_for(module) do
    module.default_models()
    |> Enum.find(&(&1.tier_hint == :primary))
    |> case do
      nil -> (module.default_models() |> List.first() || %{id: "unknown"}).id
      model -> model.id
    end
  end

  # Project %Response{} back into the legacy map shape that the agent_ex
  # loop still consumes. This shim goes away once ModeRouter reads the
  # struct directly.
  defp project_result({:ok, %AgentEx.LLM.Response{} = r}) do
    {:ok,
     %{
       "content" => Enum.map(r.content, &project_block/1),
       "stop_reason" => r.stop_reason,
       "usage" => %{
         "input_tokens" => r.usage.input_tokens,
         "output_tokens" => r.usage.output_tokens,
         "cache_read_input_tokens" => r.usage.cache_read,
         "cache_creation_input_tokens" => r.usage.cache_write
       },
       "model" => r.model_id
     }}
  end

  defp project_result({:error, %AgentEx.LLM.Error{} = e}) do
    {:error, e}
  end

  defp project_result(other), do: other

  defp project_block(%{type: :text, text: text}) do
    %{"type" => "text", "text" => text}
  end

  defp project_block(%{type: :tool_use, id: id, name: name, input: input}) do
    %{"type" => "tool_use", "id" => id, "name" => name, "input" => input}
  end

  defp project_block(other), do: other
end
