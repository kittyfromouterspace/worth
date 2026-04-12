defmodule Worth.MixProject do
  use Mix.Project

  def project do
    [
      app: :worth,
      version: "0.2.1-alpha.1",
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
      releases: releases()
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
        ]
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
    [
      {:tidewave, "~> 0.5", only: [:dev]},
      {:mneme, git: "https://github.com/kittyfromouterspace/mneme.git", tag: "v0.2.1"},
      # Local embedding support (optional - enables Mneme.Embedding.Local)
      {:bumblebee, "~> 0.6.0"},
      {:exla, ">= 0.0.0"},
      {:agent_ex, git: "https://github.com/kittyfromouterspace/agent_ex.git", tag: "v0.1.2"},

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
      {:ecto_libsql, "~> 0.9"},
      {:ecto_sql, "~> 3.12"},
      # pgvector types required by mneme schemas
      {:pgvector, "~> 0.3"},

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
      {:earmark, "~> 1.4"},

      # Dev
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind worth", "esbuild worth"],
      "assets.deploy": ["tailwind worth --minify", "esbuild worth --minify", "phx.digest"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
