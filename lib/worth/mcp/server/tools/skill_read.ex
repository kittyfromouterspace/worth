defmodule Worth.Mcp.Server.Tools.SkillRead do
  @moduledoc "Read the full content of a skill"
  use Hermes.Server.Component, type: :tool

  schema do
    field(:name, :string, required: true, description: "Skill name to read")
  end

  @impl true
  def execute(%{"name" => name}, frame) do
    case Worth.Skill.Service.read_body(name) do
      {:ok, body} ->
        {:reply, body, frame}

      {:error, reason} ->
        {:error, reason, frame}
    end
  rescue
    e -> {:error, Exception.message(e), frame}
  end
end
