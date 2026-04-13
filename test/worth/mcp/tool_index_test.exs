defmodule Worth.Mcp.ToolIndexTest do
  use ExUnit.Case, async: false

  alias Worth.Mcp.ToolIndex

  setup do
    ToolIndex.init()
    on_exit(fn -> ToolIndex.init() end)
  end

  describe "register_tools/2" do
    test "registers tools with namespaced keys" do
      tools = [
        %{"name" => "read_file", "description" => "Read a file"},
        %{"name" => "write_file", "description" => "Write a file"}
      ]

      :ok = ToolIndex.register_tools("filesystem", tools)

      assert {:ok, "filesystem"} = ToolIndex.find_server("read_file")
      assert {:ok, "filesystem"} = ToolIndex.find_server("filesystem:read_file")
    end

    test "get_schema returns tool definition" do
      tools = [%{"name" => "search", "description" => "Search the web", "input_schema" => %{}}]
      ToolIndex.register_tools("brave", tools)

      {:ok, schema} = ToolIndex.get_schema("search")
      assert schema["name"] == "search"
    end
  end

  describe "unregister_server/1" do
    test "removes all tools for a server" do
      tools = [%{"name" => "query", "description" => "Query DB"}]
      ToolIndex.register_tools("postgres", tools)
      :ok = ToolIndex.unregister_server("postgres")
      assert {:error, :not_found} = ToolIndex.find_server("query")
    end
  end

  describe "all_tools/0" do
    test "returns deduplicated tool list" do
      ToolIndex.register_tools("s1", [%{"name" => "tool_a", "description" => "A"}])
      ToolIndex.register_tools("s2", [%{"name" => "tool_b", "description" => "B"}])

      all = ToolIndex.all_tools()
      names = Enum.map(all, & &1.name)
      assert "tool_a" in names
      assert "tool_b" in names
    end
  end

  describe "tools_for_server/1" do
    test "returns tools for specific server" do
      ToolIndex.register_tools("myserver", [%{"name" => "foo", "description" => "Foo tool"}])
      tools = ToolIndex.tools_for_server("myserver")
      assert length(tools) == 1
      assert hd(tools)["name"] == "foo"
    end
  end
end
