defmodule Worth.LLM.OpenAI do
  @moduledoc """
  OpenAI adapter shim.

  Reuses `AgentEx.LLM.Transport.OpenAIChatCompletions` with the
  canonical OpenAI base URL and the `OPENAI_API_KEY` env var.
  """

  @behaviour Worth.LLM.Adapter

  alias AgentEx.LLM.Transport.OpenAIChatCompletions
  alias Worth.LLM.Shim

  require Logger

  @default_base_url "https://api.openai.com/v1"

  @impl true
  def chat(params, config) do
    api_key = config[:api_key]
    model = config[:default_model] || "gpt-4o"
    base_url = config[:base_url] || @default_base_url

    if is_nil(api_key) or api_key == "" do
      {:error, "OPENAI_API_KEY not configured"}
    else
      canonical = Shim.canonical_params(params, model)

      request =
        OpenAIChatCompletions.build_chat_request(canonical,
          base_url: base_url,
          api_key: api_key
        )

      Logger.debug(
        "Worth.LLM.OpenAI request: model=#{model} messages=#{length(canonical.messages)} tools=#{length(canonical.tools)} url=#{request.url}"
      )

      Shim.send_and_parse(request, OpenAIChatCompletions, model: model, provider_label: "OpenAI")
    end
  end
end
