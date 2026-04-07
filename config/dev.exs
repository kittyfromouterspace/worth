import Config

config :worth, Worth.Repo,
  username: "postgres",
  password: "postgres",
  database: "worth_dev",
  hostname: "localhost",
  pool_size: 10,
  types: Worth.PostgrexTypes

config :logger, level: :debug
