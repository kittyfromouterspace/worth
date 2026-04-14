import Config

alias Ecto.Adapters.SQLite3
alias Worth.Metrics.Repo

# --- Data directory (OS-conventional, auto-detected) ---
worth_data =
  case :os.type() do
    {:unix, :darwin} -> Path.expand("~/Library/Application Support/worth")
    {:win32, _} -> "LOCALAPPDATA" |> System.get_env(Path.expand("~/.local/share")) |> Path.join("worth")
    {:unix, _} -> "XDG_DATA_HOME" |> System.get_env(Path.expand("~/.local/share")) |> Path.join("worth")
  end

# --- AgentEx ---
config :agent_ex,
  providers: [
    AgentEx.LLM.Provider.OpenRouter,
    AgentEx.LLM.Provider.Anthropic,
    AgentEx.LLM.Provider.OpenAI
  ],
  catalog: [persist_path: Path.join(worth_data, "catalog.json")]

# --- esbuild ---
config :esbuild,
  version: "0.25.4",
  worth: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# --- Logger ---
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :mneme,
  database_adapter: Mneme.DatabaseAdapter.SQLiteVec,
  repo: Worth.Repo

config :mneme,
  embedding: [
    provider: Worth.Memory.Embeddings.Adapter,
    tier: :embeddings
  ],
  working_memory: [max_entries_per_scope: 50],
  outcome_feedback: [positive_half_life_delta: 5, negative_half_life_delta: 3]

# --- Phoenix ---
config :phoenix, :json_library, Jason

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

# --- Metrics Database Configuration ---
# Separate SQLite database for orchestration metrics so writes never
# contend with the main database for I/O or lock time.
config :worth, Repo,
  adapter: SQLite3,
  database: Path.join(worth_data, "metrics.db"),
  pool_size: 2,
  start_apps_before_migration: false

# --- Database Configuration ---
# Worth uses SQLite3 + sqlite-vec for zero-configuration local storage.
# Database lives in the OS-conventional data directory.
config :worth, Worth.Repo,
  adapter: SQLite3,
  database: Path.join(worth_data, "worth.db"),
  pool_size: 5

# --- Vault (ciphers configured at runtime after password unlock) ---
config :worth, Worth.Vault, ciphers: []

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

# --- Worth core ---
config :worth,
  ecto_repos: [Worth.Repo, Repo],
  generators: [timestamp_type: :utc_datetime],
  # Default workspace directory - users can override via UI settings
  workspace_directory: "~/work",
  llm: [
    default_provider: :openrouter,
    providers: %{
      openrouter: [
        api_key: {:env, "OPENROUTER_API_KEY"},
        default_model: "minimax/minimax-m2.5:free"
      ],
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

import_config "#{config_env()}.exs"
