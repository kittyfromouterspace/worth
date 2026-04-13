defmodule Worth.Workspace.ServiceTest do
  use ExUnit.Case, async: true

  alias Worth.Workspace.Service

  @test_dir Path.join(System.tmp_dir!(), "worth-test-ws-#{:rand.uniform(100_000)}")

  setup do
    File.mkdir_p!(@test_dir)
    # Point workspace_dir to temp dir for isolation
    original = Application.get_env(:worth, :workspace_directory)
    Application.put_env(:worth, :workspace_directory, @test_dir)

    on_exit(fn ->
      File.rm_rf!(@test_dir)
      if original, do: Application.put_env(:worth, :workspace_directory, original)
    end)

    :ok
  end

  test "list returns workspace directories" do
    workspaces = Service.list()
    assert is_list(workspaces)
  end

  test "create scaffolds a workspace with IDENTITY.md" do
    name = "test-ws-#{:rand.uniform(100_000)}"
    assert {:ok, path} = Service.create(name)
    assert File.exists?(Path.join(path, "IDENTITY.md"))
    assert File.exists?(Path.join(path, "AGENTS.md"))
    assert File.exists?(Path.join(path, ".worth/skills.json"))

    content = File.read!(Path.join(path, "IDENTITY.md"))
    assert content =~ name
  end

  test "create returns error for existing workspace" do
    name = "existing-#{:rand.uniform(100_000)}"
    Service.create(name)
    assert {:error, _} = Service.create(name)
  end

  test "create_personal generates rich IDENTITY.md with user profile" do
    profile = %{name: "Alice", role: "senior engineer", goals: "Help me build things fast"}

    assert {:ok, path} = Service.create_personal(profile)

    identity = File.read!(Path.join(path, "IDENTITY.md"))

    # Check frontmatter
    assert identity =~ "name: personal"
    assert identity =~ "prefer_free: true"

    # Check user profile
    assert identity =~ "Alice"
    assert identity =~ "senior engineer"
    assert identity =~ "Help me build things fast"

    # Check structure
    assert identity =~ "## About You"
    assert identity =~ "## How This Workspace Works"
    assert identity =~ "home base"
  end

  test "create_personal works with empty profile" do
    assert {:ok, path} = Service.create_personal(%{})

    identity = File.read!(Path.join(path, "IDENTITY.md"))

    assert identity =~ "name: personal"
    refute identity =~ "## About You"
    assert identity =~ "## How This Workspace Works"
  end

  test "create_personal is idempotent (updates existing)" do
    Service.create_personal(%{name: "Bob"})
    assert {:ok, path} = Service.create_personal(%{name: "Alice"})

    identity = File.read!(Path.join(path, "IDENTITY.md"))
    assert identity =~ "Alice"
    refute identity =~ "Bob"
  end

  test "resolve_path returns correct path" do
    path = Service.resolve_path("my-project")
    assert path =~ "my-project"
  end
end
