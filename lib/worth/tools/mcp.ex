defmodule Worth.Tools.Mcp do
  @moduledoc false
  alias Worth.Mcp.Broker

  def definitions do
    [
      %{
        name: "mcp_list_servers",
        description: "List all connected MCP servers and their status",
        input_schema: %{
          type: "object",
          properties: %{},
          required: []
        }
      },
      %{
        name: "mcp_server_tools",
        description: "List tools available from a specific MCP server",
        input_schema: %{
          type: "object",
          properties: %{
            server: %{type: "string", description: "Server name"}
          },
          required: ["server"]
        }
      },
      %{
        name: "mcp_call_tool",
        description: "Execute a tool on a connected MCP server",
        input_schema: %{
          type: "object",
          properties: %{
            server: %{type: "string", description: "Server name"},
            tool: %{type: "string", description: "Tool name (without server prefix)"},
            arguments: %{type: "object", description: "Tool arguments"}
          },
          required: ["server", "tool"]
        }
      },
      %{
        name: "mcp_connect",
        description: "Connect to an MCP server",
        input_schema: %{
          type: "object",
          properties: %{
            name: %{type: "string", description: "Server name"},
            type: %{type: "string", enum: ["stdio", "streamable_http"]},
            command: %{type: "string", description: "Command for stdio transport"},
            args: %{type: "array", items: %{type: "string"}, description: "Command arguments"},
            url: %{type: "string", description: "URL for HTTP transport"}
          },
          required: ["name", "type"]
        }
      },
      %{
        name: "mcp_disconnect",
        description: "Disconnect from an MCP server",
        input_schema: %{
          type: "object",
          properties: %{
            server: %{type: "string", description: "Server name"}
          },
          required: ["server"]
        }
      }
    ]
  end

  def execute("mcp_list_servers", _args, _workspace) do
    connections = Broker.list_connections()

    lines =
      Enum.map(connections, fn c -> "  [#{c.status}] #{c.name} (#{c.tool_count} tools)" end)

    if lines == [] do
      {:ok, "No MCP servers connected."}
    else
      {:ok, "MCP Servers:\n" <> Enum.join(lines, "\n")}
    end
  end

  def execute("mcp_server_tools", %{"server" => server}, _workspace) do
    tools = Worth.Mcp.ToolIndex.tools_for_server(server)

    if tools == [] do
      {:ok, "No tools found for server '#{server}'."}
    else
      lines =
        Enum.map(tools, fn t ->
          desc = t["description"] || ""
          "  #{t["name"]}: #{String.slice(desc, 0, 80)}"
        end)

      {:ok, "Tools from #{server}:\n" <> Enum.join(lines, "\n")}
    end
  end

  def execute("mcp_call_tool", %{"server" => server, "tool" => tool} = args, _workspace) do
    tool_args = Map.get(args, "arguments", %{})
    namespaced = "#{server}:#{tool}"

    case Worth.Mcp.Gateway.execute(namespaced, tool_args) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, "MCP tool error: #{reason}"}
    end
  end

  def execute("mcp_connect", args, _workspace) do
    name = args["name"]
    type = args["type"]

    config = build_connect_config(type, args)

    case Broker.connect(name, config) do
      {:ok, _} -> {:ok, "Connected to MCP server '#{name}'."}
      {:error, :already_connected} -> {:ok, "Already connected to '#{name}'."}
      {:error, reason} -> {:error, "Failed to connect: #{inspect(reason)}"}
    end
  end

  def execute("mcp_disconnect", %{"server" => server}, _workspace) do
    case Broker.disconnect(server) do
      :ok -> {:ok, "Disconnected from '#{server}'."}
      {:error, :not_connected} -> {:ok, "Server '#{server}' was not connected."}
    end
  end

  def execute(_name, _args, _workspace) do
    {:error, "Unknown MCP tool"}
  end

  defp build_connect_config("stdio", args) do
    %{
      "type" => "stdio",
      "command" => args["command"],
      "args" => args["args"] || [],
      "autoconnect" => false
    }
  end

  defp build_connect_config("streamable_http", args) do
    %{
      "type" => "streamable_http",
      "url" => args["url"],
      "mcp_path" => args["mcp_path"] || "/",
      "autoconnect" => false
    }
  end

  defp build_connect_config(_type, args), do: args
end
