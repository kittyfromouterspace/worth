defmodule Worth.UI.Root do
  @moduledoc """
  Root TermUI Elm component for the worth TUI.

  This module is intentionally thin: it owns the UI state struct, routes
  terminal events to messages, dispatches updates, and composes the view
  from the per-region render modules in `Worth.UI.*`.

  Anything that grows beyond a few lines should move into one of:

    * `Worth.UI.Header`   — top bar
    * `Worth.UI.Chat`     — main conversation
    * `Worth.UI.Sidebar`  — right-hand panel
    * `Worth.UI.Input`    — input prompt
    * `Worth.UI.Message`  — message-tuple → render blocks
    * `Worth.UI.Commands` — slash command parsing + dispatch
    * `Worth.UI.Events`   — agent_event mailbox draining
  """

  use TermUI.Elm

  import TermUI.Component.Helpers
  alias TermUI.Event
  alias Worth.UI.{Chat, Commands, Events, Header, Input, Sidebar}

  @poll_interval 50
  @model_refresh_interval 2_000

  @impl true
  def init(opts) do
    Process.send_after(self(), :check_events, @poll_interval)
    Process.send_after(self(), :refresh_model, 100)
    Worth.Brain.set_ui_pid(self())

    {width, height} = detect_terminal_size()

    %{
      messages: [],
      input_text: "",
      status: :idle,
      cost: 0.0,
      workspace: opts[:workspace] || "personal",
      mode: opts[:mode] || :code,
      models: %{
        primary: %{label: nil, source: nil},
        lightweight: %{label: nil, source: nil}
      },
      turn: 0,
      streaming_text: "",
      cursor_pos: 0,
      input_history: [],
      history_index: -1,
      sidebar_visible: true,
      sidebar_tab: :status,
      width: width,
      height: height
    }
  end

  # TermUI only broadcasts Resize on SIGWINCH, never at startup, so we
  # have to ask the terminal directly here. Fall back to a sensible
  # default if the query fails (e.g. running under a non-tty harness).
  defp detect_terminal_size do
    case TermUI.Terminal.get_terminal_size() do
      {:ok, {rows, cols}} -> {cols, rows}
      _ -> {80, 24}
    end
  end

  # ----- event_to_msg -----

  @impl true
  def event_to_msg(%Event.Key{key: :enter}, _state), do: {:msg, :submit_input}
  def event_to_msg(%Event.Key{key: :backspace}, _state), do: {:msg, :backspace}
  def event_to_msg(%Event.Key{key: :left}, _state), do: {:msg, :cursor_left}
  def event_to_msg(%Event.Key{key: :right}, _state), do: {:msg, :cursor_right}
  def event_to_msg(%Event.Key{key: :up}, _state), do: {:msg, :history_prev}
  def event_to_msg(%Event.Key{key: :down}, _state), do: {:msg, :history_next}
  def event_to_msg(%Event.Key{key: :tab}, _state), do: {:msg, :toggle_sidebar}
  def event_to_msg(%Event.Key{char: "1"}, _state), do: {:msg, {:sidebar_tab, :workspace}}
  def event_to_msg(%Event.Key{char: "2"}, _state), do: {:msg, {:sidebar_tab, :tools}}
  def event_to_msg(%Event.Key{char: "3"}, _state), do: {:msg, {:sidebar_tab, :skills}}
  def event_to_msg(%Event.Key{char: "4"}, _state), do: {:msg, {:sidebar_tab, :status}}
  def event_to_msg(%Event.Key{char: "5"}, _state), do: {:msg, {:sidebar_tab, :logs}}

  def event_to_msg(%Event.Key{char: char}, _state) when is_binary(char),
    do: {:msg, {:type_char, char}}

  def event_to_msg(%Event.Key{key: key}, _state) when is_atom(key), do: :ignore
  def event_to_msg(%Event.Resize{width: w, height: h}, _state), do: {:msg, {:resize, w, h}}
  def event_to_msg(_, _), do: :ignore

  # ----- update -----

  @impl true
  def update(:submit_input, %{input_text: ""} = state), do: {state, []}

  def update(:submit_input, state) do
    text = state.input_text

    state =
      state
      |> Map.put(:input_text, "")
      |> Map.put(:cursor_pos, 0)
      |> Map.put(:turn, state.turn + 1)
      |> Map.put(:input_history, push_history(state.input_history, text))
      |> Map.put(:history_index, -1)
      |> append_message({:user, text})

    Commands.handle(Commands.parse(text), text, state)
  end

  def update(:backspace, state) do
    if state.cursor_pos > 0 do
      {before, after_c} = String.split_at(state.input_text, state.cursor_pos - 1)
      new_text = before <> String.slice(after_c, 1..-1//1)
      {%{state | input_text: new_text, cursor_pos: state.cursor_pos - 1}, []}
    else
      {state, []}
    end
  end

  def update(:cursor_left, state),
    do: {%{state | cursor_pos: max(state.cursor_pos - 1, 0)}, []}

  def update(:cursor_right, state) do
    {%{state | cursor_pos: min(state.cursor_pos + 1, String.length(state.input_text))}, []}
  end

  def update(:history_prev, state) do
    if state.input_history != [] do
      idx = min(state.history_index + 1, length(state.input_history) - 1)
      text = Enum.at(state.input_history, idx, "")
      {%{state | input_text: text, cursor_pos: String.length(text), history_index: idx}, []}
    else
      {state, []}
    end
  end

  def update(:history_next, state) do
    if state.history_index > 0 do
      idx = state.history_index - 1
      text = Enum.at(state.input_history, idx, "")
      {%{state | input_text: text, cursor_pos: String.length(text), history_index: idx}, []}
    else
      {%{state | input_text: "", cursor_pos: 0, history_index: -1}, []}
    end
  end

  def update(:toggle_sidebar, state),
    do: {%{state | sidebar_visible: not state.sidebar_visible}, []}

  def update({:sidebar_tab, tab}, state),
    do: {%{state | sidebar_tab: tab, sidebar_visible: true}, []}

  def update({:type_char, char}, state) do
    {before, after_c} = String.split_at(state.input_text, state.cursor_pos)
    new_text = before <> char <> after_c
    {%{state | input_text: new_text, cursor_pos: state.cursor_pos + 1}, []}
  end

  def update({:resize, w, h}, state), do: {%{state | width: w, height: h}, []}

  def update(:check_events, state) do
    state = Events.drain(state)
    Process.send_after(self(), :check_events, @poll_interval)
    {state, []}
  end

  def update(:refresh_model, state) do
    state = poll_resolved_model(state)
    Process.send_after(self(), :refresh_model, @model_refresh_interval)
    {state, []}
  end

  def update(_, state), do: {state, []}

  # ----- handle_info -----

  def handle_info(:check_events, state) do
    state = Events.drain(state)
    Process.send_after(self(), :check_events, @poll_interval)
    {state, []}
  end

  def handle_info(:refresh_model, state) do
    state = poll_resolved_model(state)
    Process.send_after(self(), :refresh_model, @model_refresh_interval)
    {state, []}
  end

  def handle_info({:agent_event, _}, state) do
    {Events.drain(state), []}
  end

  def handle_info(_msg, state), do: {state, []}

  # ----- view -----

  @impl true
  def view(state) do
    chat = Chat.render(state)

    body =
      if state.sidebar_visible do
        {chat_w, sidebar_w} = split_widths(state.width)

        stack(:horizontal, [
          box([chat], width: chat_w),
          box([Sidebar.render(state)], width: sidebar_w)
        ])
      else
        chat
      end

    stack(:vertical, [Header.render(state), body, Input.render(state)])
  end

  # Sidebar takes ~1/3 of the screen, clamped to a comfortable readable
  # range (32..60 cols). On very narrow terminals it falls back to a
  # quarter-width strip so the chat area still has room to breathe.
  defp split_widths(total) when total < 100 do
    sidebar_w = max(24, div(total, 4))
    {total - sidebar_w, sidebar_w}
  end

  defp split_widths(total) do
    sidebar_w = total |> div(3) |> min(60) |> max(32)
    {total - sidebar_w, sidebar_w}
  end

  # ----- helpers -----

  defp push_history(history, text) do
    if text != "" and (history == [] or hd(history) != text) do
      [text | history] |> Enum.take(100)
    else
      history
    end
  end

  # Ask AgentEx.ModelRouter what it would resolve right now for both
  # tiers and fold the answers into state. Runs every
  # @model_refresh_interval ms so the Status panel reflects the live
  # router — e.g. after the first OpenRouter free-model fetch completes,
  # or after a route cools down and a different one becomes the best.
  # The :model_selected event from drain/1 still wins on actual LLM
  # calls (it can update either tier slot independently based on the
  # tier the call was for).
  #
  # Wrapped in safe_resolve/1 because the UI process must never die
  # from a router-side bug — we'd lose the user's whole session.
  defp poll_resolved_model(state) do
    state
    |> refresh_tier(:primary)
    |> refresh_tier(:lightweight)
  end

  defp refresh_tier(state, tier) do
    case safe_resolve(tier) do
      {:ok, route} when is_map(route) ->
        slot = route_to_slot(route)
        current = Map.get(state.models, tier)

        if current == slot do
          state
        else
          %{state | models: Map.put(state.models, tier, slot)}
        end

      _ ->
        state
    end
  end

  defp route_to_slot(route) do
    label = Map.get(route, :label) || Map.get(route, :model_id) || "?"
    provider = Map.get(route, :provider_name, "?")
    source = Map.get(route, :source, :unknown)
    %{label: label, source: "#{source}/#{provider}"}
  end

  defp safe_resolve(tier) do
    AgentEx.ModelRouter.resolve(tier)
  rescue
    _ -> :error
  catch
    :exit, _ -> :error
  end

  defp append_message(state, msg) do
    %{state | messages: state.messages ++ [msg]}
  end
end
