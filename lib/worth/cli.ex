defmodule Worth.CLI do
  def main(args \\ []) do
    {opts, _rest} =
      OptionParser.parse!(args,
        strict: [
          workspace: :string,
          mode: :string,
          help: :boolean,
          version: :boolean,
          init: :string,
          setup: :boolean
        ],
        aliases: [
          w: :workspace,
          m: :mode,
          h: :help,
          v: :version
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
    Worth.Config.Setup.maybe_run_first_run!()

    ensure_home_directory!()

    workspace = opts[:workspace] || "personal"
    mode = parse_mode(opts[:mode] || "code")
    workspace_path = Path.expand("workspaces/#{workspace}", Worth.Config.Store.home_directory())

    if !File.dir?(workspace_path) do
      IO.puts("Workspace '#{workspace}' not found. Creating in #{Worth.Config.Store.home_directory()}...")
      File.mkdir_p!(workspace_path)
    end

    Application.put_env(:worth, :current_workspace, workspace)
    Application.put_env(:worth, :current_workspace_path, workspace_path)
    Application.put_env(:worth, :current_mode, mode)

    # Ensure the Brain for this workspace is started with the right mode
    Worth.Brain.ensure(workspace)
    Worth.Brain.switch_mode(workspace, mode)

    port = Application.get_env(:worth, WorthWeb.Endpoint)[:http][:port] || 4000
    url = "http://localhost:#{port}"

    IO.puts("Worth is running at #{url}")
    open_browser(url)
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

  defp parse_mode("code"), do: :code
  defp parse_mode("research"), do: :research
  defp parse_mode("planned"), do: :planned
  defp parse_mode("turn_by_turn"), do: :turn_by_turn
  defp parse_mode(_), do: :code

  defp ensure_home_directory! do
    home = Worth.Config.Store.home_directory()
    expanded = Path.expand(home)

    if !File.dir?(expanded) do
      IO.puts("Creating home directory: #{expanded}")
      File.mkdir_p!(expanded)
    end
  end

  defp print_help do
    IO.puts("""
    worth v0.1.0 - An AI assistant

    Usage:
      worth [options]

    Options:
      -w, --workspace <name>   Open a specific workspace (default: personal)
      -m, --mode <mode>        Execution mode: code | research | planned | turn_by_turn
      --init <name>            Create a new workspace and exit
      --setup                  Run the setup wizard and exit
      -h, --help               Show this help message
      -v, --version            Show version

    The web UI starts at http://localhost:4000 by default.
    """)
  end
end
