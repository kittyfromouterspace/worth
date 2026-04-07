defmodule Worth.Mcp.ConfigTest do
  use ExUnit.Case, async: false

  describe "build_transport_opts/1" do
    test "builds stdio transport opts" do
      config = %{"type" => "stdio", "command" => "npx", "args" => ["-y", "some-server"]}
      {:stdio, opts} = Worth.Mcp.Config.build_transport_opts(config)
      assert opts[:command] == "npx"
      assert opts[:args] == ["-y", "some-server"]
    end

    test "builds streamable_http transport opts" do
      config = %{"type" => "streamable_http", "url" => "http://localhost:8000", "mcp_path" => "/mcp"}
      {:streamable_http, opts} = Worth.Mcp.Config.build_transport_opts(config)
      assert opts[:url] == "http://localhost:8000"
      assert opts[:mcp_path] == "/mcp"
    end

    test "defaults to stdio" do
      config = %{"command" => "node"}
      {:stdio, opts} = Worth.Mcp.Config.build_transport_opts(config)
      assert opts[:command] == "node"
    end

    test "returns error for unknown type" do
      assert {:error, _} = Worth.Mcp.Config.build_transport_opts(%{"type" => "unknown"})
    end

    test "resolves env variables" do
      System.put_env("WORTH_TEST_MCP_KEY", "test-key-123")
      config = %{"type" => "stdio", "command" => "npx", "env" => %{"API_KEY" => %{"env" => "WORTH_TEST_MCP_KEY"}}}
      {:stdio, opts} = Worth.Mcp.Config.build_transport_opts(config)
      assert opts[:env]["API_KEY"] == "test-key-123"
    after
      System.delete_env("WORTH_TEST_MCP_KEY")
    end
  end

  describe "load/1" do
    test "returns empty map when no config file exists" do
      result = Worth.Mcp.Config.load("/nonexistent/path")
      assert is_map(result)
    end
  end

  describe "autoconnect_servers/1" do
    test "returns empty list when no servers configured" do
      result = Worth.Mcp.Config.autoconnect_servers("/nonexistent/path")
      assert result == []
    end
  end
end
