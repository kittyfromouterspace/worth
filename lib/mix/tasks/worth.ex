defmodule Mix.Tasks.Worth do
  use Mix.Task

  @shortdoc "Start Worth"

  @requirements ["app.start"]

  @impl true
  def run(args) do
    Worth.CLI.main(args)
  end
end
