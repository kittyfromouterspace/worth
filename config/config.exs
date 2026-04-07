import Config

config :worth,
  ecto_repos: [Worth.Repo],
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
    directory: "~/.worth/workspaces"
  ],
  ui: [
    theme: :dark,
    sidebar: :auto
  ],
  cost_limit: 5.0,
  max_turns: 50

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

config :mneme,
  repo: Worth.Repo,
  embedding: [
    provider: Mneme.Embedding.Mock,
    mock: true
  ],
  working_memory: [max_entries_per_scope: 50],
  outcome_feedback: [positive_half_life_delta: 5, negative_half_life_delta: 3]

import_config "#{config_env()}.exs"
