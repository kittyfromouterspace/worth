defmodule Worth.LLM.Anthropic do
  @moduledoc """
  Anthropic Messages adapter shim.

  All wire-format translation lives in
  `AgentEx.LLM.Transport.AnthropicMessages`. This module knows the
  base URL and the `ANTHROPIC_API_KEY` env var.
  """

  @behaviour Worth.LLM.Adapter

  alias AgentEx.LLM.Transport.AnthropicMessages
  alias Worth.LLM.Shim

  require Logger

  @impl true
  def chat(params, config) do
    api_key = config[:api_key]
    model = config[:default_model] || "claude-sonnet-4-20250514"
    base_url = config[:base_url] || AnthropicMessages.default_base_url()

    if is_nil(api_key) or api_key == "" do
      {:error, "ANTHROPIC_API_KEY not configured"}
    else
      canonical = Shim.canonical_params(params, model)

      request =
        AnthropicMessages.build_chat_request(canonical,
          base_url: base_url,
          api_key: api_key
        )

      Logger.debug(
        "Worth.LLM.Anthropic request: model=#{model} messages=#{length(canonical.messages)} tools=#{length(canonical.tools)} url=#{request.url}"
      )

      Shim.send_and_parse(request, AnthropicMessages, model: model, provider_label: "Anthropic")
    end
  end
end
