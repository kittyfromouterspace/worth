defmodule Worth.UI.Commands do
  @moduledoc """
  Slash command parser. Pure function — no UI dependencies.
  Used by WorthWeb.CommandHandler for dispatch.
  """

  def parse(text) do
    parts = String.split(String.trim(text))

    case parts do
      ["/quit"] -> {:command, :quit}
      ["/clear"] -> {:command, :clear}
      ["/cost"] -> {:command, :cost}
      ["/help"] -> {:command, :help}
      ["/status"] -> {:command, {:status, nil}}
      ["/settings"] -> {:command, :settings}
      ["/usage"] -> {:command, :usage}
      ["/usage", "refresh"] -> {:command, {:usage, :refresh}}
      ["/setup"] -> {:command, {:setup, :show}}
      ["/setup" | rest] -> parse_setup(Enum.join(rest, " "))
      ["/mode", mode] -> parse_mode(mode)
      # Workspace
      ["/workspace", "list"] -> {:command, {:workspace, :list}}
      ["/workspace", "switch", name] -> {:command, {:workspace, {:switch, name}}}
      ["/workspace", "new", name] -> {:command, {:workspace, {:new, name}}}
      # Agent
      ["/agent", "list"] -> {:command, {:agent, :list}}
      ["/agent", "switch", name] -> {:command, {:agent, {:switch, String.to_atom(name)}}}
      # Memory (note can have multiple words)
      ["/memory", "query" | query_parts] -> {:command, {:memory, {:query, Enum.join(query_parts, " ")}}}
      ["/memory", "note" | note_parts] -> {:command, {:memory, {:note, Enum.join(note_parts, " ")}}}
      ["/memory", "recent"] -> {:command, {:memory, :recent}}
      ["/memory", "reembed"] -> {:command, {:memory, :reembed}}
      # Skill
      ["/skill", "list"] -> {:command, {:skill, :list}}
      ["/skill", "read", name] -> {:command, {:skill, {:read, name}}}
      ["/skill", "remove", name] -> {:command, {:skill, {:remove, name}}}
      ["/skill", "history", name] -> {:command, {:skill, {:history, name}}}
      ["/skill", "rollback", name, version] -> parse_rollback(name, version)
      ["/skill", "refine", name] -> {:command, {:skill, {:refine, name}}}
      ["/skill" | _] -> {:command, {:skill, :help}}
      # Session
      ["/session", "list"] -> {:command, {:session, :list}}
      ["/session", "resume", session_id] -> {:command, {:session, {:resume, session_id}}}
      # MCP
      ["/mcp", "list"] -> {:command, {:mcp, :list}}
      ["/mcp", "connect", name] -> {:command, {:mcp, {:connect, name}}}
      ["/mcp", "disconnect", name] -> {:command, {:mcp, {:disconnect, name}}}
      ["/mcp", "tools", name] -> {:command, {:mcp, {:tools, name}}}
      # Kit (search query can have multiple words)
      ["/kit", "search" | query_parts] -> {:command, {:kit, {:search, Enum.join(query_parts, " ")}}}
      ["/kit", "install", owner_slash_slug] -> parse_owner_slug(:install, owner_slash_slug)
      ["/kit", "list"] -> {:command, {:kit, :list}}
      ["/kit", "info", owner_slash_slug] -> parse_owner_slug(:info, owner_slash_slug)
      # Provider
      ["/provider", "list"] -> {:command, {:provider, :list}}
      ["/provider", "enable", id] -> {:command, {:provider, {:enable, String.to_atom(id)}}}
      ["/provider", "disable", id] -> {:command, {:provider, {:disable, String.to_atom(id)}}}
      ["/catalog", "refresh"] -> {:command, {:catalog, :refresh}}
      # Unknown slash command
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

  defp parse_setup(rest) do
    case String.split(rest, " ", parts: 2) do
      ["openrouter", key] -> {:command, {:setup, {:openrouter, key}}}
      ["embedding", model] -> {:command, {:setup, {:embedding, model}}}
      ["show"] -> {:command, {:setup, :show}}
      _ -> {:command, {:setup, :help}}
    end
  end

  defp parse_owner_slug(action, owner_slash_slug) do
    case String.split(owner_slash_slug, "/", parts: 2) do
      [owner, slug] -> {:command, {:kit, {action, owner, slug}}}
      _ -> {:command, {:unknown, "/kit #{action} #{owner_slash_slug}"}}
    end
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
      /memory reembed      Re-embed all stored memories with the current model
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
      /catalog refresh     Refresh model catalog from providers
      /usage               Show provider quota and session cost
      /usage refresh       Refresh usage snapshots
      /settings            Open settings panel (API keys, preferences)
      /setup               Show setup status
      /setup openrouter <k> Save OpenRouter API key
      /setup embedding <m> Set embedding model id
      Tab                  Toggle sidebar
    """
  end
end
