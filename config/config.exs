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
  home_directory: "~/work",
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

# --- Database ---
config :worth, Worth.Repo,
  username: "postgres",
  password: "postgres",
  database: "worth_dev",
  hostname: "localhost",
  port: 5432,
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10,
  types: Worth.PostgrexTypes

# --- Mneme ---
config :mneme,
  repo: Worth.Repo,
  embedding: [
    provider: Worth.Memory.Embeddings.Adapter,
    tier: :embeddings,
    dimensions: 1536
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
