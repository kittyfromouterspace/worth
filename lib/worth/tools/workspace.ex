defmodule Worth.Tools.Workspace do
  @moduledoc false

  def definitions do
    [
      %{
        "name" => "workspace_status",
        "description" => "Get current workspace information including name, path, and mode",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{}
        }
      },
      %{
        "name" => "workspace_list",
        "description" => "List all available workspaces",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{}
        }
      }
    ]
  end

  def execute("workspace_status", _input, ctx) do
    workspace = ctx[:workspace] || ctx["workspace"] || "personal"
    status = Worth.Brain.get_status(workspace)
    {:ok, "Workspace: #{status.workspace} | Mode: #{status.mode} | Profile: #{status.profile}"}
  end

  def execute("workspace_list", _input, _ctx) do
    workspaces = Worth.Workspace.Service.list()
    {:ok, "Workspaces:\n" <> Enum.map_join(workspaces, "\n", fn ws -> "  - #{ws}" end)}
  end
end
