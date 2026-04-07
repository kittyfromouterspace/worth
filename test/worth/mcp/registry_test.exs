defmodule Worth.Mcp.RegistryTest do
  use ExUnit.Case, async: false

  setup do
    Worth.Mcp.Registry.init()
    on_exit(fn -> Worth.Mcp.Registry.init() end)
  end

  describe "register/3 and lookup/1" do
    test "registers and looks up a server" do
      :ok = Worth.Mcp.Registry.register("test-server", self(), %{tool_count: 5})
      {:ok, pid, meta} = Worth.Mcp.Registry.lookup("test-server")
      assert pid == self()
      assert meta.tool_count == 5
    end

    test "returns not_found for unknown server" do
      assert {:error, :not_found} = Worth.Mcp.Registry.lookup("unknown")
    end

    test "unregisters a server" do
      Worth.Mcp.Registry.register("temp-server", self())
      :ok = Worth.Mcp.Registry.unregister("temp-server")
      assert {:error, :not_found} = Worth.Mcp.Registry.lookup("temp-server")
    end
  end

  describe "lookup_client/1" do
    test "returns just the pid" do
      Worth.Mcp.Registry.register("client-test", self())
      {:ok, pid} = Worth.Mcp.Registry.lookup_client("client-test")
      assert pid == self()
    end
  end

  describe "update_meta/2" do
    test "updates metadata for existing server" do
      Worth.Mcp.Registry.register("meta-test", self(), %{status: :ok})
      :ok = Worth.Mcp.Registry.update_meta("meta-test", %{status: :updated, tool_count: 3})
      {:ok, _pid, meta} = Worth.Mcp.Registry.lookup("meta-test")
      assert meta.status == :updated
      assert meta.tool_count == 3
    end
  end

  describe "all/0" do
    test "lists all registered servers" do
      Worth.Mcp.Registry.register("s1", self())
      Worth.Mcp.Registry.register("s2", self())
      all = Worth.Mcp.Registry.all()
      names = Enum.map(all, & &1.name)
      assert "s1" in names
      assert "s2" in names
    end
  end
end
