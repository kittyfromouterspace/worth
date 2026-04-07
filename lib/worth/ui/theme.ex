defmodule Worth.UI.Theme do
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

  def current do
    theme_name = Worth.Config.get([:ui, :theme]) || :dark

    Map.get(@themes, theme_name, %{})
    |> Map.merge(@default_theme, fn _k, v1, _v2 -> v1 end)
  end

  def style_for(element) do
    theme = current()

    case Map.get(theme, element, {:default, []}) do
      {fg, attrs} when is_list(attrs) -> TermUI.Style.from(fg: fg, attrs: attrs)
      fg when is_atom(fg) -> TermUI.Style.from(fg: fg)
    end
  end

  def status_indicator(status) do
    theme = current()

    case status do
      :idle -> theme[:status_idle]
      :running -> theme[:status_running]
      :error -> theme[:status_error]
    end
  end
end
