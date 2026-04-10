defmodule Mix.Tasks.Worth.Export do
  @moduledoc """
  Export Worth data for migration or backup.

  ## Usage

      mix worth.export --output /path/to/backup.jsonl

  ## Options

  - `--output` — Path to output file (required)
  - `--scope` — Filter by scope_id (optional)
  - `--tables` — Comma-separated list of tables to export (default: all)

  ## Examples

      # Export all data
      mix worth.export --output ~/worth_backup.jsonl

      # Export only entries and edges
      mix worth.export --output ~/worth_entries.jsonl --tables mneme_entries,mneme_edges

      # Export specific workspace
      mix worth.export --output ~/workspace.jsonl --scope "my-workspace-id"
  """

  use Mix.Task

  alias Mneme.Export

  @impl true
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          output: :string,
          scope: :string,
          owner: :string,
          tables: :string
        ]
      )

    output = Keyword.get(opts, :output)

    unless output do
      Mix.raise("Missing required option: --output")
    end

    # Start the application (but not the full supervision tree)
    Mix.Task.run("app.start", [])

    # Build export options
    export_opts =
      []
      |> maybe_add_opt(:scope_id, opts[:scope])
      |> maybe_add_opt(:owner_id, opts[:owner])
      |> maybe_add_tables(opts[:tables])

    # Perform export
    case Export.export_all(output, export_opts) do
      {:ok, result} ->
        Mix.shell().info("""
        Export completed successfully!

        File: #{result.path}
        Total rows: #{result.total_rows}
        Tables: #{length(result.tables)}
        """)

        Enum.each(result.tables, fn {table, count} ->
          Mix.shell().info("  - #{table}: #{count} rows")
        end)

      {:error, reason} ->
        Mix.raise("Export failed: #{inspect(reason)}")
    end
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_add_tables(opts, nil), do: opts

  defp maybe_add_tables(opts, tables_str) do
    tables =
      tables_str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.to_atom/1)

    Keyword.put(opts, :tables, tables)
  end
end
