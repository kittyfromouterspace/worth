defmodule Worth.Workspace.Service do
  @moduledoc false
  def list do
    dir = Worth.Paths.workspace_dir()

    if File.dir?(dir) do
      dir
      |> File.ls!()
      |> Enum.filter(fn name ->
        path = Path.join(dir, name)
        File.dir?(path) and File.exists?(Path.join(path, "IDENTITY.md"))
      end)
      |> Enum.sort()
    else
      []
    end
  end

  def create(name, opts \\ []) do
    dir = Worth.Paths.workspace_dir()
    workspace_path = Path.join(dir, name)
    workspace_type = Keyword.get(opts, :type, :code)

    if File.dir?(workspace_path) do
      {:error, "Workspace '#{name}' already exists"}
    else
      File.mkdir_p!(workspace_path)
      File.mkdir_p!(Path.join(workspace_path, ".worth"))
      File.mkdir_p!(Path.join(workspace_path, ".worth/skills"))

      write_identity(workspace_path, name, workspace_type)
      write_agents_md(workspace_path, workspace_type)
      write_skills_json(workspace_path)

      {:ok, workspace_path}
    end
  end

  @doc """
  Create the personal workspace — the user's home base.

  Accepts a profile map with `:name`, `:role`, and `:goals` keys.
  Generates a rich IDENTITY.md with frontmatter and user profile sections.
  If the workspace already exists, updates the IDENTITY.md in place.
  """
  def create_personal(profile \\ %{}) do
    dir = Worth.Paths.workspace_dir()
    workspace_path = Path.join(dir, "personal")

    File.mkdir_p!(workspace_path)
    File.mkdir_p!(Path.join(workspace_path, ".worth"))
    File.mkdir_p!(Path.join(workspace_path, ".worth/skills"))

    write_personal_identity(workspace_path, profile)
    write_agents_md(workspace_path, :general)
    write_skills_json(workspace_path)

    {:ok, workspace_path}
  end

  def resolve_path(name) do
    Path.join(Worth.Paths.workspace_dir(), name)
  end

  defp write_personal_identity(path, profile) do
    name = Map.get(profile, :name, "")
    role = Map.get(profile, :role, "")
    goals = Map.get(profile, :goals, "")

    about_section =
      if name != "" or role != "" or goals != "" do
        lines = []
        lines = if name == "", do: lines, else: lines ++ ["- **Name**: #{name}"]
        lines = if role == "", do: lines, else: lines ++ ["- **Role**: #{role}"]
        lines = if goals == "", do: lines, else: lines ++ ["- **Goals**: #{goals}"]

        """

        ## About You
        #{Enum.join(lines, "\n")}
        """
      else
        ""
      end

    content = """
    ---
    name: personal
    llm:
      prefer_free: true
      prompt_caching: true
    ---

    # Personal

    Your home workspace — the place from where you coordinate everything.
    #{about_section}
    ## How This Workspace Works

    This is your personal workspace. It's your home base — use it to think, plan,
    coordinate work across projects, and have general conversations. You can create
    additional workspaces for specific projects later.
    """

    File.write!(Path.join(path, "IDENTITY.md"), String.trim(content) <> "\n")
  end

  defp write_identity(path, name, :code) do
    content = "# #{name}\n\nA code workspace managed by worth.\n"
    File.write!(Path.join(path, "IDENTITY.md"), content)
  end

  defp write_identity(path, name, :research) do
    content = "# #{name}\n\nA research workspace managed by worth.\n"
    File.write!(Path.join(path, "IDENTITY.md"), content)
  end

  defp write_identity(path, name, _type) do
    content = "# #{name}\n\nA workspace managed by worth.\n"
    File.write!(Path.join(path, "IDENTITY.md"), content)
  end

  defp write_agents_md(path, _type) do
    content =
      "# Agent Instructions\n\n## Testing\n- Run tests with `mix test`\n\n## Conventions\n- Follow existing code style\n"

    File.write!(Path.join(path, "AGENTS.md"), content)
  end

  defp write_skills_json(path) do
    File.write!(
      Path.join(path, ".worth/skills.json"),
      Jason.encode!(%{"active" => [], "override" => %{}}, pretty: true)
    )
  end
end
