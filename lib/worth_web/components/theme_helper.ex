defmodule WorthWeb.ThemeHelper do
  @moduledoc """
  Theme helper functions for Phoenix components.
  Provides utilities to access theme colors and inject CSS.
  """

  use Phoenix.Component

  alias Worth.Theme.Registry

  @doc """
  Get the current theme module based on config
  """
  def current_theme do
    Registry.resolve()
  end

  @doc """
  Get a color class for a given key from the current theme
  """
  def color(key) do
    theme = current_theme()
    Map.get(theme.colors(), key, "")
  end

  @doc """
  Get theme CSS as a safe HTML string for injection into the layout
  """
  def css do
    theme = current_theme()
    theme.css()
  end

  @doc """
  Get theme CSS wrapped in style tags
  """
  def css_tag do
    "<style>" <> css() <> "</style>"
  end

  @doc """
  Check if theme has custom templates
  """
  def has_custom_template?(template) do
    theme = current_theme()
    theme.has_template?(template)
  end

  @doc """
  Render a custom template if available, otherwise return nil
  """
  def maybe_render(template, assigns) do
    theme = current_theme()

    if theme.has_template?(template) do
      case apply(theme, :render, [template, assigns]) do
        {:ok, rendered} -> rendered
        _ -> nil
      end
    else
      nil
    end
  end

  @doc """
  Get all themes for selection UI
  """
  def available_themes do
    Registry.list()
    |> Enum.map(fn theme ->
      %{
        name: theme.name(),
        display_name: theme.display_name(),
        description: theme.description()
      }
    end)
  end
end
