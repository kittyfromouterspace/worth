defmodule Worth.UI.Commands do
  @moduledoc """
  Slash command parser and dispatcher for the TUI.

  Flow from `Worth.UI.Root`:

      parsed = Commands.parse(text)
      Commands.handle(parsed, text, state)

  By the time `handle/3` is called the user's own input has already been
  appended to `state.messages`, so handlers only need to append system or
  error responses (or wipe history for `/clear`). `handle/3` returns the
  standard `{state, commands}` tuple expected by `TermUI.Elm.update/2`.
  """

  alias TermUI.Command

  # ----- parsing -----

  def parse(text) do
    case String.split(text, " ", parts: 2) do
      ["/quit"] -> {:command, :quit}
      ["/clear"] -> {:command, :clear}
      ["/cost"] -> {:command, :cost}
      ["/help"] -> {:command, :help}
      ["/status"] -> {:command, {:status, nil}}
      ["/mode", mode] -> parse_mode(mode)
      ["/workspace", "list"] -> {:command, {:workspace, :list}}
      ["/workspace", "switch", name] -> {:command, {:workspace, {:switch, name}}}
      ["/workspace", "new", name] -> {:command, {:workspace, {:new, name}}}
      ["/memory", "query", query] -> {:command, {:memory, {:query, query}}}
      ["/memory", "note" | note_parts] -> {:command, {:memory, {:note, Enum.join(note_parts, " ")}}}
      ["/memory", "recent"] -> {:command, {:memory, :recent}}
      ["/skill", "list"] -> {:command, {:skill, :list}}
      ["/skill", "read", name] -> {:command, {:skill, {:read, name}}}
      ["/skill", "remove", name] -> {:command, {:skill, {:remove, name}}}
      ["/skill", "history", name] -> {:command, {:skill, {:history, name}}}
      ["/skill", "rollback", name, version] -> parse_rollback(name, version)
      ["/skill", "refine", name] -> {:command, {:skill, {:refine, name}}}
      ["/session", "list"] -> {:command, {:session, :list}}
      ["/session", "resume", session_id] -> {:command, {:session, {:resume, session_id}}}
      ["/mcp", "list"] -> {:command, {:mcp, :list}}
      ["/mcp", "connect", name] -> {:command, {:mcp, {:connect, name}}}
      ["/mcp", "disconnect", name] -> {:command, {:mcp, {:disconnect, name}}}
      ["/mcp", "tools", name] -> {:command, {:mcp, {:tools, name}}}
      ["/kit", "search", query] -> {:command, {:kit, {:search, query}}}
      ["/kit", "install", owner_slash_slug] -> parse_owner_slug(:install, owner_slash_slug)
      ["/kit", "list"] -> {:command, {:kit, :list}}
      ["/kit", "info", owner_slash_slug] -> parse_owner_slug(:info, owner_slash_slug)
      ["/provider", "list"] -> {:command, {:provider, :list}}
      ["/provider", "enable", id] -> {:command, {:provider, {:enable, String.to_atom(id)}}}
      ["/provider", "disable", id] -> {:command, {:provider, {:disable, String.to_atom(id)}}}
      ["/skill" | _] -> {:command, {:skill, :help}}
      ["/" <> _ = cmd | _] -> {:command, {:unknown, cmd}}
      _ -> :message
    end
  end

  defp parse_mode(mode) when mode in ["code", "research", "planned", "turn_by_turn"] do
    {:command, {:mode, String.to_atom(mode)}}
  end

  defp parse_mode(mode), do: {:command, {:unknown, "/mode #{mode}"}}

  defp parse_rollback(name, version) do
    case Integer.parse(version) do
      {v, ""} -> {:command, {:skill, {:rollback, name, v}}}
      _ -> {:command, {:unknown, "/skill rollback #{name} #{version}"}}
    end
  end

  defp parse_owner_slug(action, owner_slash_slug) do
    case String.split(owner_slash_slug, "/", parts: 2) do
      [owner, slug] -> {:command, {:kit, {action, owner, slug}}}
      _ -> {:command, {:unknown, "/kit #{action} #{owner_slash_slug}"}}
    end
  end

  # ----- dispatch -----

  def handle({:command, :quit}, _text, state), do: {state, [Command.quit()]}

  def handle({:command, :clear}, _text, state) do
    {%{state | messages: [], streaming_text: ""}, []}
  end

  def handle({:command, :cost}, _text, state) do
    {append_system(state, "Session cost: $#{Float.round(state.cost, 4)} | Turns: #{state.turn}"), []}
  end

  def handle({:command, :help}, _text, state) do
    {append_system(state, help_text()), []}
  end

  def handle({:command, {:mode, mode}}, _text, state) do
    Worth.Brain.switch_mode(mode)
    {append_system(%{state | mode: mode}, "Switched to #{mode} mode"), []}
  end

  def handle({:command, {:workspace, :list}}, _text, state) do
    workspaces = Worth.Workspace.Service.list()
    {append_system(state, "Workspaces: #{Enum.join(workspaces, ", ")}"), []}
  end

  def handle({:command, {:workspace, {:switch, name}}}, _text, state) do
    Worth.Brain.switch_workspace(name)
    {append_system(%{state | workspace: name}, "Switched to workspace: #{name}"), []}
  end

  def handle({:command, {:workspace, {:new, name}}}, _text, state) do
    case Worth.Workspace.Service.create(name) do
      {:ok, _path} ->
        Worth.Brain.switch_workspace(name)
        {append_system(%{state | workspace: name}, "Created and switched to workspace: #{name}"), []}

      {:error, reason} ->
        {append_error(state, reason), []}
    end
  end

  def handle({:command, {:status, _}}, _text, state) do
    status = Worth.Brain.get_status()

    msg =
      "Mode: #{status.mode} | Profile: #{status.profile} | Workspace: #{status.workspace} | Cost: $#{Float.round(status.cost, 3)}"

    {append_system(state, msg), []}
  end

  def handle({:command, {:memory, {:query, query}}}, _text, state) do
    case Worth.Memory.Manager.search(query, workspace: state.workspace, limit: 5) do
      {:ok, %{entries: entries}} when is_list(entries) and entries != [] ->
        lines =
          entries
          |> Enum.map(fn e -> "  [#{Float.round(e.confidence || 0.5, 2)}] #{e.content}" end)
          |> Enum.join("\n")

        {append_system(state, "Memory results for '#{query}':\n#{lines}"), []}

      _ ->
        {append_system(state, "No memories found for '#{query}'"), []}
    end
  end

  def handle({:command, {:memory, {:note, note}}}, _text, state) do
    case Worth.Memory.Manager.working_push(note,
           workspace: state.workspace,
           importance: 0.5,
           metadata: %{entry_type: "note", role: "user"}
         ) do
      {:ok, _} ->
        {append_system(state, "Note added to working memory."), []}

      {:error, reason} ->
        {append_error(state, "Failed to add note: #{inspect(reason)}"), []}
    end
  end

  def handle({:command, {:memory, :recent}}, _text, state) do
    case Worth.Memory.Manager.recent(workspace: state.workspace, limit: 10) do
      {:ok, entries} when is_list(entries) and entries != [] ->
        lines =
          entries
          |> Enum.map(fn e -> "  [#{e.entry_type}] #{String.slice(e.content, 0, 80)}" end)
          |> Enum.join("\n")

        {append_system(state, "Recent memories:\n#{lines}"), []}

      _ ->
        {append_system(state, "No recent memories."), []}
    end
  end

  def handle({:command, {:skill, :list}}, _text, state) do
    skills = Worth.Skill.Registry.all()

    if skills == [] do
      {append_system(state, "No skills loaded."), []}
    else
      lines =
        skills
        |> Enum.map(fn s ->
          loading = if s.loading == :always, do: "[always]", else: "[on-demand]"
          "  [#{s.trust_level}] #{loading} #{s.name}: #{String.slice(s.description, 0, 60)}"
        end)
        |> Enum.join("\n")

      {append_system(state, "Skills:\n#{lines}"), []}
    end
  end

  def handle({:command, {:skill, {:read, name}}}, _text, state) do
    case Worth.Skill.Service.read_body(name) do
      {:ok, body} ->
        preview = String.slice(body, 0, 500)
        {append_system(state, "Skill '#{name}':\n#{preview}"), []}

      {:error, reason} ->
        {append_error(state, "Failed to read skill: #{reason}"), []}
    end
  end

  def handle({:command, {:skill, {:remove, name}}}, _text, state) do
    case Worth.Skill.Service.remove(name) do
      {:ok, _} -> {append_system(state, "Skill '#{name}' removed."), []}
      {:error, reason} -> {append_error(state, reason), []}
    end
  end

  def handle({:command, {:skill, {:history, name}}}, _text, state) do
    case Worth.Brain.skill_history(name) do
      {:ok, versions} when is_list(versions) and versions != [] ->
        lines =
          versions
          |> Enum.map(fn {v, info} -> "  v#{v} (#{info.size} bytes)" end)
          |> Enum.join("\n")

        {append_system(state, "Skill '#{name}' versions:\n#{lines}"), []}

      _ ->
        {append_system(state, "No version history for '#{name}'."), []}
    end
  end

  def handle({:command, {:skill, {:rollback, name, version}}}, _text, state) do
    case Worth.Brain.skill_rollback(name, version) do
      {:ok, info} ->
        {append_system(state, "Skill '#{name}' rolled back to v#{info.rolled_back_to}."), []}

      {:error, reason} ->
        {append_error(state, reason), []}
    end
  end

  def handle({:command, {:skill, {:refine, name}}}, _text, state) do
    case Worth.Brain.skill_refine(name) do
      {:ok, :no_refinement_needed} ->
        {append_system(state, "Skill '#{name}' does not need refinement."), []}

      {:ok, info} ->
        {append_system(state, "Skill '#{name}' refined to v#{info.version}."), []}

      {:error, reason} ->
        {append_error(state, reason), []}
    end
  end

  def handle({:command, {:session, :list}}, _text, state) do
    case Worth.Brain.list_sessions() do
      {:ok, sessions} when is_list(sessions) and sessions != [] ->
        lines = sessions |> Enum.map(&"  #{&1}") |> Enum.join("\n")
        {append_system(state, "Sessions:\n#{lines}"), []}

      _ ->
        {append_system(state, "No sessions found."), []}
    end
  end

  def handle({:command, {:session, {:resume, session_id}}}, _text, state) do
    Worth.Brain.resume_session(session_id)
    state = append_system(state, "Resuming session: #{session_id}")
    {%{state | status: :running}, []}
  end

  def handle({:command, {:mcp, :list}}, _text, state) do
    connections = Worth.Brain.mcp_list()

    if connections == [] do
      {append_system(state, "No MCP servers connected."), []}
    else
      lines =
        connections
        |> Enum.map(fn c -> "  [#{c.status}] #{c.name} (#{c.tool_count} tools)" end)
        |> Enum.join("\n")

      {append_system(state, "MCP Servers:\n#{lines}"), []}
    end
  end

  def handle({:command, {:mcp, {:connect, name}}}, _text, state) do
    case Worth.Mcp.Config.get_server(name) do
      nil ->
        {append_error(state, "Server '#{name}' not configured. Add it to ~/.worth/config.exs"), []}

      config ->
        case Worth.Brain.mcp_connect(name, config) do
          {:ok, _} ->
            {append_system(state, "Connected to MCP server '#{name}'."), []}

          {:error, :already_connected} ->
            {append_system(state, "Already connected to '#{name}'."), []}

          {:error, reason} ->
            {append_error(state, "Failed to connect: #{inspect(reason)}"), []}
        end
    end
  end

  def handle({:command, {:mcp, {:disconnect, name}}}, _text, state) do
    case Worth.Brain.mcp_disconnect(name) do
      :ok ->
        {append_system(state, "Disconnected from '#{name}'."), []}

      {:error, :not_connected} ->
        {append_system(state, "Server '#{name}' was not connected."), []}
    end
  end

  def handle({:command, {:mcp, {:tools, name}}}, _text, state) do
    tools = Worth.Brain.mcp_tools(name)

    if tools == [] do
      {append_system(state, "No tools found for server '#{name}'."), []}
    else
      lines =
        tools
        |> Enum.map(fn t -> "  #{t["name"]}: #{String.slice(t["description"] || "", 0, 60)}" end)
        |> Enum.join("\n")

      {append_system(state, "Tools from #{name}:\n#{lines}"), []}
    end
  end

  def handle({:command, {:kit, {:search, query}}}, _text, state) do
    kit_exec("kit_search", %{"query" => query}, state)
  end

  def handle({:command, {:kit, {:install, owner, slug}}}, _text, state) do
    kit_exec("kit_install", %{"owner" => owner, "slug" => slug, "workspace" => state.workspace}, state)
  end

  def handle({:command, {:kit, :list}}, _text, state) do
    kit_exec("kit_list", %{}, state)
  end

  def handle({:command, {:kit, {:info, owner, slug}}}, _text, state) do
    kit_exec("kit_info", %{"owner" => owner, "slug" => slug}, state)
  end

  def handle({:command, {:provider, :list}}, _text, state) do
    providers = AgentEx.LLM.ProviderRegistry.list()

    if providers == [] do
      {append_system(state, "No providers registered."), []}
    else
      lines =
        providers
        |> Enum.map(fn p ->
          status = if p.status == :enabled, do: "enabled", else: "disabled"

          models =
            try do
              p.module.default_models() |> length()
            rescue
              _ -> "?"
            end

          "  [#{status}] #{p.module.label()} (#{p.id}) — #{models} models"
        end)
        |> Enum.join("\n")

      {append_system(state, "Providers:\n#{lines}"), []}
    end
  end

  def handle({:command, {:provider, {:enable, id}}}, _text, state) do
    case AgentEx.LLM.ProviderRegistry.enable(id) do
      :ok -> {append_system(state, "Provider #{id} enabled."), []}
      {:error, :not_found} -> {append_error(state, "Provider '#{id}' not found."), []}
    end
  end

  def handle({:command, {:provider, {:disable, id}}}, _text, state) do
    case AgentEx.LLM.ProviderRegistry.disable(id) do
      :ok -> {append_system(state, "Provider #{id} disabled."), []}
      {:error, :not_found} -> {append_error(state, "Provider '#{id}' not found."), []}
    end
  end

  def handle({:command, {:skill, :help}}, _text, state) do
    msg =
      "Skill commands:\n  /skill list\n  /skill read <name>\n  /skill remove <name>\n  /skill history <name>\n  /skill rollback <name> <version>\n  /skill refine <name>"

    {append_system(state, msg), []}
  end

  def handle({:command, {:unknown, cmd}}, _text, state) do
    {append_system(state, "Unknown command: #{cmd}. Type /help for available commands."), []}
  end

  def handle(:message, text, state) do
    send_to_brain(text)
    {%{state | status: :running, streaming_text: ""}, []}
  end

  # ----- helpers -----

  def send_to_brain(text) do
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

  defp kit_exec(name, args, state) do
    case Worth.Tools.Kits.execute(name, args, state.workspace) do
      {:ok, msg} -> {append_system(state, msg), []}
      {:error, reason} -> {append_error(state, reason), []}
    end
  end

  defp append_system(state, msg) do
    %{state | messages: state.messages ++ [{:system, msg}]}
  end

  defp append_error(state, msg) do
    %{state | messages: state.messages ++ [{:error, msg}]}
  end

  def help_text do
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
      /provider list       List registered providers
      /provider enable <id> Enable a provider
      /provider disable <id> Disable a provider
      Tab                  Toggle sidebar
      Up/Down              Command history
    """
  end
end
