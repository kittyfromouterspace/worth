defmodule Worth.MixProject do
  use Mix.Project

  def project do
    [
      app: :worth,
      version: "0.1.0",
      elixir: "~> 1.19",
      description: "A terminal-based AI assistant built on Elixir/BEAM",
      package: [
        licenses: ["BSD-3-Clause"],
        links: %{"GitHub" => "https://github.com/kittyfromouterspace/worth"}
      ],
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Worth.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:term_ui, "~> 0.2.0"},
      {:agent_ex, path: "../agent_ex"},
      {:mneme, path: "../mneme", override: true},
      {:hermes_mcp, "~> 0.14.1"},
      {:phoenix_pubsub, "~> 2.1"},
      {:ash, "~> 3.23"},
      {:ash_postgres, "~> 2.8"},
      {:telemetry, "~> 1.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:nimble_options, "~> 1.1"},
      {:owl, "~> 0.12"},
      {:ecto_sql, "~> 3.12"},
      {:postgrex, "~> 0.19"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
