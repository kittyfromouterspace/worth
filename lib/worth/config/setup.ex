defmodule Worth.Config.Setup do
  @moduledoc """
  High-level setup operations for Worth.

  Two surfaces use this module:

    * `Worth.CLI` runs `maybe_run_first_run!/0` before launching the TUI.
      If the on-disk config is missing required keys it drops into a
      stdin-based wizard. Stdin must still belong to the user at this
      point — `install_tui_logger/0` has not yet swallowed it.

    * `Worth.UI.Commands` exposes a `/setup` slash command that calls
      `set_openrouter_key/1` and `set_embedding_model/1` directly. The
      TUI owns stdin while running, so the slash command takes the value
      as an argument rather than prompting.

  Required keys for a usable Worth install:

    * `:home_directory` — root directory for Worth's work (e.g., "~/work")
    * `[:secrets, "OPENROUTER_API_KEY"]` — chat + embeddings provider
    * `[:memory, :embedding_model]` — model id passed to the embeddings
      adapter (e.g. `"openai/text-embedding-3-small"` via OpenRouter)
  """

  alias Worth.Config

  @openrouter_env "OPENROUTER_API_KEY"
  @default_embedding_model "openai/text-embedding-3-small"
  @default_home_directory "~/work"

  @doc "True if Worth is missing any required configuration."
  def needs_setup? do
    is_nil(home_directory()) or is_nil(openrouter_key()) or is_nil(embedding_model())
  end

  @doc "Currently configured home directory, or nil."
  def home_directory do
    Config.get(:home_directory)
  end

  @doc "Default home directory suggested in the wizard."
  def default_home_directory, do: @default_home_directory

  @doc "Currently configured OpenRouter API key, or nil."
  def openrouter_key do
    case Config.get([:secrets, @openrouter_env]) do
      nil -> System.get_env(@openrouter_env)
      "" -> nil
      key when is_binary(key) -> key
    end
  end

  @doc "Currently configured embedding model id, or nil."
  def embedding_model do
    Config.get([:memory, :embedding_model])
  end

  @doc "Default embedding model suggested in the wizard."
  def default_embedding_model, do: @default_embedding_model

  @doc "Persist the OpenRouter API key (plain text on disk + process env)."
  def set_openrouter_key(key) when is_binary(key) do
    case String.trim(key) do
      "" ->
        {:error, :empty_key}

      trimmed ->
        :ok = Config.put_secret(@openrouter_env, trimmed)
        # The catalog's initial refresh likely ran before this key was
        # in the env. Kick another refresh so models become resolvable
        # without waiting for the next 10-minute scheduled tick.
        _ = safe_catalog_refresh()
        :ok
    end
  end

  @doc "Persist the embedding model id."
  def set_embedding_model(model) when is_binary(model) do
    case String.trim(model) do
      "" -> {:error, :empty_model}
      trimmed -> Config.put_setting([:memory, :embedding_model], trimmed)
    end
  end

  @doc "Persist the home directory path."
  def set_home_directory(path) when is_binary(path) do
    case String.trim(path) do
      "" ->
        {:error, :empty_path}

      trimmed ->
        expanded = Path.expand(trimmed)
        Config.put_setting([:home_directory], expanded)
    end
  end

  @doc """
  Run the first-run wizard if anything is missing. Safe to call before
  the TUI takes over stdout/stdin. No-op when fully configured.
  """
  def maybe_run_first_run! do
    if needs_setup?() do
      run_wizard!()
    else
      :ok
    end
  end

  @doc """
  Force-run the wizard regardless of state. Used when the user passes
  `--setup` or wants to reconfigure from the command line.
  """
  def run_wizard! do
    IO.puts("")
    IO.puts("=== Worth setup ===")
    IO.puts("Config will be saved to #{Worth.Config.Store.path()} (plain text, 0600).")
    IO.puts("")

    prompt_home_directory()
    prompt_openrouter_key()
    prompt_embedding_model()

    IO.puts("")
    IO.puts("Setup complete.")
    IO.puts("")
    :ok
  end

  defp prompt_home_directory do
    current = home_directory() || @default_home_directory
    has_current = not is_nil(home_directory())
    label = if has_current, do: " [keep current]", else: ""

    case ask("Worth home directory (root for all work)#{label}: ") do
      "" ->
        if has_current do
          :ok
        else
          :ok = set_home_directory(current)
          IO.puts("  Using #{current}.")
        end

      value ->
        :ok = set_home_directory(value)
        IO.puts("  Saved.")
    end
  end

  defp prompt_openrouter_key do
    current = openrouter_key()
    label = if current, do: " [keep current]", else: ""

    case ask("OpenRouter API key#{label}: ") do
      "" when not is_nil(current) ->
        :ok

      "" ->
        IO.puts("  An OpenRouter API key is required. Try again.")
        prompt_openrouter_key()

      value ->
        :ok = set_openrouter_key(value)
        IO.puts("  Saved.")
    end
  end

  defp prompt_embedding_model do
    current = embedding_model() || @default_embedding_model

    case ask("Embedding model [#{current}]: ") do
      "" ->
        :ok = set_embedding_model(current)
        IO.puts("  Using #{current}.")

      value ->
        :ok = set_embedding_model(value)
        IO.puts("  Saved.")
    end
  end

  defp safe_catalog_refresh do
    AgentEx.LLM.Catalog.refresh()
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp ask(prompt) do
    case IO.gets(prompt) do
      :eof -> ""
      {:error, _} -> ""
      data when is_binary(data) -> String.trim(data)
    end
  end
end
