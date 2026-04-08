defmodule Worth.UI.Theme do
  alias TermUI.Renderer.Style

  @default_theme %{
    header: {:cyan, [:bold]},
    user_input: {:green, []},
    assistant: {:default, []},
    system: {:yellow, []},
    error: {:red, []},
    tool_call: {:blue, [:dim]},
    tool_result: {:magenta, [:dim]},
    thinking: {:bright_black, [:dim]},
    sidebar_border: {:yellow, []},
    sidebar_label: [:bold],
    status_running: "*",
    status_idle: " ",
    status_error: "!"
  }

  @themes %{
    dark: %{
      header: {:cyan, [:bold]},
      user_input: {:green, []},
      assistant: {:default, []},
      system: {:yellow, []},
      error: {:red, []}
    },
    light: %{
      header: {:blue, [:bold]},
      user_input: {:green, [:bold]},
      assistant: {:black, []},
      system: {:magenta, []},
      error: {:red, [:bold]}
    },
    minimal: %{
      header: {:default, [:bold]},
      user_input: {:default, []},
      assistant: {:default, []},
      system: {:bright_black, []},
      error: {:red, []}
    }
  }

  @palette %{
    bg: :black,
    card_bg: :black,
    border: :bright_black,
    text: :default,
    accent: :cyan,
    success: :green,
    warning: :yellow,
    error: :red,
    user: :green,
    assistant: :cyan,
    tool: :blue
  }

  defdelegate palette(key), to: __MODULE__, as: :get_palette

  def current do
    theme_name = Worth.Config.get([:ui, :theme]) || :dark

    Map.get(@themes, theme_name, %{})
    |> Map.merge(@default_theme, fn _k, v1, _v2 -> v1 end)
  end

  def style_for(element) do
    theme = current()

    case Map.get(theme, element, {:default, []}) do
      {fg, attrs} when is_list(attrs) -> Style.new(fg: normalize_color(fg), attrs: attrs)
      fg when is_atom(fg) -> Style.new(fg: normalize_color(fg))
    end
  end

  defp normalize_color(:default), do: nil
  defp normalize_color(other), do: other

  def status_indicator(status) do
    theme = current()

    case status do
      :idle -> theme[:status_idle]
      :running -> theme[:status_running]
      :error -> theme[:status_error]
    end
  end

  def card_style do
    Style.new(bg: :black, fg: :default)
  end

  def card_header_style do
    Style.new(attrs: [:bold], fg: :cyan)
  end

  def tool_status(:running), do: "●"
  def tool_status(:pending), do: "○"
  def tool_status(:success), do: "✓"
  def tool_status(:failed), do: "×"
  def tool_status(:warning), do: "⚠"

  def tool_status_style(:running), do: Style.new(fg: :yellow)
  def tool_status_style(:pending), do: Style.new(fg: :bright_black)
  def tool_status_style(:success), do: Style.new(fg: :green)
  def tool_status_style(:failed), do: Style.new(fg: :red)
  def tool_status_style(:warning), do: Style.new(fg: :yellow)

  def user_style, do: Style.new(fg: :green, attrs: [:bold])
  def assistant_style, do: Style.new(fg: :cyan)
  def error_style, do: Style.new(fg: :red)
  def system_style, do: Style.new(fg: :yellow)

  def keyhint_style, do: Style.new(fg: :bright_black, attrs: [:dim])
  def keyhint_key_style, do: Style.new(fg: :cyan)

  def badge_style do
    Style.new(attrs: [:bold], fg: :cyan)
  end

  def get_palette(key) do
    Map.get(@palette, key)
  end
end
