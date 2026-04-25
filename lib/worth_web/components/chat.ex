defmodule WorthWeb.Components.Chat do
  @moduledoc """
  Function components for the Worth chat UI.
  Replaces the TUI render modules (Header, LeftPanel, Sidebar, Message, Input).
  """
  use Phoenix.Component

  import WorthWeb.CoreComponents, only: [icon: 1]
  import WorthWeb.Components.Brand, only: [worth_mark: 1, w_spinner: 1]
  import WorthWeb.ThemeHelper, only: [color: 1]

  # ── Header ──────────────────────────────────────────────────────

  attr :status, :atom, required: true
  attr :workspace, :string, required: true
  attr :mode, :atom, required: true
  attr :turn, :integer, required: true
  attr :cost, :float, required: true
  attr :models, :map, required: true
  attr :active_agents, :list, default: []
  attr :desktop_mode, :boolean, default: false
  attr :xray, :boolean, default: false

  def chat_header(assigns) do
    ~H"""
    <header class={"heat-seam flex items-center gap-2.5 px-4 py-2 shrink-0 text-sm #{color(:background)} #{color(:border)} border-b"}>
      <div class="flex items-center gap-2">
        <span class={status_class(@status)} style="font-size: 16px; line-height: 1;">
          <.status_indicator status={@status} />
        </span>
        <.worth_mark size={16} />
        <span class={"font-semibold tracking-tight #{color(:text)}"} style="font-family: 'Space Grotesk', sans-serif;">worth</span>
      </div>

      <span class={color(:text_dim)}>|</span>
      <span class={color(:text)}>{@workspace}</span>

      <span class={color(:text_dim)}>|</span>
      <span class={color(:text_muted)}>{@mode}</span>

      <span class={color(:text_dim)}>|</span>
      <span class={"tabular #{color(:text_muted)}"}>t{@turn}</span>

      <span class={color(:text_dim)}>|</span>
      <span class={"tabular #{color(:text)}"}>{cost_display(@cost)}</span>

      <span class={color(:text_dim)}>
        ( <span class={color(:text_muted)}>{model_label(@models) || "no model"}</span> )
      </span>

      <span :if={length(@active_agents) > 0} class={color(:warning)}>
        <.w_spinner /> {@active_agents |> length()} agents
      </span>

      <div class="flex-1" />

      <button
        phx-click="toggle_xray"
        class={"transition-colors cursor-pointer #{if @xray, do: color(:accent), else: "#{color(:text_dim)} hover:#{color(:text)}"}"}
        title="Toggle X-Ray debug mode"
      >
        <.icon name="hero-eye" class="w-4 h-4" />
      </button>

      <button
        :if={@desktop_mode}
        onclick="if(confirm('Quit Worth?')) window.close()"
        class={"#{color(:text_muted)} hover:#{color(:error)} transition-colors cursor-pointer"}
        title="Quit Worth"
      >
        <.icon name="hero-x-mark" class="w-4 h-4" />
      </button>
    </header>
    """
  end

  defp status_class(:running), do: color(:status_running)
  defp status_class(:error), do: color(:status_error)
  defp status_class(_), do: color(:status_idle)

  defp status_indicator(%{status: :running} = assigns) do
    ~H"""
    <.w_spinner />
    """
  end

  defp status_indicator(%{status: :error} = assigns) do
    ~H"""
    <span>×</span>
    """
  end

  defp status_indicator(assigns) do
    ~H"""
    <span>○</span>
    """
  end

  defp cost_display(cost) when is_float(cost), do: "$#{:erlang.float_to_binary(cost, decimals: 4)}"
  defp cost_display(_), do: "$0.0000"

  defp model_label(models) do
    primary = Map.get(models, :primary, %{})
    label = Map.get(primary, :label)
    if label && label != "", do: label
  end

  # ── Left Panel ──────────────────────────────────────────────────

  attr :workspace, :string, required: true
  attr :workspaces, :list, default: []
  attr :files, :list, default: []
  attr :agents, :list, default: []
  attr :status, :atom, default: :idle
  attr :memory_stats, :map, default: %{}
  attr :mode, :atom, required: true
  attr :models, :map, required: true
  attr :model_routing, :map, default: %{mode: "auto"}

  def left_panel(assigns) do
    skills =
      try do
        Worth.Skill.Registry.all()
      rescue
        _ -> []
      catch
        :exit, _ -> []
      end

    assigns = assign(assigns, :skills, skills)

    ~H"""
    <aside class={"w-52 overflow-y-auto shrink-0 text-sm #{color(:background)} #{color(:border)} border-r"}>
      <div class={"px-3 py-2 font-semibold text-[11px] uppercase tracking-wider #{color(:accent)}"}>
        Workspace
      </div>

      <%!-- Workspaces --%>
      <div class="px-3 py-2.5">
        <div class={"font-semibold text-[10px] uppercase tracking-wider mb-1.5 #{color(:text_muted)}"} style="font-family: var(--font-ui);">Workspaces</div>
        <div class="max-h-48 overflow-y-auto -mr-2 pr-2">
          <div
            :for={ws <- @workspaces}
            phx-click="switch_workspace"
            phx-value-name={ws}
            class={"text-xs py-px flex items-center gap-1.5 cursor-pointer #{ws == @workspace && "#{color(:text)} font-medium" || "#{color(:text_muted)} hover:#{color(:text)}"}"}
            style="font-family: var(--font-mono);"
          >
            <span class={if ws == @workspace, do: color(:accent), else: color(:text_muted)}>
              {if ws == @workspace, do: "●", else: "○"}
            </span>
            {ws}
          </div>
        </div>
      </div>

      <%!-- Agents --%>
      <div class="px-3 py-2.5">
        <div class={"font-semibold text-[10px] uppercase tracking-wider mb-1.5 #{color(:text_muted)}"} style="font-family: var(--font-ui);">Agents</div>
        <div :if={@agents == [] && @status == :running} class={"text-xs flex items-center gap-1.5 #{color(:warning)}"} style="font-family: var(--font-mono);">
          <.w_spinner /> working…
        </div>
        <div :if={@agents == [] && @status != :running} class={"text-xs #{color(:text_dim)}"} style="font-family: var(--font-mono);">○ idle</div>
        <div :for={agent <- @agents} class="text-xs py-px" style="font-family: var(--font-mono);">
          <.agent_row agent={agent} />
        </div>
      </div>

      <%!-- Model --%>
      <div class="px-3 py-2.5">
        <div class={"font-semibold text-[10px] uppercase tracking-wider mb-1.5 #{color(:text_muted)}"} style="font-family: var(--font-ui);">Model</div>
        <div class={"text-[11px] space-y-0.5 #{color(:text_muted)}"} style="font-family: var(--font-mono);">
          <div :if={@model_routing[:coding_agent]}>
            <span class={color(:accent)}>{@model_routing.coding_agent[:name]}</span>
            <div class={"#{color(:text_dim)} text-[10px]"}>coding agent · /model auto to switch back</div>
          </div>
          <div :if={
            @model_routing[:mode] == "manual" and not is_nil(@model_routing[:manual_model]) and
              is_nil(@model_routing[:coding_agent])
          }>
            <% actual = model_short(@models, :primary)
            configured = manual_model_label(@model_routing.manual_model)
            fallback = actual && actual != configured && actual %>
            <span class={color(:accent)}>{configured}</span>
            <div :if={fallback} class={"#{color(:info)} text-[10px]"}>→ {fallback}</div>
            <div class={"#{color(:text_dim)} text-[10px]"}>manual · /model auto to switch</div>
          </div>
          <div :if={
            (@model_routing[:mode] != "manual" or is_nil(@model_routing[:manual_model])) and
              is_nil(@model_routing[:coding_agent])
          }>
            <div class={color(:accent)}>primary</div>
            <div class={color(:text_muted)}>
              <%= case model_short(@models, :primary) do %>
                <% nil -> %>
                  <.w_spinner />
                <% label -> %>
                  {label}
              <% end %>
            </div>
            <div class={"#{color(:accent)} mt-1"}>light</div>
            <div class={color(:text_muted)}>
              <%= case model_short(@models, :lightweight) do %>
                <% nil -> %>
                  <.w_spinner />
                <% label -> %>
                  {label}
              <% end %>
            </div>
            <div class={"#{color(:text_dim)} text-[10px] mt-1"}>{routing_mode_label(@model_routing)}</div>
          </div>
        </div>
      </div>

      <%!-- Tools --%>
      <div class="px-3 py-2.5">
        <div class={"font-semibold text-[10px] uppercase tracking-wider mb-1.5 #{color(:text_muted)}"} style="font-family: var(--font-ui);">Tools</div>
        <div
          :for={tool <- ~w(read_file write_file edit_file bash list_files memory_query skill_list)}
          class={"text-xs #{color(:text_muted)} py-px"}
          style="font-family: var(--font-mono);"
        >
          {tool}
        </div>
      </div>

      <%!-- Skills --%>
      <div class="px-3 py-2.5">
        <div class={"font-semibold text-[10px] uppercase tracking-wider mb-1.5 #{color(:text_muted)}"} style="font-family: var(--font-ui);">Skills</div>
        <div :if={@skills == []} class={"text-xs #{color(:text_dim)}"} style="font-family: var(--font-mono);">(none)</div>
        <div :for={s <- @skills} class={"text-xs #{color(:text_muted)} py-px"} style="font-family: var(--font-mono);">
          {s.name} <span class={color(:text_dim)}>[{s.trust_level}]</span>
        </div>
      </div>

      <%!-- Files --%>
      <div class="px-3 py-2.5">
        <div class={"font-semibold text-[10px] uppercase tracking-wider mb-1.5 #{color(:text_muted)}"} style="font-family: var(--font-ui);">Files</div>
        <div :if={@files == []} class={"text-xs #{color(:text_dim)}"} style="font-family: var(--font-mono);">(no files)</div>
        <div :for={file <- Enum.take(@files, 20)} class={"text-xs truncate py-px #{color(:text_muted)}"} style="font-family: var(--font-mono);">
          {file}
        </div>
      </div>

      <%!-- Memory Inspector --%>
      <.memory_inspector workspace={@workspace} stats={@memory_stats} />
    </aside>
    """
  end

  # ── Memory Inspector ────────────────────────────────────────────

  attr :workspace, :string, required: true
  attr :stats, :map, default: %{}

  def memory_inspector(assigns) do
    working_count = Map.get(assigns.stats, :working_count, 0)
    recent_count = Map.get(assigns.stats, :recent_count, 0)
    memory_enabled = Map.get(assigns.stats, :enabled, true)

    assigns = assign(assigns, working_count: working_count, recent_count: recent_count, memory_enabled: memory_enabled)

    ~H"""
    <div class="px-3 py-2.5">
      <div class={"font-semibold text-[10px] uppercase tracking-wider mb-1.5 #{color(:text_muted)} flex items-center justify-between"} style="font-family: var(--font-ui);">
        <span>Memory</span>
        <span :if={!@memory_enabled} class={"#{color(:warning)} text-[10px]"}>disabled</span>
      </div>

      <div class={"text-[11px] space-y-0.5 #{@memory_enabled && color(:text_muted) || color(:text_dim)}"} style="font-family: var(--font-mono);">
        <div class="flex justify-between">
          <span>Working:</span>
          <span class={color(:accent)}>{@working_count}</span>
        </div>
        <div class="flex justify-between">
          <span>Stored:</span>
          <span class={color(:accent)}>{@recent_count}</span>
        </div>
      </div>

      <%!-- Quick Actions --%>
      <div class="mt-2 flex gap-1">
        <button
          phx-click="memory_query"
          phx-value-workspace={@workspace}
          class={"px-2 py-0.5 text-[10px] rounded #{color(:button_secondary)} opacity-80 hover:opacity-100 cursor-pointer transition-opacity"}
          title="Query recent memories"
        >
          query
        </button>
        <button
          phx-click="memory_flush"
          phx-value-workspace={@workspace}
          class={"px-2 py-0.5 text-[10px] rounded #{color(:button_secondary)} opacity-80 hover:opacity-100 cursor-pointer transition-opacity"}
          title="Flush working memory to storage"
        >
          flush
        </button>
      </div>
    </div>
    """
  end

  defp agent_row(assigns) do
    ~H"""
    <div class={"flex items-center gap-1 #{agent_status_class(@agent.status)}"}>
      <span :if={@agent.status == :running} class="spinner"></span>
      <span :if={@agent.status == :done} class={color(:success)}>✓</span>
      <span :if={@agent.status == :error} class={color(:error)}>×</span>
      <span :if={@agent.status not in [:running, :done, :error]} class={color(:text_dim)}>○</span>
      <span class="truncate">{agent_label(@agent)}</span>
      <span :if={@agent.current_tool} class={"#{color(:text_dim)} shrink-0"}>({@agent.current_tool})</span>
      <button
        :if={@agent.status == :running}
        phx-click="stop"
        class={"ml-auto shrink-0 #{color(:error)} hover:opacity-80 cursor-pointer"}
        title="Stop agent"
      >
        ■
      </button>
    </div>
    """
  end

  defp agent_status_class(:running), do: color(:warning)
  defp agent_status_class(:done), do: color(:success)
  defp agent_status_class(:error), do: color(:error)
  defp agent_status_class(_), do: color(:text_dim)

  defp agent_label(agent), do: agent.label || agent.session_id

  # ── Metrics Panel (right sidebar) ────────────────────────────────

  attr :models, :map, required: true
  attr :cost, :float, required: true
  attr :turn, :integer, required: true

  def metrics_panel(assigns) do
    default_metrics = %{
      cost: 0.0,
      calls: 0,
      input_tokens: 0,
      output_tokens: 0,
      cache_read: 0,
      cache_write: 0,
      embed_calls: 0,
      embed_cost: 0.0,
      by_provider: %{},
      started_at: System.system_time(:millisecond)
    }

    metrics =
      try do
        Worth.Metrics.session()
      rescue
        _ -> default_metrics
      catch
        :exit, _ -> default_metrics
      end

    duration_min =
      div(System.system_time(:millisecond) - (metrics.started_at || System.system_time(:millisecond)), 60_000)

    avg_cost_per_call = if metrics.calls > 0, do: metrics.cost / metrics.calls, else: 0.0

    catalog_info =
      try do
        Agentic.LLM.Catalog.info()
      rescue
        _ -> %{model_count: 0, providers: %{}}
      catch
        :exit, _ -> %{model_count: 0, providers: %{}}
      end

    coding_agents =
      try do
        Worth.CodingAgents.discover()
      rescue
        _ -> []
      catch
        :exit, _ -> []
      end

    assigns =
      assigns
      |> assign(:metrics, metrics)
      |> assign(:duration_min, duration_min)
      |> assign(:avg_cost, avg_cost_per_call)
      |> assign(:catalog_info, catalog_info)
      |> assign(:coding_agents, coding_agents)

    ~H"""
    <aside class={"w-72 overflow-y-auto shrink-0 text-sm #{color(:background)} #{color(:border)} border-l"}>
      <div class={"px-3 py-2 font-semibold text-[11px] uppercase tracking-wider #{color(:accent)}"}>
        Metrics
      </div>

      <%!-- Session --%>
      <div class="px-3 py-2.5">
        <div class={"font-semibold text-[10px] uppercase tracking-wider mb-1.5 #{color(:text_muted)}"} style="font-family: var(--font-ui);">Session</div>
        <div class={"text-[11px] #{color(:text_muted)} space-y-0.5"} style="font-family: var(--font-mono);">
          <div class="flex justify-between">
            <span>Duration:</span>
            <span>{@duration_min}m</span>
          </div>
          <div class="flex justify-between">
            <span>Cost:</span>
            <span class={color(:accent)}>{cost_display(@cost)}</span>
          </div>
          <div class="flex justify-between">
            <span>Turns:</span>
            <span>{@turn}</span>
          </div>
          <div class="flex justify-between">
            <span>Calls:</span>
            <span>{@metrics.calls}</span>
          </div>
          <div class={"flex justify-between #{color(:text_dim)}"}>
            <span>Avg/call:</span>
            <span>${Float.round(@avg_cost, 4)}</span>
          </div>
        </div>
      </div>

      <%!-- Tokens --%>
      <div class="px-3 py-2.5">
        <div class={"font-semibold text-[10px] uppercase tracking-wider mb-1.5 #{color(:text_muted)}"} style="font-family: var(--font-ui);">Tokens</div>
        <div class={"text-[11px] #{color(:text_muted)} space-y-0.5"} style="font-family: var(--font-mono);">
          <div class="flex justify-between">
            <span>Input:</span>
            <span>{format_int(@metrics.input_tokens)}</span>
          </div>
          <div class="flex justify-between">
            <span>Output:</span>
            <span>{format_int(@metrics.output_tokens)}</span>
          </div>
          <div class={"flex justify-between #{color(:text_dim)}"}>
            <span>Total:</span>
            <span>{format_int(@metrics.input_tokens + @metrics.output_tokens)}</span>
          </div>
        </div>
      </div>

      <%!-- Cache & Embeddings --%>
      <div class="px-3 py-2.5">
        <div class={"font-semibold text-[10px] uppercase tracking-wider mb-1.5 #{color(:text_muted)}"} style="font-family: var(--font-ui);">Cache & Embeddings</div>
        <div class={"text-[11px] #{color(:text_muted)} space-y-0.5"} style="font-family: var(--font-mono);">
          <div class="flex justify-between">
            <span>Cache read:</span>
            <span class={color(:success)}>{format_int(@metrics.cache_read)}</span>
          </div>
          <div class="flex justify-between">
            <span>Cache write:</span>
            <span class={color(:warning)}>{format_int(@metrics.cache_write)}</span>
          </div>
          <div class="flex justify-between">
            <span>Embeddings:</span>
            <span>{@metrics.embed_calls} calls</span>
          </div>
          <div class={"flex justify-between #{color(:text_dim)}"}>
            <span>Embed cost:</span>
            <span>${Float.round(@metrics.embed_cost, 4)}</span>
          </div>
        </div>
      </div>

      <%!-- By Provider --%>
      <div :if={@metrics.by_provider != %{}} class="px-3 py-2.5">
        <div class={"font-semibold text-[10px] uppercase tracking-wider mb-1.5 #{color(:text_muted)}"} style="font-family: var(--font-ui);">By Provider</div>
        <div :for={{provider, p} <- @metrics.by_provider} class={"text-[11px] #{color(:text_dim)}"} style="font-family: var(--font-mono);">
          <div class="flex justify-between">
            <span>{provider}:</span>
            <span>${Float.round(p.cost, 4)} ({p.calls})</span>
          </div>
        </div>
      </div>

      <%!-- Providers --%>
      <div :if={@catalog_info.providers != %{}} class="px-3 py-2.5">
        <div class={"font-semibold text-[10px] uppercase tracking-wider mb-1.5 #{color(:text_muted)}"} style="font-family: var(--font-ui);">Providers</div>
        <div
          :for={{id, stat} <- @catalog_info.providers}
          class={"flex justify-between text-[11px] #{if stat.status == :no_creds, do: color(:text_dim), else: color(:text_muted)}"}
          style="font-family: var(--font-mono);"
        >
          <span>{id |> Atom.to_string() |> String.capitalize()}:</span>
          <span>{provider_detail(stat)}</span>
        </div>
      </div>

      <%!-- Coding Agents --%>
      <div :if={@coding_agents != []} class="px-3 py-2.5">
        <div class={"font-semibold text-[10px] uppercase tracking-wider mb-1.5 #{color(:text_muted)}"} style="font-family: var(--font-ui);">Coding Agents</div>
        <div :for={agent <- @coding_agents} class="text-[11px] flex items-center gap-1.5" style="font-family: var(--font-mono);">
          <span class={if agent.available, do: color(:success), else: color(:text_dim)}>
            {if agent.available, do: "●", else: "○"}
          </span>
          <span class={color(:text_muted)}>{agent.display_name}</span>
          <span class={"#{color(:text_dim)} ml-auto"}>({agent.cli_name})</span>
        </div>
      </div>
    </aside>
    """
  end

  # ── Input bar ───────────────────────────────────────────────────

  attr :mode, :atom, required: true
  attr :status, :atom, required: true

  def input_bar(assigns) do
    ~H"""
    <div class={"border-t px-4 py-2.5 shrink-0 #{color(:border)} #{color(:background)}"}>
      <form phx-submit="submit" class="flex items-start gap-3">
        <span class={"#{color(:text_muted)} shrink-0 select-none"} style="font-family: var(--font-mono); font-size: 13px; line-height: 20px; padding-top: 1px;">{@mode} ></span>
        <textarea
          name="text"
          rows="1"
          placeholder={if @status == :running, do: "Waiting for response...", else: "Type a message or /command…"}
          disabled={@status == :running}
          autocomplete="off"
          phx-hook="ChatInput"
          id="chat-input"
          class="chat-input-textarea flex-1"
        ></textarea>
        <button
          :if={@status != :running}
          type="submit"
          class="btn-molten shrink-0"
          style="padding: 5px 14px; font-size: 11px;"
        >
          Send
        </button>
        <button
          :if={@status == :running}
          type="button"
          phx-click="stop"
          class={"shrink-0 #{color(:error)}"}
          style="padding: 5px 14px; font-size: 11px; font-weight: 600; border: 1px solid rgba(255,59,47,0.3); border-radius: 2px; background: transparent; cursor: pointer; font-family: var(--font-ui);"
        >
          Stop
        </button>
      </form>
    </div>
    """
  end

  # ── Sidebar helpers ─────────────────────────────────────────────

  defp routing_mode_label(%{mode: "auto", preference: "optimize_price", filter: "free_only"}),
    do: "auto · price · free only"

  defp routing_mode_label(%{mode: "auto", preference: pref, filter: "free_only"}), do: "auto · #{pref} · free only"
  defp routing_mode_label(%{mode: "auto", preference: pref}), do: "auto · #{pref}"
  defp routing_mode_label(_), do: "auto"

  defp model_short(models, tier) do
    model = Map.get(models, tier, %{})
    label = Map.get(model, :label)

    if label && label != "" do
      # Strip provider prefix like "Anthropic: " for brevity
      String.replace(label, ~r/^[A-Za-z]+:\s*/, "")
    end
  end

  defp manual_model_label(%{model_id: model_id}) do
    # Show just the model id part, strip provider prefix if nested (e.g. "anthropic/claude-opus-4.6")
    model_id
    |> String.split("/")
    |> List.last()
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
end
