defmodule Worth.CLI do
  @moduledoc false
  def main(args \\ []) do
      {opts, _rest} =
        OptionParser.parse!(args,
          strict: [
            workspace: :string,
            mode: :string,
            strategy: :string,
            help: :boolean,
            version: :boolean,
            init: :string,
            setup: :boolean,
            no_open: :boolean
          ],
          aliases: [
            w: :workspace,
            m: :mode,
            h: :help,
            v: :version,
            n: :no_open
          ]
        )

    cond do
      opts[:help] ->
        print_help()

      opts[:version] ->
        IO.puts("worth v0.1.0")

      opts[:init] ->
        init_workspace(opts[:init])

      opts[:setup] ->
        Worth.Config.Setup.run_wizard!()

      true ->
        start_worth(opts)
    end
  end

  defp start_worth(opts) do
    url =
      Worth.Boot.run(
        workspace: opts[:workspace],
        mode: opts[:mode],
        strategy: opts[:strategy]
      )

    if !opts[:no_open] do
      open_browser(url)
    end

    IO.puts("Worth is running at #{url}")
    IO.puts("Press Ctrl+C to stop.")

    Process.sleep(:infinity)
  end

  defp open_browser(url) do
    case :os.type() do
      {:unix, :linux} -> System.cmd("xdg-open", [url], stderr_to_stdout: true)
      {:unix, :darwin} -> System.cmd("open", [url], stderr_to_stdout: true)
      {:win32, _} -> System.cmd("cmd", ["/c", "start", url], stderr_to_stdout: true)
      _ -> IO.puts("Open #{url} in your browser")
    end
  rescue
    _ -> IO.puts("Open #{url} in your browser")
  end

  defp init_workspace(name) do
    case Worth.Workspace.Service.create(name) do
      {:ok, path} ->
        IO.puts("Created workspace '#{name}' at #{path}")

      {:error, reason} ->
        IO.puts("Error: #{reason}")
    end
  end

  defp print_help do
    IO.puts("""
    worth v0.1.0 - Your ideas are WORTH more

    Usage:
      worth [options]

    Options:
      -w, --workspace <name>   Open a specific workspace (default: personal)
      -m, --mode <mode>        Execution mode: code | research | planned | turn_by_turn
      --strategy <name>        Orchestration strategy: default | stigmergy | holonic | evolutionary | swarm | ecosystem
      -n, --no-open            Don't open the browser (for desktop/Tauri use)
      --init <name>            Create a new workspace and exit
      --setup                  Run the setup wizard and exit
      -h, --help               Show this help message
      -v, --version            Show version

    The web UI starts at http://localhost:4090 by default.
    """)
  end
end
