defmodule Worth.Workspace.FileBrowser do
  @moduledoc """
  Workspace file scanner. Returns sorted list of relative file paths.
  """

  @max_files 200

  def scan(workspace_name) do
    path = Worth.Workspace.Service.resolve_path(workspace_name)

    if File.dir?(path) do
      path
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.reject(&File.dir?/1)
      |> Enum.map(&Path.relative_to(&1, path))
      |> Enum.sort()
      |> Enum.take(@max_files)
    else
      []
    end
  rescue
    _ -> []
  end
end
