defmodule Worth.LLM.Cost do
  @moduledoc """
  Cost calculation for LLM calls.

  Phase 2: tries to look up pricing from the provider's Model struct
  first, falls back to the legacy static pricing table.
  """

  @legacy_pricing %{
    "claude-sonnet-4-20250514" => {3.0, 15.0},
    "claude-haiku-4-20250414" => {0.80, 4.0},
    "claude-opus-4-20250514" => {15.0, 75.0},
    "gpt-4o" => {2.5, 10.0},
    "gpt-4o-mini" => {0.15, 0.6}
  }

  @default_pricing {3.0, 15.0}

  def calculate(usage, model) do
    {input_price, output_price} = pricing_for(model)

    input_tokens = (usage["input_tokens"] || usage[:input_tokens] || 0) / 1_000_000
    output_tokens = (usage["output_tokens"] || usage[:output_tokens] || 0) / 1_000_000

    input_price * input_tokens + output_price * output_tokens
  end

  defp pricing_for(%AgentEx.LLM.Model{cost: %{input: inp, output: out}}) do
    {inp, out}
  end

  defp pricing_for(model_id) when is_binary(model_id) do
    Map.get(@legacy_pricing, model_id, @default_pricing)
  end

  defp pricing_for(_), do: @default_pricing
end
