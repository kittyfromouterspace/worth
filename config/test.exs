import Config

config :worth, Worth.Repo,
  username: "postgres",
  password: "postgres",
  database: "worth_test",
  hostname: "localhost",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10,
  types: Worth.PostgrexTypes

config :mneme,
  repo: Worth.Repo,
  embedding: [
    provider: Mneme.Embedding.Mock,
    mock: true
  ]

config :worth, :llm, providers: %{}

config :worth, WorthWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "zsyjtQuyfsf29bSBmrB02IjOx/ezakOMLuX2e6OSLufYHbYXJReuYp6J3f4HrjVj",
  server: false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :phoenix,
  sort_verified_routes_query_params: true
