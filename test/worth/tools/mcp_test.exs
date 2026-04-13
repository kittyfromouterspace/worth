defmodule Worth.Tools.McpTest do
  use ExUnit.Case, async: false

  alias Worth.Mcp.ToolIndex
  alias Worth.Tools.Mcp

  setup do
    ToolIndex.init()
    Worth.Mcp.Registry.init()

    on_exit(fn ->
      ToolIndex.init()
      Worth.Mcp.Registry.init()
    end)
  end

  describe "definitions/0" do
    test "returns 5 tool definitions" do
      defs = Mcp.definitions()
      assert length(defs) == 5
      names = Enum.map(defs, & &1.name)
      assert "mcp_list_servers" in names
      assert "mcp_call_tool" in names
      assert "mcp_connect" in names
      assert "mcp_disconnect" in names
      assert "mcp_server_tools" in names
    end

    test "each definition has required fields" do
      Enum.each(Mcp.definitions(), fn d ->
        assert d.name
        assert d.description
        assert d.input_schema
      end)
    end
  end

  describe "execute/3" do
    test "mcp_list_servers returns formatted output" do
      {:ok, msg} = Mcp.execute("mcp_list_servers", %{}, "test")
      assert is_binary(msg)
    end

    test "mcp_list_servers lists connections" do
      Worth.Mcp.Registry.register("test-srv", self(), %{tool_count: 3, connected_at: DateTime.utc_now()})
      {:ok, msg} = Mcp.execute("mcp_list_servers", %{}, "test")
      assert msg =~ "test-srv"
      assert msg =~ "3 tools"
    after
      Worth.Mcp.Registry.unregister("test-srv")
    end

    test "mcp_server_tools returns tools" do
      ToolIndex.register_tools("test-srv", [
        %{"name" => "read", "description" => "Read something"},
        %{"name" => "write", "description" => "Write something"}
      ])

      {:ok, msg} = Mcp.execute("mcp_server_tools", %{"server" => "test-srv"}, "test")
      assert msg =~ "read"
      assert msg =~ "write"
    after
      ToolIndex.unregister_server("test-srv")
    end

    test "mcp_server_tools returns message for empty server" do
      {:ok, msg} = Mcp.execute("mcp_server_tools", %{"server" => "nonexistent"}, "test")
      assert msg =~ "No tools found"
    end

    test "mcp_disconnect handles not connected" do
      {:ok, msg} = Mcp.execute("mcp_disconnect", %{"server" => "unknown"}, "test")
      assert msg =~ "not connected"
    end
  end
end
