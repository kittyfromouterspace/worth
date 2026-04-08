defmodule Worth.LLM.Shim do
  @moduledoc """
  Glue code shared by every Phase 1 adapter shim
  (`Worth.LLM.OpenRouter`, `Worth.LLM.Anthropic`, `Worth.LLM.OpenAI`).

  Two responsibilities:

    1. Translate Worth's adapter input — string-or-atom keyed maps with
       `"messages"`, `"tools"`, `"system"`, `"max_tokens"`, … — into the
       canonical params shape that `AgentEx.LLM.Transport` callbacks
       consume.

    2. Send the built request via `Req.post`, hand the response off to
       the transport's `parse_chat_response/3`, and project the
       resulting `AgentEx.LLM.Response` / `AgentEx.LLM.Error` structs
       back into the legacy map shape that the rest of Worth and the
       agent_ex loop currently expect (`%{"content" => [...string-keyed
       blocks...], "stop_reason" => binary, "usage" => %{...}}` on the
       happy path, `%{message:, status:, retry_after_ms:, rate_limit:}`
       on the sad path).

  The legacy projection layer goes away in Phase 2 once
  `Worth.LLM.chat/2` is rewritten as a thin dispatcher that returns
  `AgentEx.LLM.Response` directly.
  """

  alias AgentEx.LLM.{Error, Response}

  require Logger

  @doc """
  Build a canonical params map from a Worth adapter `params` map.
  Tolerates string and atom keys interchangeably.
  """
  def canonical_params(params, model) when is_map(params) do
    %{
      model: model,
      messages: get(params, "messages", :messages, []),
      system: get(params, "system", :system, nil),
      tools: get(params, "tools", :tools, []) || [],
      max_tokens: get(params, "max_tokens", :max_tokens, nil),
      temperature: get(params, "temperature", :temperature, nil),
      tool_choice: get(params, "tool_choice", :tool_choice, nil)
    }
  end

  @doc """
  Send a transport-built request via Req and project the parsed result
  back into the legacy Worth/agent_ex response map shape.
  """
  def send_and_parse(%{url: url, body: body, headers: headers}, transport, opts) do
    model = Keyword.get(opts, :model)
    label = Keyword.get(opts, :provider_label, "LLM")

    case Req.post(url, json: body, headers: headers, receive_timeout: 120_000) do
      {:ok, %{status: status, body: resp_body, headers: resp_headers}} ->
        case transport.parse_chat_response(status, resp_body, resp_headers) do
          {:ok, %Response{} = response} ->
            Logger.debug(
              "Worth.LLM.#{label} response: model=#{model} stop_reason=#{response.stop_reason} blocks=#{length(response.content)} in=#{response.usage.input_tokens} out=#{response.usage.output_tokens}"
            )

            {:ok, project_response(response)}

          {:error, %Error{} = error} ->
            Logger.warning(
              "Worth.LLM.#{label} HTTP #{error.status}: #{error.message} (classification=#{error.classification}, retry_after_ms=#{inspect(error.retry_after_ms)})"
            )

            {:error, project_error(error)}
        end

      {:error, exception} ->
        Logger.warning("Worth.LLM.#{label} HTTP failure: #{Exception.message(exception)}")

        {:error,
         %{
           message: "HTTP error: #{Exception.message(exception)}",
           status: nil,
           retry_after_ms: nil,
           rate_limit: nil,
           classification: :transient
         }}
    end
  end

  # ----- legacy projections -----

  @doc """
  Project an `AgentEx.LLM.Response` into the legacy
  string-keyed map shape consumed by `Worth.Brain`,
  `AgentEx.Loop.Stages.ModeRouter`, and friends.
  """
  def project_response(%Response{} = r) do
    %{
      "content" => Enum.map(r.content, &project_block/1),
      "stop_reason" => Atom.to_string(r.stop_reason),
      "usage" => %{
        "input_tokens" => r.usage.input_tokens,
        "output_tokens" => r.usage.output_tokens,
        "cache_read_input_tokens" => r.usage.cache_read,
        "cache_creation_input_tokens" => r.usage.cache_write
      },
      "model" => r.model_id
    }
  end

  defp project_block(%{type: :text, text: text}) do
    %{"type" => "text", "text" => text}
  end

  defp project_block(%{type: :tool_use, id: id, name: name, input: input}) do
    %{"type" => "tool_use", "id" => id, "name" => name, "input" => input}
  end

  defp project_block(other), do: other

  @doc """
  Project an `AgentEx.LLM.Error` into the legacy error map shape.
  Carries `:classification` through (Phase 1 taxonomy) so the retry
  walk in `Worth.LLM.chat_tier/3` and
  `AgentEx.Loop.Stages.LLMCall.do_try_routes/6` can read it directly
  off the map without re-classifying from strings.
  """
  def project_error(%Error{} = e) do
    %{
      message: e.message,
      status: e.status,
      retry_after_ms: e.retry_after_ms,
      rate_limit: project_rate_limit(e.rate_limit),
      classification: e.classification
    }
  end

  defp project_rate_limit(nil), do: nil

  defp project_rate_limit(%AgentEx.LLM.RateLimit{} = rl) do
    %{limit: rl.limit, remaining: rl.remaining, reset_ms: rl.reset_at_ms}
  end

  # ----- helpers -----

  defp get(map, str_key, atom_key, default) do
    case Map.get(map, str_key) do
      nil -> Map.get(map, atom_key, default)
      val -> val
    end
  end
end
