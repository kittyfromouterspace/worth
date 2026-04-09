defmodule Worth.Workspace.Service do
  alias Worth.Config.Store

  def list do
    dir = Path.expand("workspaces", Store.home_directory())

    if File.dir?(dir) do
      File.ls!(dir)
      |> Enum.filter(fn name ->
        Path.join(dir, name) |> File.dir?()
      end)
      |> Enum.sort()
    else
      []
    end
  end

  def create(name, opts \\ []) do
    dir = Path.expand("workspaces", Store.home_directory())
    workspace_path = Path.join(dir, name)
    workspace_type = Keyword.get(opts, :type, :code)

    if File.dir?(workspace_path) do
      {:error, "Workspace '#{name}' already exists"}
    else
      File.mkdir_p!(workspace_path)
      File.mkdir_p!(Path.join(workspace_path, ".worth"))

      write_identity(workspace_path, name, workspace_type)
      write_agents_md(workspace_path, workspace_type)
      write_skills_json(workspace_path)

      {:ok, workspace_path}
    end
  end

  def resolve_path(name) do
    Path.expand(Path.join("workspaces", name), Store.home_directory())
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
