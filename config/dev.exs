import Config

worth_data_dev =
  case :os.type() do
    {:unix, :darwin} -> Path.expand("~/Library/Application Support/worth")
    {:win32, _} -> "LOCALAPPDATA" |> System.get_env(Path.expand("~/.local/share")) |> Path.join("worth")
    {:unix, _} -> "XDG_DATA_HOME" |> System.get_env(Path.expand("~/.local/share")) |> Path.join("worth")
  end

config :logger, :default_formatter, format: "[$level] $message\n"
config :logger, level: :debug

config :phoenix, :plug_init_mode, :runtime
config :phoenix, :stacktrace_depth, 20

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true

config :recollect,
  database_adapter: Recollect.DatabaseAdapter.SQLiteVec

config :worth, Worth.Repo,
  adapter: Ecto.Adapters.SQLite3,
  database: Path.join(worth_data_dev, "worth_dev.db"),
  pool_size: 5

config :worth, WorthWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "sRsdpfm2KLi47mQkuaEDoZWM0KC5WUAGffFo0ATPu+TEG2Ju/2B09dtajrzW4g4/",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:worth, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:worth, ~w(--watch)]}
  ]

config :worth, WorthWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
      ~r"lib/worth_web/router\.ex$"E,
      ~r"lib/worth_web/(controllers|live|components)/.*\.(ex|heex)$"E
    ]
  ]

config :worth, dev_routes: true
