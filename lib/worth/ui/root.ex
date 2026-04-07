defmodule Worth.UI.Root do
  use TermUI.Elm

  alias TermUI.{Event, Style, Command}

  @impl true
  def init(opts) do
    state = %{
      messages: [],
      input_text: "",
      status: :idle,
      cost: 0.0,
      workspace: opts[:workspace] || "personal",
      mode: opts[:mode] || :code,
      model: opts[:model] || "claude-sonnet-4",
      turn: 0,
      streaming_text: "",
      cursor_pos: 0,
      input_history: [],
      history_index: -1,
      sidebar_visible: false,
      sidebar_tab: :workspace,
      width: 80,
      height: 24
    }

    {state, [Command.interval(50, :check_events)]}
  end

  @impl true
  def event_to_msg(%Event.Key{key: :enter}, _state), do: {:msg, :submit_input}
  def event_to_msg(%Event.Key{key: :backspace}, _state), do: {:msg, :backspace}
  def event_to_msg(%Event.Key{key: :left}, _state), do: {:msg, :cursor_left}
  def event_to_msg(%Event.Key{key: :right}, _state), do: {:msg, :cursor_right}
  def event_to_msg(%Event.Key{key: :up}, _state), do: {:msg, :history_prev}
  def event_to_msg(%Event.Key{key: :down}, _state), do: {:msg, :history_next}
  def event_to_msg(%Event.Key{key: :tab}, _state), do: {:msg, :toggle_sidebar}
  def event_to_msg(%Event.Key{char: char}, _state) when is_binary(char), do: {:msg, {:type_char, char}}
  def event_to_msg(%Event.Key{key: key}, _state) when is_atom(key), do: :ignore
  def event_to_msg(%Event.Resize{width: w, height: h}, _state), do: {:msg, {:resize, w, h}}
  def event_to_msg(_, _), do: :ignore

  @impl true
  def update(:submit_input, %{input_text: ""} = state), do: {state, []}

  def update(:submit_input, state) do
    text = state.input_text

    history =
      if text != "" and (state.input_history == [] or hd(state.input_history) != text) do
        [text | state.input_history] |> Enum.take(100)
      else
        state.input_history
      end

    state = %{state | input_text: "", cursor_pos: 0, turn: state.turn + 1, input_history: history, history_index: -1}
    new_messages = state.messages ++ [{:user, text}]

    case parse_command(text) do
      {:command, :quit} ->
        {state, [Command.quit()]}

      {:command, :clear} ->
        {%{state | messages: [], streaming_text: ""}, []}

      {:command, :cost} ->
        msg = "Session cost: $#{Float.round(state.cost, 4)} | Turns: #{state.turn}"
        {%{state | messages: new_messages ++ [{:system, msg}]}, []}

      {:command, :help} ->
        help = help_text()
        {%{state | messages: new_messages ++ [{:system, help}]}, []}

      {:command, {:mode, mode}} ->
        Worth.Brain.switch_mode(mode)
        msg = "Switched to #{mode} mode"
        {%{state | messages: new_messages ++ [{:system, msg}], mode: mode}, []}

      {:command, {:workspace, :list}} ->
        workspaces = Worth.Workspace.Service.list()
        msg = "Workspaces: #{Enum.join(workspaces, ", ")}"
        {%{state | messages: new_messages ++ [{:system, msg}]}, []}

      {:command, {:workspace, {:switch, name}}} ->
        Worth.Brain.switch_workspace(name)
        msg = "Switched to workspace: #{name}"
        {%{state | messages: new_messages ++ [{:system, msg}], workspace: name}, []}

      {:command, {:workspace, {:new, name}}} ->
        case Worth.Workspace.Service.create(name) do
          {:ok, _path} ->
            Worth.Brain.switch_workspace(name)
            msg = "Created and switched to workspace: #{name}"
            {%{state | messages: new_messages ++ [{:system, msg}], workspace: name}, []}

          {:error, reason} ->
            {%{state | messages: new_messages ++ [{:error, reason}]}, []}
        end

      {:command, {:status, _}} ->
        status = Worth.Brain.get_status()

        msg =
          "Mode: #{status.mode} | Profile: #{status.profile} | Workspace: #{status.workspace} | Cost: $#{Float.round(status.cost, 3)}"

        {%{state | messages: new_messages ++ [{:system, msg}]}, []}

      {:command, {:memory, {:query, query}}} ->
        case Worth.Memory.Manager.search(query, workspace: state.workspace, limit: 5) do
          {:ok, %{entries: entries}} when is_list(entries) and entries != [] ->
            lines =
              entries
              |> Enum.map(fn e -> "  [#{Float.round(e.confidence || 0.5, 2)}] #{e.content}" end)
              |> Enum.join("\n")

            msg = "Memory results for '#{query}':\n#{lines}"
            {%{state | messages: new_messages ++ [{:system, msg}]}, []}

          _ ->
            msg = "No memories found for '#{query}'"
            {%{state | messages: new_messages ++ [{:system, msg}]}, []}
        end

      {:command, {:memory, {:note, note}}} ->
        case Worth.Memory.Manager.working_push(note,
               workspace: state.workspace,
               importance: 0.5,
               metadata: %{entry_type: "note", role: "user"}
             ) do
          {:ok, _} ->
            msg = "Note added to working memory."
            {%{state | messages: new_messages ++ [{:system, msg}]}, []}

          {:error, reason} ->
            {%{state | messages: new_messages ++ [{:error, "Failed to add note: #{inspect(reason)}"}]}, []}
        end

      {:command, {:memory, :recent}} ->
        case Worth.Memory.Manager.recent(workspace: state.workspace, limit: 10) do
          {:ok, entries} when is_list(entries) and entries != [] ->
            lines =
              entries
              |> Enum.map(fn e -> "  [#{e.entry_type}] #{String.slice(e.content, 0, 80)}" end)
              |> Enum.join("\n")

            msg = "Recent memories:\n#{lines}"
            {%{state | messages: new_messages ++ [{:system, msg}]}, []}

          _ ->
            msg = "No recent memories."
            {%{state | messages: new_messages ++ [{:system, msg}]}, []}
        end

      {:command, {:skill, :list}} ->
        skills = Worth.Skill.Registry.all()

        if skills == [] do
          msg = "No skills loaded."
          {%{state | messages: new_messages ++ [{:system, msg}]}, []}
        else
          lines =
            skills
            |> Enum.map(fn s ->
              loading = if s.loading == :always, do: "[always]", else: "[on-demand]"
              "  [#{s.trust_level}] #{loading} #{s.name}: #{String.slice(s.description, 0, 60)}"
            end)
            |> Enum.join("\n")

          msg = "Skills:\n#{lines}"
          {%{state | messages: new_messages ++ [{:system, msg}]}, []}
        end

      {:command, {:skill, {:read, name}}} ->
        case Worth.Skill.Service.read_body(name) do
          {:ok, body} ->
            preview = String.slice(body, 0, 500)
            msg = "Skill '#{name}':\n#{preview}"
            {%{state | messages: new_messages ++ [{:system, msg}]}, []}

          {:error, reason} ->
            {%{state | messages: new_messages ++ [{:error, "Failed to read skill: #{reason}"}]}, []}
        end

      {:command, {:skill, {:remove, name}}} ->
        case Worth.Skill.Service.remove(name) do
          {:ok, _} ->
            msg = "Skill '#{name}' removed."
            {%{state | messages: new_messages ++ [{:system, msg}]}, []}

          {:error, reason} ->
            {%{state | messages: new_messages ++ [{:error, reason}]}, []}
        end

      {:command, {:skill, {:history, name}}} ->
        case Worth.Brain.skill_history(name) do
          {:ok, versions} when is_list(versions) and versions != [] ->
            lines =
              versions
              |> Enum.map(fn {v, info} -> "  v#{v} (#{info.size} bytes)" end)
              |> Enum.join("\n")

            msg = "Skill '#{name}' versions:\n#{lines}"
            {%{state | messages: new_messages ++ [{:system, msg}]}, []}

          _ ->
            msg = "No version history for '#{name}'."
            {%{state | messages: new_messages ++ [{:system, msg}]}, []}
        end

      {:command, {:skill, {:rollback, name, version}}} ->
        case Worth.Brain.skill_rollback(name, version) do
          {:ok, info} ->
            msg = "Skill '#{name}' rolled back to v#{info.rolled_back_to}."
            {%{state | messages: new_messages ++ [{:system, msg}]}, []}

          {:error, reason} ->
            {%{state | messages: new_messages ++ [{:error, reason}]}, []}
        end

      {:command, {:skill, {:refine, name}}} ->
        case Worth.Brain.skill_refine(name) do
          {:ok, info} ->
            msg = "Skill '#{name}' refined to v#{info.version}."
            {%{state | messages: new_messages ++ [{:system, msg}]}, []}

          {:ok, :no_refinement_needed} ->
            msg = "Skill '#{name}' does not need refinement."
            {%{state | messages: new_messages ++ [{:system, msg}]}, []}

          {:error, reason} ->
            {%{state | messages: new_messages ++ [{:error, reason}]}, []}
        end

      {:command, {:session, :list}} ->
        case Worth.Brain.list_sessions() do
          {:ok, sessions} when is_list(sessions) and sessions != [] ->
            lines = sessions |> Enum.map(&"  #{&1}") |> Enum.join("\n")
            msg = "Sessions:\n#{lines}"
            {%{state | messages: new_messages ++ [{:system, msg}]}, []}

          _ ->
            msg = "No sessions found."
            {%{state | messages: new_messages ++ [{:system, msg}]}, []}
        end

      {:command, {:session, {:resume, session_id}}} ->
        Worth.Brain.resume_session(session_id)
        msg = "Resuming session: #{session_id}"
        {%{state | messages: new_messages ++ [{:system, msg}], status: :running}, []}

      {:command, {:mcp, :list}} ->
        connections = Worth.Brain.mcp_list()

        if connections == [] do
          msg = "No MCP servers connected."
          {%{state | messages: new_messages ++ [{:system, msg}]}, []}
        else
          lines =
            connections
            |> Enum.map(fn c -> "  [#{c.status}] #{c.name} (#{c.tool_count} tools)" end)
            |> Enum.join("\n")

          msg = "MCP Servers:\n#{lines}"
          {%{state | messages: new_messages ++ [{:system, msg}]}, []}
        end

      {:command, {:mcp, {:connect, name}}} ->
        case Worth.Mcp.Config.get_server(name) do
          nil ->
            msg = "Server '#{name}' not configured. Add it to ~/.worth/config.exs"
            {%{state | messages: new_messages ++ [{:error, msg}]}, []}

          config ->
            case Worth.Brain.mcp_connect(name, config) do
              {:ok, _} ->
                msg = "Connected to MCP server '#{name}'."
                {%{state | messages: new_messages ++ [{:system, msg}]}, []}

              {:error, :already_connected} ->
                msg = "Already connected to '#{name}'."
                {%{state | messages: new_messages ++ [{:system, msg}]}, []}

              {:error, reason} ->
                {%{state | messages: new_messages ++ [{:error, "Failed to connect: #{inspect(reason)}"}]}, []}
            end
        end

      {:command, {:mcp, {:disconnect, name}}} ->
        case Worth.Brain.mcp_disconnect(name) do
          :ok ->
            msg = "Disconnected from '#{name}'."
            {%{state | messages: new_messages ++ [{:system, msg}]}, []}

          {:error, :not_connected} ->
            msg = "Server '#{name}' was not connected."
            {%{state | messages: new_messages ++ [{:system, msg}]}, []}
        end

      {:command, {:mcp, {:tools, name}}} ->
        tools = Worth.Brain.mcp_tools(name)

        if tools == [] do
          msg = "No tools found for server '#{name}'."
          {%{state | messages: new_messages ++ [{:system, msg}]}, []}
        else
          lines =
            tools
            |> Enum.map(fn t -> "  #{t["name"]}: #{String.slice(t["description"] || "", 0, 60)}" end)
            |> Enum.join("\n")

          msg = "Tools from #{name}:\n#{lines}"
          {%{state | messages: new_messages ++ [{:system, msg}]}, []}
        end

      {:command, {:kit, {:search, query}}} ->
        case Worth.Tools.Kits.execute("kit_search", %{"query" => query}, state.workspace) do
          {:ok, msg} ->
            {%{state | messages: new_messages ++ [{:system, msg}]}, []}

          {:error, reason} ->
            {%{state | messages: new_messages ++ [{:error, reason}]}, []}
        end

      {:command, {:kit, {:install, owner, slug}}} ->
        case Worth.Tools.Kits.execute(
               "kit_install",
               %{"owner" => owner, "slug" => slug, "workspace" => state.workspace},
               state.workspace
             ) do
          {:ok, msg} ->
            {%{state | messages: new_messages ++ [{:system, msg}]}, []}

          {:error, reason} ->
            {%{state | messages: new_messages ++ [{:error, reason}]}, []}
        end

      {:command, {:kit, :list}} ->
        case Worth.Tools.Kits.execute("kit_list", %{}, state.workspace) do
          {:ok, msg} ->
            {%{state | messages: new_messages ++ [{:system, msg}]}, []}

          {:error, reason} ->
            {%{state | messages: new_messages ++ [{:error, reason}]}, []}
        end

      {:command, {:kit, {:info, owner, slug}}} ->
        case Worth.Tools.Kits.execute("kit_info", %{"owner" => owner, "slug" => slug}, state.workspace) do
          {:ok, msg} ->
            {%{state | messages: new_messages ++ [{:system, msg}]}, []}

          {:error, reason} ->
            {%{state | messages: new_messages ++ [{:error, reason}]}, []}
        end

      {:command, {:skill, :help}} ->
        msg =
          "Skill commands:\n  /skill list\n  /skill read <name>\n  /skill remove <name>\n  /skill history <name>\n  /skill rollback <name> <version>\n  /skill refine <name>"

        {%{state | messages: new_messages ++ [{:system, msg}]}, []}

      {:command, {:unknown, cmd}} ->
        msg = "Unknown command: #{cmd}. Type /help for available commands."
        {%{state | messages: new_messages ++ [{:system, msg}]}, []}

      :message ->
        send_message_to_brain(text)
        {%{state | messages: new_messages, status: :running, streaming_text: ""}, []}
    end
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

  def update(:cursor_left, state), do: {%{state | cursor_pos: max(state.cursor_pos - 1, 0)}, []}

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

  def update(:toggle_sidebar, state) do
    {%{state | sidebar_visible: not state.sidebar_visible}, []}
  end

  def update({:type_char, char}, state) do
    {before, after_c} = String.split_at(state.input_text, state.cursor_pos)
    new_text = before <> char <> after_c
    {%{state | input_text: new_text, cursor_pos: state.cursor_pos + 1}, []}
  end

  def update({:resize, w, h}, state), do: {%{state | width: w, height: h}, []}

  def update(:check_events, state) do
    state = drain_events(state)
    {state, [Command.interval(50, :check_events)]}
  end

  def update(_, state), do: {state, []}

  @impl true
  def view(state) do
    header = render_header(state)
    chat_nodes = render_chat(state)
    input_line = render_input(state)

    if state.sidebar_visible do
      {chat_w, sidebar_w} = split_widths(state.width)

      stack(:horizontal, [
        box([header, box(chat_nodes, height: :auto), input_line], width: chat_w),
        render_sidebar(state, sidebar_w)
      ])
    else
      stack(:vertical, [header, box(chat_nodes, height: :auto), input_line])
    end
  end

  defp split_widths(total) do
    sidebar_w = min(30, div(total, 3))
    {total - sidebar_w, sidebar_w}
  end

  defp render_header(state) do
    mode_label = "[#{state.mode}]"

    indicator = Worth.UI.Theme.status_indicator(state.status)

    header_text =
      "[#{indicator}] worth > #{state.workspace} #{mode_label}  turn:#{state.turn}  $#{Float.round(state.cost, 3)}"

    text(header_text, Worth.UI.Theme.style_for(:header))
  end

  defp render_chat(state) do
    all_nodes =
      state.messages
      |> Enum.flat_map(&message_to_nodes/1)
      |> then(fn nodes ->
        if state.streaming_text != "" and state.status == :running do
          nodes ++ message_to_nodes({:assistant, state.streaming_text})
        else
          nodes
        end
      end)

    if all_nodes == [] do
      [text("Welcome to worth. Type a message or /help for commands.", Style.from(fg: :bright_black))]
    else
      all_nodes
    end
  end

  defp render_input(state) do
    text("> #{state.input_text}", Worth.UI.Theme.style_for(:user_input))
  end

  defp render_sidebar(state, width) do
    tabs_label =
      case state.sidebar_tab do
        :workspace -> "Workspace"
        :tools -> "Tools"
        :status -> "Status"
      end

    content =
      case state.sidebar_tab do
        :workspace ->
          ws_list = Worth.Workspace.Service.list()

          ws_lines =
            if ws_list == [],
              do: ["  (none)"],
              else:
                Enum.map(ws_list, fn ws ->
                  if ws == state.workspace, do: "  * #{ws}", else: "    #{ws}"
                end)

          [text("Workspaces:", Style.from(attrs: [:bold])) | Enum.map(ws_lines, &text/1)]

        :tools ->
          tools =
            ~w(read_file write_file edit_file bash list_files skill_list skill_read memory_query search_tools use_tool)

          [
            text("Active Tools:", Style.from(attrs: [:bold]))
            | Enum.map(tools, fn t -> text("  #{t}", Style.from(fg: :bright_black)) end)
          ]

        :status ->
          [
            text("Status:", Style.from(attrs: [:bold])),
            text("  Mode: #{state.mode}"),
            text("  Cost: $#{Float.round(state.cost, 3)}"),
            text("  Turns: #{state.turn}"),
            text("  Model: #{state.model}", Style.from(fg: :bright_black))
          ]
      end

    box(
      [text("[Tab: #{tabs_label}] (Tab to toggle)", Style.from(fg: :yellow)) | content],
      style: Style.new(),
      width: width
    )
  end

  defp message_to_nodes({:user, text}) do
    style = Worth.UI.Theme.style_for(:user_input)

    text
    |> String.split("\n")
    |> Enum.map(fn line -> text("> #{line}", style) end)
  end

  defp message_to_nodes({:assistant, text}) do
    style = Worth.UI.Theme.style_for(:assistant)

    text
    |> String.split("\n")
    |> Enum.map(fn line -> text(line, style) end)
  end

  defp message_to_nodes({:system, text}) do
    style = Worth.UI.Theme.style_for(:system)

    text
    |> String.split("\n")
    |> Enum.map(fn line -> text("[system] #{line}", style) end)
  end

  defp message_to_nodes({:error, text}) do
    style = Worth.UI.Theme.style_for(:error)

    text
    |> String.split("\n")
    |> Enum.map(fn line -> text("[error] #{line}", style) end)
  end

  defp message_to_nodes({:tool_call, %{name: name, input: input}}) do
    input_preview =
      input
      |> (fn i -> if is_map(i), do: Jason.encode!(i, pretty: false), else: inspect(i) end).()
      |> String.slice(0, 80)

    [
      text("", nil),
      text("  >> #{name}(#{input_preview})", Worth.UI.Theme.style_for(:tool_call))
    ]
  end

  defp message_to_nodes({:tool_result, %{name: name, output: output}}) do
    preview = String.slice(output || "", 0, 100)

    [
      text("  << #{name}: #{preview}", Worth.UI.Theme.style_for(:tool_result))
    ]
  end

  defp message_to_nodes({:thinking, text}) do
    [
      text("  (thinking: #{String.slice(text, 0, 60)}...)", Worth.UI.Theme.style_for(:thinking))
    ]
  end

  defp drain_events(state) do
    receive do
      {:agent_event, {:text_chunk, chunk}} ->
        drain_events(%{state | streaming_text: state.streaming_text <> chunk})

      {:agent_event, {:status, status}} ->
        drain_events(%{state | status: status})

      {:agent_event, {:cost, amount}} ->
        drain_events(%{state | cost: state.cost + amount})

      {:agent_event, {:tool_call, %{name: name, input: input}}} ->
        messages = state.messages ++ [{:tool_call, %{name: name, input: input}}]
        drain_events(%{state | messages: messages})

      {:agent_event, {:tool_result, %{name: name, output: output}}} ->
        messages = state.messages ++ [{:tool_result, %{name: name, output: output}}]
        drain_events(%{state | messages: messages})

      {:agent_event, {:thinking_chunk, text}} ->
        messages = state.messages ++ [{:thinking, text}]
        drain_events(%{state | messages: messages})

      {:agent_event, {:done, %{text: text}}} ->
        final = if state.streaming_text != "", do: state.streaming_text, else: text || ""
        messages = state.messages ++ [{:assistant, final}]
        %{state | messages: messages, streaming_text: "", status: :idle}

      {:agent_event, {:error, reason}} ->
        messages = state.messages ++ [{:error, "Error: #{reason}"}]
        %{state | messages: messages, status: :idle, streaming_text: ""}

      {:agent_event, _} ->
        drain_events(state)
    after
      0 -> state
    end
  end

  defp parse_command(text) do
    case String.split(text, " ", parts: 2) do
      ["/quit"] ->
        {:command, :quit}

      ["/clear"] ->
        {:command, :clear}

      ["/cost"] ->
        {:command, :cost}

      ["/help"] ->
        {:command, :help}

      ["/status"] ->
        {:command, {:status, nil}}

      ["/mode", mode] ->
        case mode do
          m when m in ["code", "research", "planned", "turn_by_turn"] ->
            {:command, {:mode, String.to_atom(m)}}

          _ ->
            {:command, {:unknown, "/mode #{mode}"}}
        end

      ["/workspace", "list"] ->
        {:command, {:workspace, :list}}

      ["/workspace", "switch", name] ->
        {:command, {:workspace, {:switch, name}}}

      ["/workspace", "new", name] ->
        {:command, {:workspace, {:new, name}}}

      ["/memory", "query", query] ->
        {:command, {:memory, {:query, query}}}

      ["/memory", "note" | note_parts] ->
        {:command, {:memory, {:note, Enum.join(note_parts, " ")}}}

      ["/memory", "recent"] ->
        {:command, {:memory, :recent}}

      ["/skill", "list"] ->
        {:command, {:skill, :list}}

      ["/skill", "read", name] ->
        {:command, {:skill, {:read, name}}}

      ["/skill", "remove", name] ->
        {:command, {:skill, {:remove, name}}}

      ["/skill", "history", name] ->
        {:command, {:skill, {:history, name}}}

      ["/skill", "rollback", name, version] ->
        case Integer.parse(version) do
          {v, ""} -> {:command, {:skill, {:rollback, name, v}}}
          _ -> {:command, {:unknown, "/skill rollback #{name} #{version}"}}
        end

      ["/skill", "refine", name] ->
        {:command, {:skill, {:refine, name}}}

      ["/session", "list"] ->
        {:command, {:session, :list}}

      ["/session", "resume", session_id] ->
        {:command, {:session, {:resume, session_id}}}

      ["/mcp", "list"] ->
        {:command, {:mcp, :list}}

      ["/mcp", "connect", name] ->
        {:command, {:mcp, {:connect, name}}}

      ["/mcp", "disconnect", name] ->
        {:command, {:mcp, {:disconnect, name}}}

      ["/mcp", "tools", name] ->
        {:command, {:mcp, {:tools, name}}}

      ["/kit", "search", query] ->
        {:command, {:kit, {:search, query}}}

      ["/kit", "install", owner_slash_slug] ->
        case String.split(owner_slash_slug, "/", parts: 2) do
          [owner, slug] -> {:command, {:kit, {:install, owner, slug}}}
          _ -> {:command, {:unknown, "/kit install #{owner_slash_slug}"}}
        end

      ["/kit", "list"] ->
        {:command, {:kit, :list}}

      ["/kit", "info", owner_slash_slug] ->
        case String.split(owner_slash_slug, "/", parts: 2) do
          [owner, slug] -> {:command, {:kit, {:info, owner, slug}}}
          _ -> {:command, {:unknown, "/kit info #{owner_slash_slug}"}}
        end

      ["/skill" | _] ->
        {:command, {:skill, :help}}

      ["/" <> _ = cmd | _] ->
        {:command, {:unknown, cmd}}

      _ ->
        :message
    end
  end

  defp help_text do
    """
    Commands:
      /help                Show this help
      /quit                Exit worth
      /clear               Clear chat history
      /cost                Show session cost and turn count
      /status              Show current status
      /mode <mode>         Switch mode: code | research | planned | turn_by_turn
      /workspace list      List workspaces
      /workspace new <n>   Create workspace
      /workspace switch    Switch workspace
      /memory query <q>    Search global memory
      /memory note <t>     Add note to working memory
      /memory recent       Show recent memories
      /skill list          List skills
      /skill read <name>   Read skill content
      /skill remove <n>    Remove a skill
      /skill history <n>   Show skill version history
      /skill rollback <n> <v> Roll back skill to version
      /skill refine <n>    Trigger skill refinement
      /session list        List past sessions
      /session resume <id> Resume a session
      /mcp list            List connected MCP servers
      /mcp connect <name>  Connect to an MCP server
      /mcp disconnect <n>  Disconnect from a server
      /mcp tools <name>    List tools from a server
      /kit search <query>  Search JourneyKits
      /kit install <o/s>   Install a kit
      /kit list            List installed kits
      /kit info <o/s>      Show kit details
      Tab                  Toggle sidebar
      Up/Down              Command history
    """
  end

  defp send_message_to_brain(text) do
    ui_pid = self()

    Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
      case Worth.Brain.send_message(text) do
        {:ok, response} ->
          send(ui_pid, {:agent_event, {:done, response}})

        {:error, reason} ->
          send(ui_pid, {:agent_event, {:error, reason}})
      end
    end)
  end
end
