import Config

# --- Data directory (OS-conventional, auto-detected) ---
worth_data =
  case :os.type() do
    {:unix, :darwin} -> Path.expand("~/Library/Application Support/worth")
    {:win32, _} -> System.get_env("LOCALAPPDATA", Path.expand("~/.local/share")) |> Path.join("worth")
    {:unix, _} -> System.get_env("XDG_DATA_HOME", Path.expand("~/.local/share")) |> Path.join("worth")
  end

# --- AgentEx ---
config :agent_ex,
  providers: [
    AgentEx.LLM.Provider.OpenRouter,
    AgentEx.LLM.Provider.Anthropic,
    AgentEx.LLM.Provider.OpenAI
  ],
  catalog: [persist_path: Path.join(worth_data, "catalog.json")]

# --- Worth core ---
config :worth,
  ecto_repos: [Worth.Repo],
  generators: [timestamp_type: :utc_datetime],
  # Default workspace directory - users can override via UI settings
  workspace_directory: "~/work",
  llm: [
    default_provider: :openrouter,
    providers: %{
      openrouter: [
        api_key: {:env, "OPENROUTER_API_KEY"},
        default_model: "google/gemini-2.5-flash"
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

# --- Vault (ciphers configured at runtime after password unlock) ---
config :worth, Worth.Vault, ciphers: []

# --- Database Configuration ---
# Worth uses libSQL (SQLite) for zero-configuration local storage.
# Database lives in the OS-conventional data directory.
config :worth, Worth.Repo,
  adapter: Ecto.Adapters.LibSql,
  database: Path.join(worth_data, "worth.db"),
  pool_size: 5

config :mneme,
  database_adapter: Mneme.DatabaseAdapter.LibSQL,
  repo: Worth.Repo

# --- Mneme Core Configuration ---
# Default: local embeddings via Bumblebee (all-MiniLM-L6-v2, 384-dim).
# Model is downloaded on first start. No API key needed.
config :mneme,
  embedding: [
    provider: Mneme.Embedding.Local
  ],
  working_memory: [max_entries_per_scope: 50],
  outcome_feedback: [positive_half_life_delta: 5, negative_half_life_delta: 3]

# --- Nx (required for local embeddings) ---
config :nx, default_backend: EXLA.Backend

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
