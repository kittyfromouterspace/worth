defmodule Worth.Tools.Git do
  @moduledoc false

  def definitions do
    [
      %{
        "name" => "git_diff",
        "description" => "Show git diff of changes in the workspace",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "path" => %{"type" => "string", "description" => "Optional file or directory path to diff"},
            "staged" => %{"type" => "boolean", "description" => "Show staged changes", "default" => false}
          }
        }
      },
      %{
        "name" => "git_log",
        "description" => "Show git commit history",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{
            "count" => %{"type" => "integer", "description" => "Number of commits to show", "default" => 10},
            "path" => %{"type" => "string", "description" => "Optional file path to show history for"}
          }
        }
      },
      %{
        "name" => "git_status",
        "description" => "Show git working tree status",
        "input_schema" => %{
          "type" => "object",
          "properties" => %{}
        }
      }
    ]
  end

  def execute("git_diff", input, ctx) do
    args = []
    args = if input["staged"], do: ["--staged" | args], else: args
    args = if input["path"], do: args ++ ["--", input["path"]], else: args
    run_git("diff", args, ctx)
  end

  def execute("git_log", input, ctx) do
    count = input["count"] || 10
    args = ["--oneline", "-n", to_string(count)]
    args = if input["path"], do: args ++ ["--", input["path"]], else: args
    run_git("log", args, ctx)
  end

  def execute("git_status", _input, ctx) do
    run_git("status", ["--short"], ctx)
  end

  defp run_git(subcommand, args, workspace) when is_binary(workspace) do
    full_args = [subcommand | args]

    case System.cmd("git", full_args, cd: workspace, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, output}

      {output, _code} ->
        {:error, output}
    end
  end

  defp run_git(subcommand, args, ctx) when is_map(ctx) do
    workspace = ctx[:workspace] || ctx["workspace"]
    run_git(subcommand, args, workspace)
  end

  defp run_git(_subcommand, _args, _ctx) do
    {:error, "No workspace provided"}
  end
end
