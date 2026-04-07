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
