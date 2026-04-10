import Config

# Development uses libSQL (SQLite) by default for zero-configuration setup
# To use PostgreSQL instead: export WORTH_DATABASE_BACKEND=postgres
config :worth, Worth.Repo,
  adapter: Ecto.Adapters.LibSQL,
  database: Path.expand("~/.worth/worth_dev.db"),
  pool_size: 5

config :mneme,
  database_adapter: Mneme.DatabaseAdapter.LibSQL

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

config :logger, :default_formatter, format: "[$level] $message\n"
config :logger, level: :debug

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true
