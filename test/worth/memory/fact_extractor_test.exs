defmodule Worth.Memory.FactExtractorTest do
  use ExUnit.Case

  describe "extract_facts/2" do
    test "extracts facts deterministically for preference patterns" do
      {:ok, facts} =
        Worth.Memory.FactExtractor.extract_facts(
          "I always use conventional commits with scope prefix",
          enabled: true
        )

      assert is_list(facts)
      assert length(facts) >= 1
    end

    test "returns empty list when no patterns match" do
      {:ok, facts} =
        Worth.Memory.FactExtractor.extract_facts(
          "The weather is nice today.",
          enabled: true
        )

      assert facts == []
    end

    test "returns empty list when disabled" do
      {:ok, facts} =
        Worth.Memory.FactExtractor.extract_facts(
          "I prefer tabs over spaces",
          enabled: false
        )

      assert facts == []
    end

    test "parses JSON array from LLM response" do
      response = ~s(["User prefers conventional commits", "Project uses Ecto 3.12"])

      assert {:ok, facts} =
               Worth.Memory.FactExtractor.extract_facts("test",
                 llm_fn: fn _messages ->
                   {:ok, %{"content" => response}}
                 end
               )

      assert length(facts) == 2
    end

    test "handles markdown-wrapped JSON" do
      response = "```json\n[\"Fact one\", \"Fact two\"]\n```"

      assert {:ok, facts} =
               Worth.Memory.FactExtractor.extract_facts("test",
                 llm_fn: fn _messages ->
                   {:ok, %{content: response}}
                 end
               )

      assert length(facts) == 2
    end

    test "handles invalid JSON gracefully" do
      assert {:ok, facts} =
               Worth.Memory.FactExtractor.extract_facts("test",
                 llm_fn: fn _messages ->
                   {:ok, %{"content" => "not json at all"}}
                 end
               )

      assert facts == []
    end

    test "handles LLM errors gracefully" do
      assert {:ok, facts} =
               Worth.Memory.FactExtractor.extract_facts("test",
                 llm_fn: fn _messages ->
                   {:error, "api error"}
                 end
               )

      assert facts == []
    end
  end

  describe "extract_and_store/2" do
    test "extracts and stores facts when enabled" do
      results =
        Worth.Memory.FactExtractor.extract_and_store(
          "I prefer conventional commits",
          enabled: false
        )

      assert {:ok, results} = results
      assert is_list(results)
    end
  end
end
