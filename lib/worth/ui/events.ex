defmodule Worth.UI.Events do
  @moduledoc """
  Drains queued `{:agent_event, _}` messages from the UI process mailbox
  and folds them into the UI state.

  Called from `Worth.UI.Root` both on the periodic poll tick and from
  `handle_info/2` so updates land on the next render regardless of how
  the message arrived.
  """

  def drain(state) do
    receive do
      {:agent_event, {:text_chunk, chunk}} ->
        drain(%{state | streaming_text: state.streaming_text <> chunk})

      {:agent_event, {:status, status}} ->
        drain(%{state | status: status})

      {:agent_event, {:cost, amount}} ->
        drain(%{state | cost: state.cost + amount})

      {:agent_event, {:model_selected, info}} ->
        tier = Map.get(info, :tier, :primary)
        label = Map.get(info, :label) || Map.get(info, :model_id) || "?"
        provider = Map.get(info, :provider_name, "?")
        source = Map.get(info, :source, :unknown)
        slot = %{label: label, source: "#{source}/#{provider}"}
        drain(%{state | models: Map.put(state.models, tier, slot)})

      {:agent_event, {:tool_call, %{name: name, input: input}}} ->
        messages = state.messages ++ [{:tool_call, %{name: name, input: input}}]
        drain(%{state | messages: messages})

      {:agent_event, {:tool_result, %{name: name, output: output}}} ->
        messages = state.messages ++ [{:tool_result, %{name: name, output: output}}]
        drain(%{state | messages: messages})

      {:agent_event, {:thinking_chunk, text}} ->
        messages = state.messages ++ [{:thinking, text}]
        drain(%{state | messages: messages})

      {:agent_event, {:done, %{text: text}}} ->
        final = if state.streaming_text != "", do: state.streaming_text, else: text || ""
        messages = state.messages ++ [{:assistant, final}]
        %{state | messages: messages, streaming_text: "", status: :idle}

      {:agent_event, {:error, reason}} ->
        messages = state.messages ++ [{:error, "Error: #{reason}"}]
        %{state | messages: messages, status: :idle, streaming_text: ""}

      {:agent_event, _} ->
        drain(state)
    after
      0 -> state
    end
  end
end
