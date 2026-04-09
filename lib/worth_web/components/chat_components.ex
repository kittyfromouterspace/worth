defmodule WorthWeb.ChatComponents do
  @moduledoc """
  Function components for the Worth chat UI.
  Replaces the TUI render modules (Header, LeftPanel, Sidebar, Message, Input).
  """
  use Phoenix.Component

  import WorthWeb.CoreComponents, only: [icon: 1]

  # ── Header ──────────────────────────────────────────────────────

  attr :status, :atom, required: true
  attr :workspace, :string, required: true
  attr :mode, :atom, required: true
  attr :turn, :integer, required: true
  attr :cost, :float, required: true
  attr :models, :map, required: true
  attr :active_agents, :list, default: []

  def chat_header(assigns) do
    ~H"""
    <header class="flex items-center gap-3 px-4 py-2 bg-ctp-mantle border-b border-ctp-surface0 text-sm shrink-0">
      <div class="flex items-center gap-2">
        <span class={status_class(@status)}>
          <.status_indicator status={@status} />
        </span>
        <span class="font-bold text-ctp-blue">worth</span>
      </div>

      <span class="text-ctp-surface2">|</span>
      <span class="text-ctp-text">{@workspace}</span>

      <span class="text-ctp-surface2">|</span>
      <span class="text-ctp-lavender">{@mode}</span>

      <span class="text-ctp-surface2">|</span>
      <span class="text-ctp-subtext0">t{@turn}</span>

      <span class="text-ctp-surface2">|</span>
      <span class="text-ctp-yellow">{cost_display(@cost)}</span>

      <span :if={model_label(@models)} class="text-ctp-overlay0">
        ({model_label(@models)})
      </span>

      <span :if={length(@active_agents) > 0} class="text-ctp-peach">
        <span class="spinner"></span> {@active_agents |> length()} agents
      </span>

      <div class="flex-1" />
    </header>
    """
  end

  defp status_class(:running), do: "text-ctp-blue"
  defp status_class(:error), do: "text-ctp-red"
  defp status_class(_), do: "text-ctp-overlay0"

  defp status_indicator(%{status: :running} = assigns) do
    ~H"""
    <span class="spinner"></span>
    """
  end

  defp status_indicator(%{status: :error} = assigns) do
    ~H"""
    <span>x</span>
    """
  end

  defp status_indicator(assigns) do
    ~H"""
    <span>o</span>
    """
  end

  defp cost_display(cost) when is_float(cost), do: "$#{:erlang.float_to_binary(cost, decimals: 4)}"
  defp cost_display(_), do: "$0.0000"

  defp model_label(models) do
    primary = Map.get(models, :primary, %{})
    label = Map.get(primary, :label)
    if label && label != "", do: label, else: nil
  end

  # ── Left Panel ──────────────────────────────────────────────────

  attr :workspace, :string, required: true
  attr :files, :list, default: []
  attr :agents, :list, default: []

  def left_panel(assigns) do
    ~H"""
    <aside class="w-56 bg-ctp-mantle border-r border-ctp-surface0 overflow-y-auto shrink-0 text-sm">
      <div class="px-3 py-2 bg-ctp-blue/10 text-ctp-blue font-bold text-xs uppercase tracking-wider">
        Navigator
      </div>

      <%!-- Workspaces --%>
      <div class="px-3 py-2">
        <div class="text-ctp-lavender font-semibold text-xs uppercase tracking-wider mb-1">Workspaces</div>
        <.workspace_list workspace={@workspace} />
      </div>

      <%!-- Files --%>
      <div class="px-3 py-2">
        <div class="text-ctp-lavender font-semibold text-xs uppercase tracking-wider mb-1">Files</div>
        <div :if={@files == []} class="text-ctp-overlay0 text-xs">(no files)</div>
        <div :for={file <- Enum.take(@files, 20)} class="text-xs text-ctp-subtext0 truncate py-px">
          {file}
        </div>
      </div>

      <%!-- Agents --%>
      <div class="px-3 py-2">
        <div class="text-ctp-lavender font-semibold text-xs uppercase tracking-wider mb-1">Agents</div>
        <div :if={@agents == []} class="text-ctp-overlay0 text-xs">o idle</div>
        <div :for={agent <- @agents} class="text-xs py-px">
          <.agent_row agent={agent} />
        </div>
      </div>
    </aside>
    """
  end

  defp workspace_list(assigns) do
    workspaces =
      try do
        Worth.Workspace.Service.list()
      rescue
        _ -> [assigns.workspace]
      end

    assigns = assign(assigns, :workspaces, workspaces)

    ~H"""
    <div
      :for={ws <- @workspaces}
      class={[
        "text-xs py-px",
        ws == @workspace && "text-ctp-blue font-semibold",
        ws != @workspace && "text-ctp-subtext0"
      ]}
    >
      {if ws == @workspace, do: "● ", else: "○ "}{ws}
    </div>
    """
  end

  defp agent_row(assigns) do
    ~H"""
    <div class={agent_status_class(@agent.status)}>
      <span :if={@agent.status == :running} class="spinner"></span>
      <span :if={@agent.status == :done} class="text-ctp-green">✓</span>
      <span :if={@agent.status == :error} class="text-ctp-red">×</span>
      <span :if={@agent.status not in [:running, :done, :error]} class="text-ctp-overlay0">○</span>
      {agent_label(@agent)}
      <span :if={@agent.current_tool} class="text-ctp-overlay0 ml-1">({@agent.current_tool})</span>
    </div>
    """
  end

  defp agent_status_class(:running), do: "text-ctp-yellow"
  defp agent_status_class(:done), do: "text-ctp-green"
  defp agent_status_class(:error), do: "text-ctp-red"
  defp agent_status_class(_), do: "text-ctp-overlay0"

  defp agent_label(agent), do: agent.label || agent.session_id

  # ── Sidebar ─────────────────────────────────────────────────────

  @tabs [
    {:status, "Status"},
    {:usage, "Usage"},
    {:tools, "Tools"},
    {:skills, "Skills"},
    {:logs, "Logs"}
  ]

  attr :tab, :atom, required: true
  attr :models, :map, required: true
  attr :cost, :float, required: true
  attr :turn, :integer, required: true
  attr :mode, :atom, required: true
  attr :workspace, :string, default: "personal"

  def sidebar(assigns) do
    assigns = assign(assigns, :tabs, @tabs)

    ~H"""
    <aside class="w-72 bg-ctp-mantle border-l border-ctp-surface0 overflow-y-auto shrink-0 text-sm">
      <%!-- Tab bar --%>
      <div class="flex border-b border-ctp-surface0">
        <button
          :for={{key, label} <- @tabs}
          phx-click="select_tab"
          phx-value-tab={key}
          class={[
            "px-3 py-1.5 text-xs font-medium cursor-pointer transition-colors",
            key == @tab && "bg-ctp-blue text-ctp-base",
            key != @tab && "text-ctp-subtext0 hover:text-ctp-text hover:bg-ctp-surface0"
          ]}
        >
          {label}
        </button>
      </div>

      <%!-- Tab content --%>
      <div class="p-3 space-y-1">
        <.tab_content tab={@tab} models={@models} cost={@cost} turn={@turn} mode={@mode} workspace={@workspace} />
      </div>
    </aside>
    """
  end

  defp tab_content(%{tab: :status} = assigns) do
    catalog_info =
      try do
        AgentEx.LLM.Catalog.info()
      rescue
        _ -> %{model_count: 0, providers: %{}}
      end

    assigns = assign(assigns, :catalog_info, catalog_info)

    ~H"""
    <div class="text-ctp-subtext0 space-y-1">
      <div>Mode: {@mode}</div>
      <div class="text-ctp-yellow">Cost: {cost_display(@cost)}</div>
      <div>Turns: {@turn}</div>
    </div>

    <div class="mt-3">
      <div class="text-ctp-lavender font-semibold text-xs uppercase tracking-wider mb-1">
        Models ({@catalog_info.model_count})
      </div>
      <div class="text-xs space-y-1">
        <div class="text-ctp-subtext0">{model_line(@models, :primary)}</div>
        <div class="text-ctp-overlay0">via {source_line(@models, :primary)}</div>
        <div class="text-ctp-subtext0">{model_line(@models, :lightweight)}</div>
        <div class="text-ctp-overlay0">via {source_line(@models, :lightweight)}</div>
      </div>
    </div>

    <div :if={@catalog_info.providers != %{}} class="mt-3">
      <div class="text-ctp-lavender font-semibold text-xs uppercase tracking-wider mb-1">Providers</div>
      <div :for={{id, stat} <- @catalog_info.providers} class="text-xs text-ctp-overlay0">
        {id |> Atom.to_string() |> String.capitalize()}: {provider_detail(stat)}
      </div>
    </div>
    """
  end

  defp tab_content(%{tab: :usage} = assigns) do
    metrics =
      try do
        Worth.Metrics.session()
      rescue
        _ ->
          %{
            cost: 0.0,
            calls: 0,
            input_tokens: 0,
            output_tokens: 0,
            cache_read: 0,
            cache_write: 0,
            embed_calls: 0,
            by_provider: %{}
          }
      end

    assigns = assign(assigns, :metrics, metrics)

    ~H"""
    <div class="text-ctp-lavender font-semibold text-xs uppercase tracking-wider mb-1">Session</div>
    <div class="text-xs text-ctp-subtext0 space-y-0.5">
      <div>Cost: ${Float.round(@metrics.cost, 4)} ({@metrics.calls} calls)</div>
      <div>Tokens: {format_int(@metrics.input_tokens)} in / {format_int(@metrics.output_tokens)} out</div>
      <div class="text-ctp-overlay0">
        Cache: {format_int(@metrics.cache_read)} read / {format_int(@metrics.cache_write)} write
      </div>
      <div class="text-ctp-overlay0">Embed: {@metrics.embed_calls} calls</div>
    </div>

    <div :if={@metrics.by_provider != %{}} class="mt-3">
      <div class="text-ctp-lavender font-semibold text-xs uppercase tracking-wider mb-1">By Provider</div>
      <div :for={{provider, p} <- @metrics.by_provider} class="text-xs text-ctp-overlay0">
        {provider} ${Float.round(p.cost, 4)} ({p.calls})
      </div>
    </div>
    """
  end

  defp tab_content(%{tab: :tools} = assigns) do
    ~H"""
    <div class="text-ctp-lavender font-semibold text-xs uppercase tracking-wider mb-1">Built-in Tools</div>
    <div
      :for={tool <- ~w(read_file write_file edit_file bash list_files memory_query skill_list)}
      class="text-xs text-ctp-subtext0 py-px"
    >
      {tool}
    </div>
    """
  end

  defp tab_content(%{tab: :skills} = assigns) do
    skills =
      try do
        Worth.Skill.Registry.all()
      rescue
        _ -> []
      end

    assigns = assign(assigns, :skills, skills)

    ~H"""
    <div class="text-ctp-lavender font-semibold text-xs uppercase tracking-wider mb-1">Skills</div>
    <div :if={@skills == []} class="text-xs text-ctp-overlay0">(none)</div>
    <div :for={s <- @skills} class="text-xs text-ctp-subtext0 py-px">
      {s.name} <span class="text-ctp-overlay0">[{s.trust_level}]</span>
    </div>
    """
  end

  defp tab_content(%{tab: :logs} = assigns) do
    entries =
      try do
        Worth.LogBuffer.recent(50)
      rescue
        _ -> []
      end

    assigns = assign(assigns, :entries, entries)

    ~H"""
    <div class="text-ctp-lavender font-semibold text-xs uppercase tracking-wider mb-1">Logs</div>
    <div :if={@entries == []} class="text-xs text-ctp-overlay0">(no log entries)</div>
    <div :for={entry <- @entries} class={["text-xs py-px font-mono", log_color_class(entry.level)]}>
      [{short_level(entry.level)}] {truncate(entry.text)}
    </div>
    """
  end

  defp tab_content(assigns) do
    ~H"""
    <div class="text-ctp-overlay0 text-xs">Unknown tab</div>
    """
  end

  # ── Message ─────────────────────────────────────────────────────

  attr :msg, :map, required: true

  def message(assigns) do
    ~H"""
    <div class={message_wrapper_class(@msg.type)}>
      <.message_content msg={@msg} />
    </div>
    """
  end

  defp message_content(%{msg: %{type: :user}} = assigns) do
    ~H"""
    <div class="flex gap-2">
      <span class="text-ctp-green font-bold shrink-0">you</span>
      <span class="text-ctp-text">{@msg.content}</span>
    </div>
    """
  end

  defp message_content(%{msg: %{type: :assistant}} = assigns) do
    ~H"""
    <div class="flex gap-2">
      <span class="text-ctp-blue font-bold shrink-0">ai</span>
      <div class="markdown-content flex-1 min-w-0">{render_markdown(@msg.content)}</div>
    </div>
    """
  end

  defp message_content(%{msg: %{type: :system}} = assigns) do
    ~H"""
    <div class="flex gap-2">
      <span class="text-ctp-mauve font-bold shrink-0">sys</span>
      <pre class="text-ctp-subtext0 whitespace-pre-wrap text-xs flex-1 min-w-0">{@msg.content}</pre>
    </div>
    """
  end

  defp message_content(%{msg: %{type: :error}} = assigns) do
    ~H"""
    <div class="flex gap-2">
      <span class="text-ctp-red font-bold shrink-0">err</span>
      <span class="text-ctp-red">{@msg.content}</span>
    </div>
    """
  end

  defp message_content(%{msg: %{type: :tool_call, content: content}} = assigns) do
    assigns = assign(assigns, :name, content.name)

    ~H"""
    <div class="flex items-center gap-2 text-xs">
      <.icon name="hero-wrench-screwdriver" class="size-3 text-ctp-peach" />
      <span class="text-ctp-peach font-semibold">{@name}</span>
      <span :if={@msg.content[:status] == :running} class="spinner text-ctp-yellow"></span>
    </div>
    """
  end

  defp message_content(%{msg: %{type: :tool_result, content: content}} = assigns) do
    status = Map.get(content, :status, :success)
    output = Map.get(content, :output, "")
    truncated = if String.length(output) > 300, do: String.slice(output, 0, 300) <> "...", else: output

    assigns = assign(assigns, name: content.name, status: status, output: truncated)

    ~H"""
    <div class="text-xs">
      <div class="flex items-center gap-2">
        <span class={if @status == :failed, do: "text-ctp-red", else: "text-ctp-green"}>
          {if @status == :failed, do: "× ", else: "✓ "}
        </span>
        <span class="text-ctp-peach">{@name}</span>
      </div>
      <pre :if={@output != ""} class="text-ctp-overlay0 whitespace-pre-wrap ml-5 mt-1 max-h-32 overflow-y-auto">{@output}</pre>
    </div>
    """
  end

  defp message_content(%{msg: %{type: :thinking}} = assigns) do
    ~H"""
    <div class="flex gap-2 text-xs">
      <span class="text-ctp-mauve italic shrink-0">thinking</span>
      <span class="text-ctp-overlay0 italic">{String.slice(@msg.content, 0, 200)}</span>
    </div>
    """
  end

  defp message_content(assigns) do
    ~H"""
    <div class="text-ctp-overlay0 text-xs">{inspect(@msg)}</div>
    """
  end

  defp message_wrapper_class(:user), do: "py-2 px-3 rounded-md bg-ctp-surface0/50"
  defp message_wrapper_class(:assistant), do: "py-2 px-3"
  defp message_wrapper_class(:error), do: "py-2 px-3 rounded-md bg-ctp-red/10 border border-ctp-red/30"
  defp message_wrapper_class(:tool_call), do: "py-1 px-3 ml-4"
  defp message_wrapper_class(:tool_result), do: "py-1 px-3 ml-4"
  defp message_wrapper_class(:thinking), do: "py-1 px-3 ml-4 border-l-2 border-ctp-mauve/30"
  defp message_wrapper_class(:system), do: "py-2 px-3 rounded-md bg-ctp-mauve/5 border border-ctp-mauve/20"
  defp message_wrapper_class(_), do: "py-1 px-3"

  # ── Input bar ───────────────────────────────────────────────────

  attr :mode, :atom, required: true
  attr :status, :atom, required: true

  def input_bar(assigns) do
    ~H"""
    <div class="border-t border-ctp-surface0 bg-ctp-mantle px-4 py-3 shrink-0">
      <form phx-submit="submit" class="flex items-center gap-3">
        <span class="text-ctp-blue font-bold text-sm">{@mode} ></span>
        <input
          type="text"
          name="text"
          placeholder={if @status == :running, do: "Waiting for response...", else: "Type a message or /command..."}
          disabled={@status == :running}
          autocomplete="off"
          phx-hook="InputFocus"
          id="chat-input"
          class="flex-1 bg-transparent border-none outline-none text-ctp-text placeholder-ctp-overlay0 text-sm font-mono"
        />
        <button
          type="submit"
          disabled={@status == :running}
          class={[
            "px-3 py-1 rounded text-xs font-semibold transition-colors",
            @status == :running && "bg-ctp-surface1 text-ctp-overlay0 cursor-not-allowed",
            @status != :running && "bg-ctp-blue text-ctp-base hover:bg-ctp-lavender cursor-pointer"
          ]}
        >
          Send
        </button>
      </form>
    </div>
    """
  end

  # ── Markdown rendering ─────────────────────────────────────────

  defp render_markdown(nil), do: ""
  defp render_markdown(""), do: ""

  defp render_markdown(text) do
    case Earmark.as_html(text, compact_output: true) do
      {:ok, html, _} -> Phoenix.HTML.raw(html)
      _ -> text
    end
  end

  # ── Sidebar helpers ─────────────────────────────────────────────

  defp model_line(models, tier) do
    model = Map.get(models, tier, %{})
    label = Map.get(model, :label)
    if label && label != "", do: label, else: "(detecting...)"
  end

  defp source_line(models, tier) do
    model = Map.get(models, tier, %{})
    source = Map.get(model, :source)
    if source && source != "", do: source, else: "no route yet"
  end

  defp provider_detail(%{status: :ok, count: count}), do: "#{count} models"
  defp provider_detail(%{status: :static, count: count}), do: "#{count} (static)"
  defp provider_detail(%{status: :fallback, count: count}), do: "#{count} (fallback)"
  defp provider_detail(%{status: :no_creds}), do: "no key"
  defp provider_detail(_), do: "?"

  defp format_int(n) when is_integer(n) and n >= 1000 do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format_int(n) when is_integer(n), do: Integer.to_string(n)
  defp format_int(_), do: "0"

  defp short_level(:emergency), do: "emrg"
  defp short_level(:alert), do: "alrt"
  defp short_level(:critical), do: "crit"
  defp short_level(:error), do: "err "
  defp short_level(:warning), do: "warn"
  defp short_level(:notice), do: "note"
  defp short_level(:info), do: "info"
  defp short_level(:debug), do: "dbg "
  defp short_level(other), do: to_string(other)

  defp log_color_class(level) when level in [:emergency, :alert, :critical, :error], do: "text-ctp-red"
  defp log_color_class(:warning), do: "text-ctp-yellow"
  defp log_color_class(:notice), do: "text-ctp-blue"
  defp log_color_class(:info), do: "text-ctp-text"
  defp log_color_class(:debug), do: "text-ctp-overlay0"
  defp log_color_class(_), do: "text-ctp-text"

  defp truncate(line) do
    line
    |> String.replace("\n", " ")
    |> String.slice(0, 200)
  end
end
