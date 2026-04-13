defmodule Worth.Mcp.Server.Tools.SkillList do
  @moduledoc "List all installed and learned skills"
  use Hermes.Server.Component, type: :tool

  schema do
    field(:workspace, :string, description: "Optional workspace to filter skills for")
  end

  @impl true
  def execute(params, frame) do
    opts = if params["workspace"], do: [workspace: params["workspace"]], else: []
    skills = Worth.Skill.Service.list(opts)

    lines =
      Enum.map_join(skills, "\n", fn s -> "[#{s.trust_level}] #{s.name}: #{s.description}" end)

    {:reply, lines, frame}
  rescue
    e -> {:error, Exception.message(e), frame}
  end
end
