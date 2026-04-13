defmodule Worth.Tools.Router do
  @moduledoc """
  Routes tool calls to the appropriate Worth tool module based on name prefix.
  Single source of truth for tool definition aggregation and dispatch.
  """

  @base_tool_modules [
    {"memory_", Worth.Tools.Memory},
    {"skill_", Worth.Tools.Skills},
    {"mcp_", Worth.Tools.Mcp},
    {"kit_", Worth.Tools.Kits},
    {"workspace_", Worth.Tools.Workspace},
    {"web_", Worth.Tools.Web}
  ]

  def all_definitions(workspace_path \\ nil) do
    workspace_path
    |> tool_modules()
    |> Enum.flat_map(fn {_prefix, mod} -> mod.definitions() end)
  end

  def execute(name, args, workspace) do
    workspace_path = if is_binary(workspace), do: workspace

    case find_module(name, workspace_path) do
      {:ok, mod} ->
        mod.execute(name, args, workspace)

      :not_found ->
        if String.contains?(name, ":") do
          Worth.Mcp.Gateway.execute(name, args)
        else
          {:error, "External tool '#{name}' not configured"}
        end
    end
  end

  def get_schema(name, workspace_path \\ nil) do
    Enum.find(all_definitions(workspace_path), fn d ->
      (d[:name] || d["name"]) == name
    end)
  end

  defp tool_modules(workspace_path) do
    git_available? =
      System.find_executable("git") != nil and
        workspace_path != nil and
        File.dir?(Path.join(workspace_path, ".git"))

    if git_available? do
      [{"git_", Worth.Tools.Git} | @base_tool_modules]
    else
      @base_tool_modules
    end
  end

  defp find_module(name, workspace_path) do
    case Enum.find(tool_modules(workspace_path), fn {prefix, _} -> String.starts_with?(name, prefix) end) do
      {_, mod} -> {:ok, mod}
      nil -> :not_found
    end
  end
end
