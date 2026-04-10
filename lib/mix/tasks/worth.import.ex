defmodule Mix.Tasks.Worth.Import do
  @moduledoc """
  Import Worth data from an export file.

  ## Usage

      mix worth.import --input /path/to/backup.jsonl

  ## Options

  - `--input` — Path to input file (required)
  - `--dry-run` — Validate without importing (default: false)
  - `--on-conflict` — How to handle conflicts: skip, replace (default: skip)
  - `--batch-size` — Rows per batch (default: 1000)

  ## Examples

      # Import all data
      mix worth.import --input ~/worth_backup.jsonl

      # Validate first
      mix worth.import --input ~/worth_backup.jsonl --dry-run

      # Replace existing data
      mix worth.import --input ~/worth_backup.jsonl --on-conflict replace
  """

  use Mix.Task

  alias Mneme.Import

  @impl true
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          input: :string,
          dry_run: :boolean,
          on_conflict: :string,
          batch_size: :integer
        ]
      )

    input = Keyword.get(opts, :input)

    unless input do
      Mix.raise("Missing required option: --input")
    end

    unless File.exists?(input) do
      Mix.raise("Input file not found: #{input}")
    end

    # Start the application
    Mix.Task.run("app.start", [])

    # Build import options
    import_opts =
      []
      |> maybe_add_opt(:dry_run, opts[:dry_run])
      |> maybe_add_opt(:batch_size, opts[:batch_size])
      |> maybe_add_conflict(opts[:on_conflict])

    # Validate first
    Mix.shell().info("Validating import file...")

    case Import.validate(input) do
      {:ok, metadata} ->
        Mix.shell().info("""
        Validation successful!

        Tables found: #{Enum.join(metadata.tables, ", ")}
        Total rows: #{metadata.total_rows}
        """)

        unless import_opts[:dry_run] do
          proceed = Mix.shell().yes?("Proceed with import?")

          if proceed do
            perform_import(input, import_opts)
          else
            Mix.shell().info("Import cancelled.")
          end
        else
          Mix.shell().info("Dry run complete. Use without --dry-run to import.")
        end

      {:error, reason} ->
        Mix.raise("Validation failed: #{inspect(reason)}")
    end
  end

  defp perform_import(input, opts) do
    Mix.shell().info("Importing data...")

    case Import.import_all(input, opts) do
      {:ok, result} ->
        Mix.shell().info("""
        Import completed!

        Imported: #{result.imported} rows
        Skipped: #{result.skipped} rows
        Errors: #{length(result.errors)}
        """)

        if result.errors != [] do
          Mix.shell().info("\nErrors encountered:")
          Enum.take(result.errors, 10)
          |> Enum.each(fn error ->
            Mix.shell().info("  - #{inspect(error)}")
          end)
        end

      {:error, reason} ->
        Mix.raise("Import failed: #{inspect(reason)}")
    end
  end

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_add_conflict(opts, nil), do: opts

  defp maybe_add_conflict(opts, conflict) when conflict in ["skip", "replace"] do
    Keyword.put(opts, :on_conflict, String.to_atom(conflict))
  end

  defp maybe_add_conflict(_opts, conflict) do
    Mix.raise("Invalid --on-conflict value: #{conflict}. Use 'skip' or 'replace'.")
  end
end
