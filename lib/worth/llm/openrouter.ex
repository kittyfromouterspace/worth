defmodule Worth.LLM.OpenRouter do
  @moduledoc """
  OpenRouter adapter shim.

  All wire-format translation lives in
  `AgentEx.LLM.Transport.OpenAIChatCompletions`. This module is the
  thin per-provider piece: it knows the OpenRouter base URL, the
  `OPENROUTER_API_KEY` env var, and the analytics headers OpenRouter
  recommends. Adding a new OpenAI-compatible provider (Groq, Together,
  Fireworks, …) is a copy of this file with a different base URL and
  env var.
  """

  @behaviour Worth.LLM.Adapter

  alias AgentEx.LLM.Transport.OpenAIChatCompletions
  alias Worth.LLM.Shim

  require Logger

  @default_base_url "https://openrouter.ai/api/v1"

  @impl true
  def chat(params, config) do
    api_key = config[:api_key]
    model = config[:default_model] || "anthropic/claude-sonnet-4"
    base_url = config[:base_url] || @default_base_url

    if is_nil(api_key) or api_key == "" do
      {:error, "OPENROUTER_API_KEY not configured"}
    else
      canonical = Shim.canonical_params(params, model)

      extra_headers = [
        {"HTTP-Referer", "https://github.com/lenzg/worth"},
        {"X-Title", "worth"}
      ]

      request =
        OpenAIChatCompletions.build_chat_request(canonical,
          base_url: base_url,
          api_key: api_key,
          extra_headers: extra_headers
        )

      Logger.debug(
        "Worth.LLM.OpenRouter request: model=#{model} messages=#{length(canonical.messages)} tools=#{length(canonical.tools)} url=#{request.url}"
      )

      Shim.send_and_parse(request, OpenAIChatCompletions, model: model, provider_label: "OpenRouter")
    end
  end
end
