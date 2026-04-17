defmodule Worth.CodingAgents do
  @moduledoc """
  Service for discovering and managing local coding agent CLIs.

  Supports auto-discovery of installed coding agents (Claude Code, OpenCode, etc.)
  and integrates them with Agentic's pluggable protocol infrastructure.
  """

  require Logger

  alias Agentic.Protocol.ACP.Discovery

  @doc "Discover all available coding agents on the system."
  def discover do
    Discovery.known_agents()
    |> Enum.filter(fn entry -> System.find_executable(entry.command) != nil end)
    |> Enum.map(fn entry ->
      %{
        cli_name: entry.command,
        protocol: entry.name,
        display_name: entry.display,
        available: true
      }
    end)
  end

  @doc "Check if a specific coding agent is available."
  def available?(protocol) do
    case Discovery.lookup_known(protocol) do
      nil -> false
      entry -> System.find_executable(entry.command) != nil
    end
  end

  @doc "Get the protocol config for a given protocol atom."
  def protocol_config(protocol) do
    case Discovery.lookup_known(protocol) do
      nil -> nil
      entry -> %{cli_name: entry.command, protocol: entry.name, display_name: entry.display}
    end
  end

  @doc "Get the Agentic profile atom for a coding agent."
  def profile_for(protocol) do
    case protocol do
      :claude -> :claude_code
      :claude_code -> :claude_code
      :codex -> :codex
      # Everything else (opencode, kimi, gemini, cursor, goose, qwen, ...)
      # runs over the generic Agent Client Protocol. Each CLI's specific
      # launch command comes from `backend_config/2` via the Discovery DB.
      _ -> :acp
    end
  end

  @doc "Get the backend config for ACP-based coding agents."
  def backend_config(protocol, workspace \\ File.cwd!()) do
    case Discovery.lookup_known(protocol) do
      nil ->
        %{workspace: workspace}

      entry ->
        %{
          command: entry.command,
          args: entry.args,
          workspace: workspace
        }
    end
  end

  @doc "List all registered protocol names (from Agentic Registry)."
  def list_registered do
    Agentic.Protocol.Registry.for_transport(:local_agent)
  end

  @doc "Check if a protocol is both registered and available."
  def active?(protocol) do
    Agentic.Protocol.Registry.available?(protocol)
  end

  @doc "Register a protocol with Agentic.Registry."
  def register_protocol(protocol_module, protocol_atom) do
    name = inspect(protocol_atom)

    case Agentic.Protocol.Registry.lookup(protocol_atom) do
      {:ok, _} ->
        Logger.info("Protocol #{name} already registered")
        :ok

      :error ->
        Agentic.Protocol.Registry.register(protocol_atom, protocol_module)
        Logger.info("Registered coding agent protocol: #{name}")
    end
  end

  @doc "Auto-discover and register all available coding agents, adding them to config."
  def auto_register do
    discovered = discover()

    # Ensure generic ACP protocol is registered
    register_protocol(Agentic.Protocol.ACP, {:acp, :generic})

    for agent <- discovered do
      case agent.protocol do
        :claude ->
          register_protocol(Agentic.Protocol.ClaudeCode, :claude_code)
          add_to_config(:claude_code, "Claude Code")

        :claude_code ->
          register_protocol(Agentic.Protocol.ClaudeCode, :claude_code)
          add_to_config(:claude_code, "Claude Code")

        :codex ->
          register_protocol(Agentic.Protocol.Codex, :codex)
          add_to_config(:codex, "Codex CLI")

        protocol ->
          # Register ACP-based agents under {:acp, protocol}
          register_protocol(Agentic.Protocol.ACP, {:acp, protocol})
          add_to_config(protocol, agent.display_name)
      end
    end

    {:ok, discovered}
  end

  @doc "Add a coding agent to the local config if not already present."
  def add_to_config(protocol, display_name) do
    config = Worth.Config.get_all()
    existing = config[:coding_agents] || []

    if Enum.any?(existing, &(&1[:protocol] == protocol)) do
      Logger.info("Coding agent #{display_name} already in config")
      :ok
    else
      new_agent = %{
        protocol: protocol,
        name: display_name,
        enabled: true
      }

      Worth.Config.put_setting([:coding_agents], existing ++ [new_agent], persist: false)
      Logger.info("Added coding agent to config: #{display_name}")
    end
  end

  @doc """
  Return the resolved private directories (config, logs, cache) for a coding agent.

  These are OS-dependent paths that the agent needs access to for its own
  configuration, skills, and logs. They do NOT include the Worth data directory.
  """
  def agent_private_dirs(protocol) when is_atom(protocol) do
    discovered =
      case Discovery.agent_directories(protocol) do
        nil -> []
        dirs -> dirs.config ++ dirs.logs ++ dirs.cache
      end

    (discovered ++ extra_agent_paths(protocol))
    |> Enum.filter(&File.exists?/1)
    |> Enum.uniq()
  end

  # Companion files/dirs the discovery database doesn't capture but the
  # CLI still expects at its usual location (e.g. ~/.claude.json).
  defp extra_agent_paths(:claude), do: extra_agent_paths(:claude_code)

  defp extra_agent_paths(:claude_code) do
    [Path.expand("~/.claude.json"), Path.expand("~/.claude.json.backup")]
  end

  # asdf-managed CLIs fall back to $HOME/.tool-versions when they can't
  # walk up to a nearer one, so surface that file (and any local asdf
  # config) into the sandbox.
  defp extra_agent_paths(:codex) do
    [Path.expand("~/.tool-versions"), Path.expand("~/.asdfrc")]
  end

  defp extra_agent_paths(_), do: []

  @doc "Convert a protocol atom to a display-friendly name."
  def display_name(protocol) when is_atom(protocol) do
    case Discovery.lookup_known(protocol) do
      nil -> Atom.to_string(protocol)
      entry -> entry.display
    end
  end

  def display_name(other), do: inspect(other)
end
