defmodule Mix.Tasks.Worth do
  @shortdoc "Start Worth"

  @moduledoc false
  use Mix.Task

  @requirements ["app.start"]

  @impl true
  def run(args) do
    Worth.CLI.main(args)
  end
end
