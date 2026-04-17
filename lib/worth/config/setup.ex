defmodule Worth.Config.Setup do
  @moduledoc """
  High-level setup operations for Worth.

  Required keys for a usable Worth install:

    * `:workspace_directory` — root directory for user workspaces (e.g., "~/work")
    * `OPENROUTER_API_KEY` — chat + embeddings provider (stored in Settings DB)
    * `[:memory, :embedding_model]` — model id for embeddings
  """

  alias Worth.Config

  @openrouter_env "OPENROUTER_API_KEY"
  @default_embedding_model "openai/text-embedding-3-small"

  @doc "True if Worth is missing any required configuration."
  def needs_setup? do
    if safe_has_password?() do
      false
    else
      is_nil(workspace_directory()) or is_nil(openrouter_key())
    end
  end

  defp safe_has_password? do
    Worth.Settings.has_password?()
  rescue
    _ -> false
  catch
    :exit, _ -> false
  end

  @doc "Currently configured workspace directory, or nil."
  def workspace_directory do
    Config.get(:workspace_directory)
  end

  @doc "Default workspace directory suggested in the wizard."
  def default_workspace_directory, do: Worth.Paths.default_workspace_dir()

  @doc "Currently configured OpenRouter API key, or nil."
  def openrouter_key do
    if not Worth.Settings.locked?() do
      Worth.Settings.get(@openrouter_env)
    end
  end

  @doc "Currently configured embedding model id, or nil."
  def embedding_model do
    Config.get([:memory, :embedding_model])
  end

  @doc "Default embedding model suggested in the wizard."
  def default_embedding_model, do: @default_embedding_model

  @doc "Persist the OpenRouter API key."
  def set_openrouter_key(key) when is_binary(key) do
    case String.trim(key) do
      "" ->
        {:error, :empty_key}

      trimmed ->
        :ok = Config.put_secret(@openrouter_env, trimmed)
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

  @doc "Persist the workspace directory path."
  def set_workspace_directory(path) when is_binary(path) do
    case String.trim(path) do
      "" ->
        {:error, :empty_path}

      trimmed ->
        expanded = Path.expand(trimmed)
        Config.put_setting([:workspace_directory], expanded)
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
  Force-run the wizard regardless of state.
  """
  def run_wizard! do
    IO.puts("")
    IO.puts("=== Worth setup ===")
    IO.puts("Settings are stored in the application database.")
    IO.puts("")

    prompt_workspace_directory()
    prompt_openrouter_key()
    prompt_embedding_model()

    IO.puts("")
    IO.puts("Setup complete.")
    IO.puts("")
    :ok
  end

  defp prompt_workspace_directory do
    current = workspace_directory() || Worth.Paths.default_workspace_dir()
    has_current = not is_nil(workspace_directory())
    label = if has_current, do: " [keep current]", else: ""

    case ask("Workspace directory (root for all workspaces)#{label}: ") do
      "" ->
        if has_current do
          :ok
        else
          :ok = set_workspace_directory(current)
          IO.puts("  Using #{current}.")
        end

      value ->
        :ok = set_workspace_directory(value)
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
    Agentic.LLM.Catalog.refresh()
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
