defmodule Worth.UI.Sidebar do
  @moduledoc """
  Right-hand sidebar with tab indicator and per-tab content.

  Tabs: `:workspace`, `:tools`, `:skills`, `:status`. The active tab is
  driven by `state.sidebar_tab`; rendering is otherwise stateless.
  """

  import TermUI.Component.Helpers
  alias TermUI.Renderer.Style

  @tabs [:workspace, :tools, :skills, :status, :logs]
  @log_tail 50

  def render(state) do
    header = box([text("[#{tab_dots(state.sidebar_tab)}]", Style.new(fg: :cyan))])

    content = box(tab_content(state), style: Style.new(bg: :black))

    stack(:vertical, [header, content])
  end

  defp tab_dots(active) do
    Enum.map_join(@tabs, "", fn t -> if t == active, do: "●", else: "○" end)
  end

  defp tab_content(%{sidebar_tab: :workspace} = state), do: workspace_tab(state)
  defp tab_content(%{sidebar_tab: :tools} = state), do: tools_tab(state)
  defp tab_content(%{sidebar_tab: :skills} = state), do: skills_tab(state)
  defp tab_content(%{sidebar_tab: :status} = state), do: status_tab(state)
  defp tab_content(%{sidebar_tab: :logs} = state), do: logs_tab(state)

  defp workspace_tab(_state) do
    ws_list = Worth.Workspace.Service.list()
    lines = if ws_list == [], do: ["(none)"], else: Enum.map(ws_list, &"  #{&1}")
    [text("Workspace", Style.new(attrs: [:bold])) | Enum.map(lines, &text(&1))]
  end

  defp tools_tab(_state) do
    tools = ~w(read_file write_file edit_file bash list_files memory_query skill_list)

    [
      text("Tools", Style.new(attrs: [:bold]))
      | Enum.map(tools, &text("  #{&1}", Style.new(fg: :bright_black)))
    ]
  end

  defp skills_tab(_state) do
    skills = Worth.Skill.Registry.all()

    if skills == [] do
      [text("Skills", Style.new(attrs: [:bold])), text("  (none)", Style.new(fg: :bright_black))]
    else
      lines = Enum.map(skills, fn s -> "  #{s.name} [#{s.trust_level}]" end)
      [text("Skills", Style.new(attrs: [:bold])) | Enum.map(lines, &text(&1))]
    end
  end

  defp status_tab(state) do
    primary = Map.get(state.models, :primary, %{})
    lightweight = Map.get(state.models, :lightweight, %{})

    [
      text("Status", Style.new(attrs: [:bold])),
      text("  Mode:  #{state.mode}"),
      text("  Cost:  $#{Float.round(state.cost, 4)}"),
      text("  Turns: #{state.turn}"),
      text("  Models", Style.new(attrs: [:bold])),
      text("    primary:     #{model_line(primary)}", Style.new(fg: :bright_black)),
      text("      via #{source_line(primary)}", Style.new(fg: :bright_black)),
      text("    lightweight: #{model_line(lightweight)}", Style.new(fg: :bright_black)),
      text("      via #{source_line(lightweight)}", Style.new(fg: :bright_black))
    ]
  end

  defp model_line(%{label: label}) when is_binary(label) and label != "", do: label
  defp model_line(_), do: "(detecting…)"

  defp source_line(%{source: source}) when is_binary(source) and source != "", do: source
  defp source_line(_), do: "no route yet"

  defp logs_tab(_state) do
    entries = Worth.UI.LogBuffer.recent(@log_tail)

    body =
      if entries == [] do
        [text("  (no log entries)", Style.new(fg: :bright_black))]
      else
        Enum.map(entries, &log_line/1)
      end

    [text("Logs", Style.new(attrs: [:bold])) | body]
  end

  defp log_line(%{level: level, text: line}) do
    text("  [#{short_level(level)}] #{truncate(line)}", Style.new(fg: log_color(level)))
  end

  defp short_level(:emergency), do: "emrg"
  defp short_level(:alert), do: "alrt"
  defp short_level(:critical), do: "crit"
  defp short_level(:error), do: "err "
  defp short_level(:warning), do: "warn"
  defp short_level(:notice), do: "note"
  defp short_level(:info), do: "info"
  defp short_level(:debug), do: "dbg "
  defp short_level(other), do: to_string(other)

  defp log_color(level) when level in [:emergency, :alert, :critical, :error], do: :red
  defp log_color(:warning), do: :yellow
  defp log_color(:notice), do: :cyan
  defp log_color(:info), do: :white
  defp log_color(:debug), do: :bright_black
  defp log_color(_), do: :white

  defp truncate(line) do
    line
    |> String.replace("\n", " ")
    |> String.slice(0, 200)
  end
end
