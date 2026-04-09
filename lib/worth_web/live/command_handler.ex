defmodule WorthWeb.CommandHandler do
  @moduledoc """
  Handles slash commands in the LiveView context.
  Ported from Worth.UI.Commands.handle/3 to operate on socket assigns.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [stream: 4]

  alias WorthWeb.ChatLive

  def handle(:quit, _text, socket) do
    append_system(socket, "Use Ctrl+C in the terminal to stop Worth.")
  end

  def handle(:clear, _text, socket) do
    Worth.Metrics.reset()

    socket
    |> stream(:messages, [], reset: true)
    |> assign(streaming_text: "", cost: 0.0, turn: 0)
  end

  def handle(:cost, _text, socket) do
    append_system(socket, "Session cost: $#{Float.round(socket.assigns.cost, 4)} | Turns: #{socket.assigns.turn}")
  end

  def handle(:help, _text, socket) do
    append_system(socket, Worth.UI.Commands.help_text())
  end

  def handle({:mode, mode}, _text, socket) do
    Worth.Brain.switch_mode(mode)
    append_system(assign(socket, mode: mode), "Switched to #{mode} mode")
  end

  def handle({:agent, :list}, _text, socket) do
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

  def handle({:agent, {:switch, protocol}}, _text, socket) do
    case Worth.Brain.switch_to_coding_agent(protocol) do
      :ok ->
        agent_name = Worth.CodingAgents.display_name(protocol)
        append_system(assign(socket, mode: :coding_agent), "Switched to coding agent: #{agent_name}")

      {:error, :not_available} ->
        append_error(socket, "Coding agent not available. Make sure it's installed.")

      {:error, :unknown_protocol} ->
        append_error(socket, "Unknown coding agent. Use /agent list to see available agents.")
    end
  end

  def handle({:workspace, :list}, _text, socket) do
    workspaces = Worth.Workspace.Service.list()
    append_system(socket, "Workspaces: #{Enum.join(workspaces, ", ")}")
  end

  def handle({:workspace, {:switch, name}}, _text, socket) do
    Worth.Brain.switch_workspace(name)
    append_system(assign(socket, workspace: name), "Switched to workspace: #{name}")
  end

  def handle({:workspace, {:new, name}}, _text, socket) do
    case Worth.Workspace.Service.create(name) do
      {:ok, _path} ->
        Worth.Brain.switch_workspace(name)
        append_system(assign(socket, workspace: name), "Created and switched to workspace: #{name}")

      {:error, reason} ->
        append_error(socket, reason)
    end
  end

  def handle({:status, _}, _text, socket) do
    status = Worth.Brain.get_status()

    msg =
      "Mode: #{status.mode} | Profile: #{status.profile} | Workspace: #{status.workspace} | Cost: $#{Float.round(status.cost, 3)}"

    append_system(socket, msg)
  end

  def handle({:memory, {:query, query}}, _text, socket) do
    case Worth.Memory.Manager.search(query, workspace: socket.assigns.workspace, limit: 5) do
      {:ok, %{entries: entries}} when is_list(entries) and entries != [] ->
        lines =
          entries
          |> Enum.map(fn e -> "  [#{Float.round(e.confidence || 0.5, 2)}] #{e.content}" end)
          |> Enum.join("\n")

        append_system(socket, "Memory results for '#{query}':\n#{lines}")

      _ ->
        append_system(socket, "No memories found for '#{query}'")
    end
  end

  def handle({:memory, {:note, note}}, _text, socket) do
    case Worth.Memory.Manager.working_push(note,
           workspace: socket.assigns.workspace,
           importance: 0.5,
           metadata: %{entry_type: "note", role: "user"}
         ) do
      {:ok, _} ->
        append_system(socket, "Note added to working memory.")

      {:error, reason} ->
        append_error(socket, "Failed to add note: #{inspect(reason)}")
    end
  end

  def handle({:memory, :reembed}, _text, socket) do
    parent = self()

    Task.start(fn ->
      result = Worth.Tools.Memory.Reembed.run([])
      send(parent, {:reembed_done, result})
    end)

    append_system(socket, "Re-embedding memories in the background... (results will follow)")
  end

  def handle({:memory, :recent}, _text, socket) do
    case Worth.Memory.Manager.recent(workspace: socket.assigns.workspace, limit: 10) do
      {:ok, entries} when is_list(entries) and entries != [] ->
        lines =
          entries
          |> Enum.map(fn e -> "  [#{e.entry_type}] #{String.slice(e.content, 0, 80)}" end)
          |> Enum.join("\n")

        append_system(socket, "Recent memories:\n#{lines}")

      _ ->
        append_system(socket, "No recent memories.")
    end
  end

  def handle({:skill, :list}, _text, socket) do
    skills = Worth.Skill.Registry.all()

    if skills == [] do
      append_system(socket, "No skills loaded.")
    else
      lines =
        skills
        |> Enum.map(fn s ->
          loading = if s.loading == :always, do: "[always]", else: "[on-demand]"
          "  [#{s.trust_level}] #{loading} #{s.name}: #{String.slice(s.description, 0, 60)}"
        end)
        |> Enum.join("\n")

      append_system(socket, "Skills:\n#{lines}")
    end
  end

  def handle({:skill, {:read, name}}, _text, socket) do
    case Worth.Skill.Service.read_body(name) do
      {:ok, body} ->
        preview = String.slice(body, 0, 500)
        append_system(socket, "Skill '#{name}':\n#{preview}")

      {:error, reason} ->
        append_error(socket, "Failed to read skill: #{reason}")
    end
  end

  def handle({:skill, {:remove, name}}, _text, socket) do
    case Worth.Skill.Service.remove(name) do
      {:ok, _} -> append_system(socket, "Skill '#{name}' removed.")
      {:error, reason} -> append_error(socket, reason)
    end
  end

  def handle({:skill, {:history, name}}, _text, socket) do
    case Worth.Brain.skill_history(name) do
      {:ok, versions} when is_list(versions) and versions != [] ->
        lines =
          versions
          |> Enum.map(fn {v, info} -> "  v#{v} (#{info.size} bytes)" end)
          |> Enum.join("\n")

        append_system(socket, "Skill '#{name}' versions:\n#{lines}")

      _ ->
        append_system(socket, "No version history for '#{name}'.")
    end
  end

  def handle({:skill, {:rollback, name, version}}, _text, socket) do
    case Worth.Brain.skill_rollback(name, version) do
      {:ok, info} ->
        append_system(socket, "Skill '#{name}' rolled back to v#{info.rolled_back_to}.")

      {:error, reason} ->
        append_error(socket, reason)
    end
  end

  def handle({:skill, {:refine, name}}, _text, socket) do
    case Worth.Brain.skill_refine(name) do
      {:ok, :no_refinement_needed} ->
        append_system(socket, "Skill '#{name}' does not need refinement.")

      {:ok, info} ->
        append_system(socket, "Skill '#{name}' refined to v#{info.version}.")

      {:error, reason} ->
        append_error(socket, reason)
    end
  end

  def handle({:skill, :help}, _text, socket) do
    msg =
      "Skill commands:\n  /skill list\n  /skill read <name>\n  /skill remove <name>\n  /skill history <name>\n  /skill rollback <name> <version>\n  /skill refine <name>"

    append_system(socket, msg)
  end

  def handle({:session, :list}, _text, socket) do
    case Worth.Brain.list_sessions() do
      {:ok, sessions} when is_list(sessions) and sessions != [] ->
        lines = sessions |> Enum.map(&"  #{&1}") |> Enum.join("\n")
        append_system(socket, "Sessions:\n#{lines}")

      _ ->
        append_system(socket, "No sessions found.")
    end
  end

  def handle({:session, {:resume, session_id}}, _text, socket) do
    Worth.Brain.resume_session(session_id)
    socket = append_system(socket, "Resuming session: #{session_id}")
    assign(socket, status: :running)
  end

  def handle({:mcp, :list}, _text, socket) do
    connections = Worth.Brain.mcp_list()

    if connections == [] do
      append_system(socket, "No MCP servers connected.")
    else
      lines =
        connections
        |> Enum.map(fn c -> "  [#{c.status}] #{c.name} (#{c.tool_count} tools)" end)
        |> Enum.join("\n")

      append_system(socket, "MCP Servers:\n#{lines}")
    end
  end

  def handle({:mcp, {:connect, name}}, _text, socket) do
    case Worth.Mcp.Config.get_server(name) do
      nil ->
        append_error(socket, "Server '#{name}' not configured. Add it to ~/.worth/config.exs")

      config ->
        case Worth.Brain.mcp_connect(name, config) do
          {:ok, _} ->
            append_system(socket, "Connected to MCP server '#{name}'.")

          {:error, :already_connected} ->
            append_system(socket, "Already connected to '#{name}'.")

          {:error, reason} ->
            append_error(socket, "Failed to connect: #{inspect(reason)}")
        end
    end
  end

  def handle({:mcp, {:disconnect, name}}, _text, socket) do
    case Worth.Brain.mcp_disconnect(name) do
      :ok ->
        append_system(socket, "Disconnected from '#{name}'.")

      {:error, :not_connected} ->
        append_system(socket, "Server '#{name}' was not connected.")
    end
  end

  def handle({:mcp, {:tools, name}}, _text, socket) do
    tools = Worth.Brain.mcp_tools(name)

    if tools == [] do
      append_system(socket, "No tools found for server '#{name}'.")
    else
      lines =
        tools
        |> Enum.map(fn t -> "  #{t["name"]}: #{String.slice(t["description"] || "", 0, 60)}" end)
        |> Enum.join("\n")

      append_system(socket, "Tools from #{name}:\n#{lines}")
    end
  end

  def handle({:kit, {:search, query}}, _text, socket) do
    kit_exec("kit_search", %{"query" => query}, socket)
  end

  def handle({:kit, {:install, owner, slug}}, _text, socket) do
    kit_exec("kit_install", %{"owner" => owner, "slug" => slug, "workspace" => socket.assigns.workspace}, socket)
  end

  def handle({:kit, :list}, _text, socket) do
    kit_exec("kit_list", %{}, socket)
  end

  def handle({:kit, {:info, owner, slug}}, _text, socket) do
    kit_exec("kit_info", %{"owner" => owner, "slug" => slug}, socket)
  end

  def handle({:provider, :list}, _text, socket) do
    providers = AgentEx.LLM.ProviderRegistry.list()

    if providers == [] do
      append_system(socket, "No providers registered.")
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

          "  [#{status}] #{p.module.label()} (#{p.id}) - #{models} models"
        end)
        |> Enum.join("\n")

      append_system(socket, "Providers:\n#{lines}")
    end
  end

  def handle({:provider, {:enable, id}}, _text, socket) do
    case AgentEx.LLM.ProviderRegistry.enable(id) do
      :ok -> append_system(socket, "Provider #{id} enabled.")
      {:error, :not_found} -> append_error(socket, "Provider '#{id}' not found.")
    end
  end

  def handle({:provider, {:disable, id}}, _text, socket) do
    case AgentEx.LLM.ProviderRegistry.disable(id) do
      :ok -> append_system(socket, "Provider #{id} disabled.")
      {:error, :not_found} -> append_error(socket, "Provider '#{id}' not found.")
    end
  end

  def handle({:catalog, :refresh}, _text, socket) do
    AgentEx.LLM.Catalog.refresh()
    info = AgentEx.LLM.Catalog.info()
    append_system(socket, "Catalog refresh triggered. #{info.model_count} models loaded.")
  end

  def handle(:usage, _text, socket) do
    metrics = Worth.Metrics.session()
    snapshots = AgentEx.LLM.UsageManager.snapshot()

    provider_section =
      if snapshots == [] do
        "Providers: (no quota endpoints)"
      else
        lines =
          Enum.map_join(snapshots, "\n", fn s ->
            credit =
              case s.credits do
                %{used: u, limit: l} -> " - credits $#{Float.round(u, 2)}/$#{Float.round(l, 2)}"
                _ -> ""
              end

            "  #{s.label}#{credit}"
          end)

        "Providers:\n#{lines}"
      end

    by_provider =
      case Map.to_list(metrics.by_provider) do
        [] ->
          ""

        entries ->
          lines =
            Enum.map_join(entries, "\n", fn {provider, p} ->
              "  #{provider}  $#{Float.round(p.cost, 4)} (#{p.calls} calls)"
            end)

          "\nBy provider:\n#{lines}"
      end

    msg =
      "#{provider_section}\nSession: $#{Float.round(metrics.cost, 4)} | #{metrics.calls} calls | #{metrics.input_tokens} in / #{metrics.output_tokens} out#{by_provider}"

    append_system(socket, String.trim(msg))
  end

  def handle({:usage, :refresh}, _text, socket) do
    AgentEx.LLM.UsageManager.refresh()
    append_system(socket, "Usage refresh triggered.")
  end

  def handle({:setup, :show}, _text, socket) do
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

  def handle({:setup, :help}, _text, socket) do
    msg =
      "Setup commands:\n  /setup                 Show current setup status\n  /setup openrouter <k>  Save OpenRouter API key\n  /setup embedding <m>   Set embedding model id"

    append_system(socket, msg)
  end

  def handle({:setup, {:openrouter, key}}, _text, socket) do
    case Worth.Config.Setup.set_openrouter_key(key) do
      :ok -> append_system(socket, "OpenRouter key saved to #{Worth.Config.Store.path()}.")
      {:error, :empty_key} -> append_error(socket, "OpenRouter key cannot be empty.")
    end
  end

  def handle({:setup, {:embedding, model}}, _text, socket) do
    case Worth.Config.Setup.set_embedding_model(model) do
      :ok -> append_system(socket, "Embedding model set to #{model}.")
      {:error, :empty_model} -> append_error(socket, "Embedding model cannot be empty.")
    end
  end

  def handle({:unknown, cmd}, _text, socket) do
    append_system(socket, "Unknown command: #{cmd}. Type /help for available commands.")
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp kit_exec(name, args, socket) do
    case Worth.Tools.Kits.execute(name, args, socket.assigns.workspace) do
      {:ok, msg} -> append_system(socket, msg)
      {:error, reason} -> append_error(socket, reason)
    end
  end

  defp append_system(socket, msg) do
    ChatLive.append_system_message(socket, msg)
  end

  defp append_error(socket, msg) do
    Phoenix.LiveView.stream_insert(socket, :messages, %{
      id: System.unique_integer([:positive]) |> to_string(),
      type: :error,
      content: msg
    })
  end
end
