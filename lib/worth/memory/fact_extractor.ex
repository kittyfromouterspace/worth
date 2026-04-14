defmodule Worth.Memory.FactExtractor do
  @moduledoc false

  @extraction_prompt """
  Extract factual knowledge from the following text. Return a JSON array of facts.
  Each fact should be a concise statement that could be useful to remember later.
  Focus on: preferences, decisions, conventions, patterns, project-specific knowledge.
  If no facts worth remembering are present, return an empty array.

  Example output:
  ["User prefers conventional commits", "Project uses Ecto 3.12"]

  Text:
  """

  def extract_facts(text, opts \\ []) do
    if extraction_enabled?(opts) do
      {:ok, facts} = extract_facts_impl(text, opts)
      {:ok, facts}
    else
      {:ok, []}
    end
  end

  def extract_and_store(text, opts \\ []) do
    {:ok, facts} = extract_facts(text, opts)

    results =
      Enum.map(facts, fn fact ->
        Worth.Memory.Manager.remember(fact,
          entry_type: "observation",
          source: "fact_extractor",
          workspace: opts[:workspace],
          metadata: %{
            source_type: opts[:source_type] || "response",
            turn: opts[:turn]
          }
        )
      end)

    {:ok, results}
  end

  defp extract_facts_impl(text, opts) do
    llm_fn = opts[:llm_fn]

    if llm_fn do
      extract_with_llm(text, llm_fn)
    else
      extract_deterministic(text)
    end
  end

  defp extract_with_llm(text, llm_fn) do
    prompt = @extraction_prompt <> text

    case llm_fn.([%{role: "user", content: prompt}]) do
      {:ok, %{"content" => response}} ->
        parse_json_array(response)

      {:ok, %{content: response}} ->
        parse_json_array(response)

      {:ok, response} when is_binary(response) ->
        parse_json_array(response)

      {:ok, [%{type: "text", text: response} | _rest]} ->
        parse_json_array(response)

      {:ok, [%{type: :text, text: response} | _rest]} ->
        parse_json_array(response)

      _ ->
        {:ok, []}
    end
  end

  defp extract_deterministic(text) do
    facts = []

    facts =
      if String.contains?(String.downcase(text), "i prefer") or
           String.contains?(String.downcase(text), "always use") or
           String.contains?(String.downcase(text), "never use") do
        [text | facts]
      else
        facts
      end

    {:ok, facts}
  end

  defp parse_json_array(content) when is_list(content) do
    text =
      Enum.map_join(content, "\n", fn
        %{text: t} -> t
        %{"text" => t} -> t
        t when is_binary(t) -> t
        _ -> ""
      end)

    parse_json_array(text)
  end

  defp parse_json_array(text) when is_binary(text) do
    cleaned =
      text
      |> String.replace(~r/```json\s*/, "")
      |> String.replace(~r/```\s*/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, facts} when is_list(facts) ->
        valid =
          facts
          |> Enum.filter(&is_binary/1)
          |> Enum.filter(&(String.length(&1) > 5))
          |> Enum.take(10)

        {:ok, valid}

      _ ->
        {:ok, []}
    end
  end

  defp extraction_enabled?(opts) do
    Keyword.get(opts, :enabled, Worth.Config.get([:memory, :enabled], true))
  end
end
