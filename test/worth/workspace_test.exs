defmodule Worth.Workspace.ServiceTest do
  use ExUnit.Case, async: true

  @test_dir System.tmp_dir!() |> Path.join("worth-test-ws-#{:rand.uniform(100_000)}")

  setup do
    File.mkdir_p!(@test_dir)
    on_exit(fn -> File.rm_rf!(@test_dir) end)
    :ok
  end

  test "list returns workspace directories" do
    workspaces = Worth.Workspace.Service.list()
    assert is_list(workspaces)
  end

  test "create scaffolds a workspace" do
    name = "test-ws-#{:rand.uniform(100_000)}"
    dir = Path.join(@test_dir, name)
    File.mkdir_p!(dir)

    File.write!(Path.join(dir, "IDENTITY.md"), "# Test")
    assert File.exists?(Path.join(dir, "IDENTITY.md"))
  end

  test "resolve_path returns correct path" do
    path = Worth.Workspace.Service.resolve_path("my-project")
    assert path =~ "my-project"
  end
end
