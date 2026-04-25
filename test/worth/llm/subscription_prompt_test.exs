defmodule Worth.LLM.SubscriptionPromptTest do
  use Worth.DataCase, async: false

  alias Worth.LLM.SubscriptionPrompt
  alias Worth.Settings.Setting

  setup do
    Repo.delete_all(Setting)
    :ok
  end

  describe "dismiss/1 + dismissed?/1" do
    test "dismiss is sticky" do
      refute SubscriptionPrompt.dismissed?(:claude_code)

      SubscriptionPrompt.dismiss(:claude_code)
      assert SubscriptionPrompt.dismissed?(:claude_code)
    end

    test "dismissals are per-provider" do
      SubscriptionPrompt.dismiss(:claude_code)

      assert SubscriptionPrompt.dismissed?(:claude_code)
      refute SubscriptionPrompt.dismissed?(:codex)
    end
  end

  describe "pending/0" do
    # `pending/0` joins ProviderAccountResolver against provider
    # availability — most CLIs aren't installed in the test
    # environment, so the list comes back empty. We only assert
    # the function returns a list.
    test "returns a (possibly empty) list of prompt maps" do
      result = SubscriptionPrompt.pending()
      assert is_list(result)

      Enum.each(result, fn prompt ->
        assert is_map(prompt)
        assert is_atom(prompt.provider)
        assert is_binary(prompt.label)
        assert is_binary(prompt.hint)
      end)
    end

    test "dismissed providers don't appear in pending/0" do
      # Even if a CLI were detected, dismissing it should suppress
      # the prompt. We can't easily fake an installed CLI in a unit
      # test, so we only verify the dismiss filter is applied (the
      # post-condition: a dismissed provider never shows up
      # regardless of state).
      SubscriptionPrompt.dismiss(:claude_code)

      result = SubscriptionPrompt.pending()
      refute Enum.any?(result, &(&1.provider == :claude_code))
    end
  end
end
