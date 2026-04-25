import Config

alias Ecto.Adapters.SQLite3
alias Worth.Memory.Embeddings.Adapter
alias Worth.Metrics.Repo

# --- Data directory ---
# NOTE: the *actual* data-dir path is resolved at runtime in runtime.exs.
# Here we only provide a dev/test fallback so that `mix` tasks work outside
# a release.  Release builds must never rely on this value.
worth_data =
  case config_env() do
    env when env in [:dev, :test] ->
      case :os.type() do
        {:unix, :darwin} -> Path.expand("~/Library/Application Support/worth")
        {:win32, _} -> "LOCALAPPDATA" |> System.get_env(Path.expand("~/.local/share")) |> Path.join("worth")
        {:unix, _} -> "XDG_DATA_HOME" |> System.get_env(Path.expand("~/.local/share")) |> Path.join("worth")
      end

    _ ->
      nil
  end

# --- Agentic ---
config :agentic,
  providers: [
    Agentic.LLM.Provider.OpenRouter,
    Agentic.LLM.Provider.Anthropic,
    Agentic.LLM.Provider.OpenAI,
    Agentic.LLM.Provider.Zai,
    # Coding-agent CLI wrappers — registered eagerly; their
    # `availability/1` callbacks gate visibility based on whether the
    # binary is on PATH, so listing one whose CLI isn't installed
    # is harmless.
    Agentic.LLM.Provider.ClaudeCode,
    Agentic.LLM.Provider.OpenCode,
    Agentic.LLM.Provider.Codex,
    Agentic.LLM.Provider.Cursor,
    Agentic.LLM.Provider.GeminiCli,
    Agentic.LLM.Provider.Goose,
    Agentic.LLM.Provider.Copilot,
    Agentic.LLM.Provider.Kimi,
    Agentic.LLM.Provider.Qwen
  ],
  catalog: [persist_path: worth_data && Path.join(worth_data, "catalog.json")]

# --- ex_money / FX ---
# v1: Worth bundles its own OXR app id (set at runtime / via env var).
# v2 (future): clients hit a Worth-hosted OXR-compatible relay — see
# §5.5.1 of docs/IMPLEMENTATION_PROPOSAL_MULTI_PATHWAY_ROUTING.md.
# Disabled by default in dev/test; enabled in prod when OXR app id is
# present. The Money library is still loaded for currency-aware Money.t()
# values regardless.
config :ex_money,
  default_cldr_backend: Worth.Cldr,
  auto_start_exchange_rate_service: false,
  exchange_rates_retrieve_every: :timer.hours(6),
  api_module: Money.ExchangeRates.OpenExchangeRates,
  open_exchange_rates_app_id: {:system, "WORTH_OXR_APP_ID"}

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

# --- Phoenix ---
config :phoenix, :json_library, Jason

config :recollect,
  database_adapter: Recollect.DatabaseAdapter.SQLiteVec,
  repo: Worth.Repo,
  on_graph_change: {Worth.Memory.GraphNotifier, :notify, []}

config :recollect,
  embedding: [
    provider: Adapter,
    tier: :embeddings,
    credentials_fn: &Adapter.credentials/0
  ],
  working_memory: [max_entries_per_scope: 50],
  outcome_feedback: [positive_half_life_delta: 5, negative_half_life_delta: 3]

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
  database: worth_data && Path.join(worth_data, "metrics.db"),
  pool_size: 2,
  start_apps_before_migration: false

# --- Database Configuration ---
# Worth uses SQLite3 + sqlite-vec for zero-configuration local storage.
# Database lives in the OS-conventional data directory.
config :worth, Worth.Repo,
  adapter: SQLite3,
  database: worth_data && Path.join(worth_data, "worth.db"),
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
        default_model: "minimax/minimax-m2.5:free"
      ],
      anthropic: [
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
