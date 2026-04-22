defmodule Worth.Theme.Registry do
  @moduledoc """
  Theme registry - manages available themes and lookups.
  """

  alias Worth.Theme.Bedrock
  alias Worth.Theme.Cyberdeck
  alias Worth.Theme.Daylight
  alias Worth.Theme.FifthElement
  alias Worth.Theme.Standard

  @setting_key "theme"

  @doc """
  Returns all available themes. Bedrock first — it's the flagship brand theme.
  """
  def list, do: [Bedrock, Standard, Daylight, Cyberdeck, FifthElement]

  @doc """
  Get a theme module by name
  """
  def get("bedrock"), do: {:ok, Bedrock}
  def get("standard"), do: {:ok, Standard}
  def get("daylight"), do: {:ok, Daylight}
  def get("cyberdeck"), do: {:ok, Cyberdeck}
  def get("fifth_element"), do: {:ok, FifthElement}
  def get(_), do: {:error, :not_found}

  @doc """
  Returns the default theme
  """
  def default, do: Bedrock

  @doc """
  Get theme from settings, config, or return default.
  Priority: 1) Worth.Settings (user preference), 2) Application config, 3) default
  """
  def resolve do
    theme_name = get_theme_name()

    case get(theme_name) do
      {:ok, theme} -> theme
      {:error, _} -> default()
    end
  end

  @doc """
  Get the current theme name as a string.
  """
  def current_theme_name do
    get_theme_name()
  end

  defp get_theme_name do
    settings_theme = try_get_settings_theme()
    if settings_theme && settings_theme != "", do: settings_theme, else: app_config_theme()
  end

  defp try_get_settings_theme do
    if function_exported?(Worth.Settings, :locked?, 0) do
      if not Worth.Settings.locked?() do
        Worth.Settings.get(@setting_key)
      end
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp app_config_theme do
    :theme
    |> Worth.Config.get("bedrock")
    |> to_string()
  end
end
