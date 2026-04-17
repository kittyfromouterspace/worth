defmodule Worth.MixProject do
  use Mix.Project

  def project do
    [
      app: :worth,
      version: "0.2.1-alpha.9",
      elixir: "~> 1.19",
      description: "An AI assistant built on Elixir/BEAM",
      package: [
        licenses: ["BSD-3-Clause"],
        links: %{"GitHub" => "https://github.com/kittyfromouterspace/worth"}
      ],
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      aliases: aliases(),
      deps: deps(),
      releases: releases(),
      usage_rules: usage_rules()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {Worth.Application, []}
    ]
  end

  defp releases do
    [
      worth: [
        steps: [:assemble],
        applications: [
          worth: :permanent
        ]
      ],
      desktop: [
        steps: [:assemble],
        applications: [
          worth: :permanent
        ],
        validate_compile_env: false
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    worth_deps_mode = System.get_env("WORTH_DEPS_MODE", "dev")

    internal_deps =
      if worth_deps_mode == "prod" do
        [
          {:recollect, git: "https://github.com/kittyfromouterspace/recollect.git", tag: "v0.5.0", override: true},
          {:agentic, git: "https://github.com/kittyfromouterspace/agentic.git", tag: "v0.2.1"}
        ]
      else
        [
          {:recollect, path: "../recollect", override: true},
          {:agentic, path: "../agentic"}
        ]
      end

    other_deps = [
      {:tidewave, "~> 0.5", only: [:dev]},

      # Phoenix
      {:phoenix, "~> 1.8.5"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.1.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_pubsub, "~> 2.1"},
      {:bandit, "~> 1.5"},

      # Assets
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons", tag: "v2.2.0", sparse: "optimized", app: false, compile: false, depth: 1},

      # Database
      {:ecto_sqlite3, "~> 0.18"},
      {:sqlite_vec, "~> 0.1"},
      {:ecto_sql, "~> 3.12"},

      # MCP
      {:hermes_mcp, "~> 0.14.1"},

      # Telemetry
      {:telemetry, "~> 1.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},

      # Encryption
      {:cloak_ecto, "~> 1.3"},
      {:pbkdf2_elixir, "~> 2.2"},

      # Utilities
      {:nimble_options, "~> 1.1"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:mdex, "~> 0.2"},

      # Dev/Test tooling
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:ex_check, "~> 0.16", only: [:dev], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.22", only: [:dev], runtime: false},
      {:styler, ">= 0.11.0", only: [:dev, :test], runtime: false},
      {:lazy_html, ">= 0.1.0", only: :test},

      # Agent skills & usage rules
      {:usage_rules, "~> 1.1", only: [:dev]},
      {:igniter, "~> 0.6", only: [:dev]}
    ]

    internal_deps ++ other_deps
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": [
        "ecto.create",
        "ecto.create --repo Worth.Metrics.Repo",
        "ecto.migrate",
        "ecto.migrate --repo Worth.Metrics.Repo"
      ],
      "ecto.reset": ["ecto.drop", "ecto.drop --repo Worth.Metrics.Repo", "ecto.setup"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind worth", "esbuild worth"],
      "assets.deploy": ["tailwind worth --minify", "esbuild worth --minify", "phx.digest"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "ecto.migrate --quiet --repo Worth.Metrics.Repo", "test"]
    ]
  end

  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: [:usage_rules, :agentic, :recollect, :elixir, :otp],
      skills: [
        location: ".claude/skills",
        deps: [:agentic, :recollect],
        package_skills: [:agentic, :recollect],
        build: [
          "worth-memory": [
            description:
              "Use this skill when working with Worth's memory, knowledge, and agent systems. Combines agentic runtime and recollect memory patterns.",
            usage_rules: [:agentic, :recollect]
          ]
        ]
      ]
    ]
  end
end
