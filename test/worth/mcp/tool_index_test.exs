defmodule Worth.Mcp.ToolIndexTest do
  use ExUnit.Case, async: false

  setup do
    Worth.Mcp.ToolIndex.init()
    on_exit(fn -> Worth.Mcp.ToolIndex.init() end)
  end

  describe "register_tools/2" do
    test "registers tools with namespaced keys" do
      tools = [
        %{"name" => "read_file", "description" => "Read a file"},
        %{"name" => "write_file", "description" => "Write a file"}
      ]

      :ok = Worth.Mcp.ToolIndex.register_tools("filesystem", tools)

      assert {:ok, "filesystem"} = Worth.Mcp.ToolIndex.find_server("read_file")
      assert {:ok, "filesystem"} = Worth.Mcp.ToolIndex.find_server("filesystem:read_file")
    end

    test "get_schema returns tool definition" do
      tools = [%{"name" => "search", "description" => "Search the web", "input_schema" => %{}}]
      Worth.Mcp.ToolIndex.register_tools("brave", tools)

      {:ok, schema} = Worth.Mcp.ToolIndex.get_schema("search")
      assert schema["name"] == "search"
    end
  end

  describe "unregister_server/1" do
    test "removes all tools for a server" do
      tools = [%{"name" => "query", "description" => "Query DB"}]
      Worth.Mcp.ToolIndex.register_tools("postgres", tools)
      :ok = Worth.Mcp.ToolIndex.unregister_server("postgres")
      assert {:error, :not_found} = Worth.Mcp.ToolIndex.find_server("query")
    end
  end

  describe "all_tools/0" do
    test "returns deduplicated tool list" do
      Worth.Mcp.ToolIndex.register_tools("s1", [%{"name" => "tool_a", "description" => "A"}])
      Worth.Mcp.ToolIndex.register_tools("s2", [%{"name" => "tool_b", "description" => "B"}])

      all = Worth.Mcp.ToolIndex.all_tools()
      names = Enum.map(all, & &1.name)
      assert "tool_a" in names
      assert "tool_b" in names
    end
  end

  describe "tools_for_server/1" do
    test "returns tools for specific server" do
      Worth.Mcp.ToolIndex.register_tools("myserver", [%{"name" => "foo", "description" => "Foo tool"}])
      tools = Worth.Mcp.ToolIndex.tools_for_server("myserver")
      assert length(tools) == 1
      assert hd(tools)["name"] == "foo"
    end
  end
end
