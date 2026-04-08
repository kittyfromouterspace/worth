defmodule Mix.Tasks.Worth do
  use Mix.Task

  @shortdoc "Start the Worth TUI"

  @requirements ["app.start"]

  @impl true
  def run(args) do
    Worth.CLI.main(args)
  end
end
