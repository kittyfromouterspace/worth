import Config

# --- AgentEx ---
config :agent_ex,
  providers: [
    AgentEx.LLM.Provider.OpenRouter,
    AgentEx.LLM.Provider.Anthropic,
    AgentEx.LLM.Provider.OpenAI
  ],
  catalog: [persist_path: "~/work/catalog.json"]

# --- Worth core ---
config :worth,
  ecto_repos: [Worth.Repo],
  generators: [timestamp_type: :utc_datetime],
  # Default home directory - users can override via UI settings
  home_directory: "~/.worth",
  llm: [
    default_provider: :anthropic,
    providers: %{
      anthropic: [
        api_key: {:env, "ANTHROPIC_API_KEY"},
        default_model: "claude-sonnet-4-20250514"
      ]
    }
  ],
  memory: [
    enabled: true,
    extraction: :llm,
    auto_flush: true,
    decay_days: 90
  ],
  workspaces: [
    default: "personal",
    directory: "~/work/workspaces"
  ],
  ui: [
    theme: :dark,
    sidebar: :auto
  ],
  log: [
    rotation: :daily
  ],
  cost_limit: 5.0,
  max_turns: 50

# --- Vault (ciphers configured at runtime after password unlock) ---
config :worth, Worth.Vault, ciphers: []

# --- Database Configuration ---
# Worth supports two database backends:
# 1. libSQL (default) - Single file SQLite with native vector support
# 2. PostgreSQL - Traditional server-based database with pgvector
#
# Use the WORTH_DATABASE_BACKEND environment variable to choose:
#   export WORTH_DATABASE_BACKEND=libsql  # default
#   export WORTH_DATABASE_BACKEND=postgres

worth_home = System.get_env("WORTH_HOME", Path.expand("~/.worth"))
database_backend = System.get_env("WORTH_DATABASE_BACKEND", "libsql")

# Configure database based on backend choice
if database_backend == "postgres" do
  # PostgreSQL configuration
  config :worth, Worth.Repo,
    adapter: Ecto.Adapters.Postgres,
    username: System.get_env("WORTH_DB_USER", "postgres"),
    password: System.get_env("WORTH_DB_PASSWORD", "postgres"),
    database: System.get_env("WORTH_DB_NAME", "worth_dev"),
    hostname: System.get_env("WORTH_DB_HOST", "localhost"),
    port: String.to_integer(System.get_env("WORTH_DB_PORT", "5432")),
    stacktrace: true,
    show_sensitive_data_on_connection_error: true,
    pool_size: 10,
    types: Worth.PostgrexTypes

  config :mneme,
    database_adapter: Mneme.DatabaseAdapter.Postgres,
    repo: Worth.Repo
else
  # libSQL configuration (default)
  # Single file database stored in ~/.worth/worth.db
  config :worth, Worth.Repo,
    adapter: Ecto.Adapters.LibSql,
    database: Path.join(worth_home, "worth.db"),
    pool_size: 5

  config :mneme,
    database_adapter: Mneme.DatabaseAdapter.LibSQL,
    repo: Worth.Repo
end

# --- Mneme Core Configuration ---
config :mneme,
  embedding: [
    provider: Worth.Memory.Embeddings.Adapter,
    tier: :embeddings,
    dimensions: 1536,
    credentials_fn: fn ->
      case AgentEx.LLM.Credentials.resolve(AgentEx.LLM.Provider.OpenRouter) do
        {:ok, %{api_key: key}} -> %{api_key: key}
        _ -> :disabled
      end
    end
  ],
  working_memory: [max_entries_per_scope: 50],
  outcome_feedback: [positive_half_life_delta: 5, negative_half_life_delta: 3]

# --- Phoenix Endpoint ---
config :worth, WorthWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: WorthWeb.ErrorHTML, json: WorthWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Worth.PubSub,
  live_view: [signing_salt: "7RgzzNCL"]

# --- esbuild ---
config :esbuild,
  version: "0.25.4",
  worth: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# --- Tailwind ---
config :tailwind,
  version: "4.1.12",
  worth: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# --- Logger ---
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# --- Phoenix ---
config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
