defmodule WorthWeb.Commands.WorkspaceCommands do
  import Phoenix.Component, only: [assign: 2]
  import WorthWeb.Commands.Helpers

  def handle({:workspace, :list}, socket) do
    workspaces = Worth.Workspace.Service.list()
    append_system(socket, "Workspaces: #{Enum.join(workspaces, ", ")}")
  end

  def handle({:workspace, {:switch, name}}, socket) do
    old_workspace = socket.assigns.workspace
    Phoenix.PubSub.unsubscribe(Worth.PubSub, "workspace:#{old_workspace}")
    Phoenix.PubSub.subscribe(Worth.PubSub, "workspace:#{name}")

    socket = assign(socket, workspace: name, workspaces: Worth.Workspace.Service.list())
    append_system(socket, "Switched to workspace: #{name}")
  end

  def handle({:workspace, {:new, name}}, socket) do
    case Worth.Workspace.Service.create(name) do
      {:ok, _path} ->
        old_workspace = socket.assigns.workspace
        Phoenix.PubSub.unsubscribe(Worth.PubSub, "workspace:#{old_workspace}")
        Phoenix.PubSub.subscribe(Worth.PubSub, "workspace:#{name}")

        socket = assign(socket, workspace: name, workspaces: Worth.Workspace.Service.list())
        append_system(socket, "Created and switched to workspace: #{name}")

      {:error, reason} ->
        append_error(socket, reason)
    end
  end

  def handle({:agent, :list}, socket) do
    agents = Worth.CodingAgents.discover()

    text =
      if Enum.empty?(agents) do
        "No coding agents found. Install Claude Code or OpenCode to use this feature."
      else
        agent_text =
          Enum.map_join(agents, "\n", fn a ->
            "  - #{a.display_name} (#{a.cli_name}) - #{if a.available, do: "available", else: "not available"}"
          end)

        "Available coding agents:\n#{agent_text}"
      end

    append_system(socket, text)
  end

  def handle({:agent, {:switch, protocol}}, socket) do
    workspace = socket.assigns.workspace

    case Worth.Brain.switch_to_coding_agent(workspace, protocol) do
      :ok ->
        agent_name = Worth.CodingAgents.display_name(protocol)
        append_system(assign(socket, mode: :coding_agent), "Switched to coding agent: #{agent_name}")

      {:error, :not_available} ->
        append_error(socket, "Coding agent not available. Make sure it's installed.")

      {:error, :unknown_protocol} ->
        append_error(socket, "Unknown coding agent. Use /agent list to see available agents.")
    end
  end

  def handle({:session, :list}, socket) do
    workspace = socket.assigns.workspace

    case Worth.Brain.list_sessions(workspace) do
      {:ok, sessions} when is_list(sessions) and sessions != [] ->
        lines = sessions |> Enum.map(&"  #{&1}") |> Enum.join("\n")
        append_system(socket, "Sessions:\n#{lines}")

      _ ->
        append_system(socket, "No sessions found.")
    end
  end

  def handle({:session, {:resume, session_id}}, socket) do
    workspace = socket.assigns.workspace
    Worth.Brain.resume_session(workspace, session_id)
    socket = append_system(socket, "Resuming session: #{session_id}")
    assign(socket, status: :running)
  end

  def handle({:kit, {:search, query}}, socket) do
    kit_exec("kit_search", %{"query" => query}, socket)
  end

  def handle({:kit, {:install, owner, slug}}, socket) do
    kit_exec("kit_install", %{"owner" => owner, "slug" => slug, "workspace" => socket.assigns.workspace}, socket)
  end

  def handle({:kit, :list}, socket) do
    kit_exec("kit_list", %{}, socket)
  end

  def handle({:kit, {:info, owner, slug}}, socket) do
    kit_exec("kit_info", %{"owner" => owner, "slug" => slug}, socket)
  end

  def handle({:setup, :show}, socket) do
    key =
      case Worth.Config.Setup.openrouter_key() do
        nil -> "(not set)"
        k -> "#{String.slice(k, 0, 8)}... (#{String.length(k)} chars)"
      end

    model = Worth.Config.Setup.embedding_model() || "(not set)"

    msg =
      "Setup status:\n  config file:     #{Worth.Config.Store.path()}\n  openrouter key:  #{key}\n  embedding model: #{model}"

    append_system(socket, msg)
  end

  def handle({:setup, :help}, socket) do
    append_system(socket,
      "Setup commands:\n  /setup                 Show current setup status\n  /setup openrouter <k>  Save OpenRouter API key\n  /setup embedding <m>   Set embedding model id"
    )
  end

  def handle({:setup, {:openrouter, key}}, socket) do
    case Worth.Config.Setup.set_openrouter_key(key) do
      :ok -> append_system(socket, "OpenRouter key saved to #{Worth.Config.Store.path()}.")
      {:error, :empty_key} -> append_error(socket, "OpenRouter key cannot be empty.")
    end
  end

  def handle({:setup, {:embedding, model}}, socket) do
    case Worth.Config.Setup.set_embedding_model(model) do
      :ok -> append_system(socket, "Embedding model set to #{model}.")
      {:error, :empty_model} -> append_error(socket, "Embedding model cannot be empty.")
    end
  end

  defp kit_exec(name, args, socket) do
    case Worth.Tools.Kits.execute(name, args, socket.assigns.workspace) do
      {:ok, msg} -> append_system(socket, msg)
      {:error, reason} -> append_error(socket, reason)
    end
  end
end
