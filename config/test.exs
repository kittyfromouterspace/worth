import Config

config :logger, level: :warning

config :mneme,
  database_adapter: Mneme.DatabaseAdapter.SQLiteVec,
  repo: Worth.Repo,
  embedding: [
    provider: Mneme.Embedding.Mock,
    mock: true,
    credentials_fn: nil
  ]

config :phoenix, :plug_init_mode, :runtime

config :phoenix,
  sort_verified_routes_query_params: true

config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Test configuration uses SQLite3 + sqlite-vec for faster, simpler tests
# This avoids the need for a running PostgreSQL server during tests
config :worth, Worth.Repo,
  adapter: Ecto.Adapters.SQLite3,
  database: "worth_test.db",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :worth, WorthWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "zsyjtQuyfsf29bSBmrB02IjOx/ezakOMLuX2e6OSLufYHbYXJReuYp6J3f4HrjVj",
  server: false

config :worth, :llm, providers: %{}
