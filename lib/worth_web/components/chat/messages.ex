defmodule WorthWeb.Components.Chat.Messages do
  @moduledoc """
  Message rendering for the Worth chat UI.

  Mirrors the Bedrock UI kit:

    * **user** → small surface card (`#1A1A1E` on `#3A3A3F` border) with
      `you` meta line and body text
    * **assistant** → no card; `worth` meta line, then markdown body, with
      a thinking strip prepended if present
    * **tool_call / tool_result** → terminal-flavored `tool-call` block
      (amber name, muted args, ore-green ✓ result)
    * **thinking** → italic `msg-thinking` strip
    * **system** → muted preformatted block with action affordances
    * **error** → molten card with `err` meta
  """
  use Phoenix.Component

  import WorthWeb.ThemeHelper, only: [color: 1]
  import WorthWeb.Components.Brand, only: [w_spinner: 1]

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
    <div class="msg-meta">you</div>
    <div class={"leading-relaxed #{color(:text)}"}>{@msg.content}</div>
    """
  end

  defp message_content(%{msg: %{type: :assistant}} = assigns) do
    {thinking, response} = split_thinking(assigns.msg.content)
    model = Map.get(assigns.msg, :model)
    assigns = assign(assigns, thinking: thinking, response: response, model: model)

    ~H"""
    <div class="msg-meta">worth<span :if={@model && @model != ""}> · {@model}</span></div>
    <div
      :if={@thinking != ""}
      class="msg-thinking mb-2"
    >
      thinking · {String.slice(@thinking, 0, 500)}{if String.length(@thinking) > 500, do: "…", else: ""}
    </div>
    <div class="markdown-content">{render_markdown(@response)}</div>
    """
  end

  defp message_content(%{msg: %{type: :system}} = assigns) do
    has_consent = Map.has_key?(assigns.msg, :learning_consent)
    has_learning = Map.has_key?(assigns.msg, :learning_report)
    has_permission = Map.has_key?(assigns.msg, :permission_agents)
    has_mapping = Map.has_key?(assigns.msg, :project_mapping)

    assigns =
      assigns
      |> assign(:has_consent, has_consent)
      |> assign(:has_learning, has_learning)
      |> assign(:has_permission, has_permission)
      |> assign(:has_mapping, has_mapping)

    ~H"""
    <div class="msg-meta">sys</div>
    <pre class={"whitespace-pre-wrap text-xs #{color(:text_muted)}"} style="font-family: var(--font-mono);">{@msg.content}</pre>
    <.learning_consent_actions :if={@has_consent} />
    <.permission_actions :if={@has_permission} agents={@msg.permission_agents} />
    <.project_mapping_actions :if={@has_mapping} projects={@msg.project_mapping} workspace={@msg.mapping_workspace} />
    <.learning_actions :if={@has_learning} report={@msg.learning_report} />
    """
  end

  defp message_content(%{msg: %{type: :error}} = assigns) do
    ~H"""
    <div class="msg-meta" style="color: #FF3B2F;">err</div>
    <div class={color(:error)}>{@msg.content}</div>
    """
  end

  defp message_content(%{msg: %{type: :tool_call, content: content}} = assigns) do
    args_summary = format_args(content[:input])
    running? = content[:status] == :running
    assigns = assign(assigns, name: content.name, args: args_summary, running: running?)

    ~H"""
    <div>
      <span class="tool-call-name">{@name}</span><span :if={@args != ""} class="tool-call-args">({@args})</span>
      <span :if={@running} class="ml-2" style="color: #F0B341;"><.w_spinner /></span>
    </div>
    """
  end

  defp message_content(%{msg: %{type: :tool_result, content: content}} = assigns) do
    status = Map.get(content, :status, :success)
    output = Map.get(content, :output, "")
    summary = result_summary(status, output)
    assigns = assign(assigns, status: status, summary: summary)

    ~H"""
    <div class={"tool-call-result #{if @status == :failed, do: "text-[#FF3B2F]", else: ""}"}>
      {@summary}
    </div>
    """
  end

  defp message_content(%{msg: %{type: :thinking}} = assigns) do
    ~H"""
    thinking · {String.slice(@msg.content, 0, 200)}
    """
  end

  defp message_content(assigns) do
    ~H"""
    <div class={"text-xs #{color(:text_dim)}"}>{inspect(@msg)}</div>
    """
  end

  # ── Learning Actions ────────────────────────────────────────────

  defp learning_consent_actions(assigns) do
    ~H"""
    <div class="flex gap-2 mt-2">
      <button
        phx-click="enable_learning"
        class={"px-3 py-1 rounded text-xs font-semibold transition-colors #{color(:button_primary)} cursor-pointer"}
      >
        Yes, enable learning
      </button>
      <button
        phx-click="disable_learning"
        class={"px-2 py-1 rounded text-xs font-semibold transition-colors #{color(:button_secondary)} cursor-pointer"}
      >
        No thanks
      </button>
    </div>
    """
  end

  attr :agents, :list, required: true

  defp permission_actions(assigns) do
    ~H"""
    <div class="mt-2 space-y-2">
      <div class="flex gap-2">
        <button
          phx-click="grant_all_agents"
          class={"px-3 py-1 rounded text-xs font-semibold transition-colors #{color(:button_primary)} cursor-pointer"}
        >
          Grant access to all
        </button>
      </div>
      <div class="space-y-1">
        <%= for agent <- @agents do %>
          <div class="flex items-center gap-2">
            <span class={"text-xs #{color(:text_muted)}"}>{format_agent_name(agent.agent)} — {hd(agent.data_paths)}</span>
            <button
              phx-click="grant_agent_permission"
              phx-value-agent={agent.agent}
              class={"px-2 py-0.5 rounded text-xs transition-colors #{color(:button_primary)} cursor-pointer"}
            >
              Allow
            </button>
            <button
              phx-click="deny_agent_permission"
              phx-value-agent={agent.agent}
              class={"px-2 py-0.5 rounded text-xs transition-colors #{color(:button_secondary)} cursor-pointer"}
            >
              Deny
            </button>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_agent_name(:claude_code), do: "Claude Code"
  defp format_agent_name(:codex), do: "Codex"
  defp format_agent_name(:gemini), do: "Gemini"
  defp format_agent_name(:opencode), do: "OpenCode"
  defp format_agent_name(name), do: name |> Phoenix.HTML.Safe.to_iodata() |> to_string()

  attr :projects, :map, required: true
  attr :workspace, :string, required: true

  defp project_mapping_actions(assigns) do
    ~H"""
    <div class="mt-2 space-y-2">
      <div class="flex gap-2">
        <button
          phx-click="map_all_projects"
          phx-value-workspace={@workspace}
          class={"px-3 py-1 rounded text-xs font-semibold transition-colors #{color(:button_primary)} cursor-pointer"}
        >
          Select all projects
        </button>
      </div>
      <%= for {agent, projects} <- @projects do %>
        <div class="space-y-1">
          <div class={"text-xs font-semibold #{color(:text)}"}>{format_agent_name(agent)}</div>
          <div class="ml-2 flex flex-wrap gap-1">
            <%= for project <- projects do %>
              <button
                phx-click="map_projects"
                phx-value-workspace={@workspace}
                phx-value-agent={agent}
                phx-value-projects={Jason.encode!(projects)}
                class={"px-2 py-0.5 rounded text-xs transition-colors #{color(:button_secondary)} cursor-pointer"}
              >
                {project}
              </button>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  attr :report, :map, required: true

  defp learning_actions(assigns) do
    ~H"""
    <div class="flex gap-2 mt-2">
      <button
        phx-click="approve_learning"
        phx-value-workspace={@report.workspace}
        class={"px-3 py-1 rounded text-xs font-semibold transition-colors #{color(:button_primary)} cursor-pointer"}
      >
        Yes, learn from this workspace
      </button>
      <button
        phx-click="decline_learning"
        phx-value-workspace={@report.workspace}
        class={"px-2 py-1 rounded text-xs font-semibold transition-colors #{color(:button_secondary)} cursor-pointer"}
      >
        No, skip for now
      </button>
    </div>
    """
  end

  defp message_wrapper_class(:user), do: "msg-user"
  defp message_wrapper_class(:assistant), do: ""
  defp message_wrapper_class(:error), do: "py-2 px-3 rounded-sm #{color(:message_error_bg)}"
  defp message_wrapper_class(:tool_call), do: "tool-call"
  defp message_wrapper_class(:tool_result), do: "tool-call"
  defp message_wrapper_class(:thinking), do: "msg-thinking"
  defp message_wrapper_class(:system), do: "py-2 px-3 rounded-sm #{color(:message_system_bg)}"
  defp message_wrapper_class(_), do: ""

  # Render tool args inline for the call line, truncated. Mirrors the UI kit's
  # `(path: "lib/worth/vault.ex")` summary. We don't try to be perfect — the
  # full input is available in the X-ray panel.
  defp format_args(nil), do: ""
  defp format_args(map) when is_map(map) and map_size(map) == 0, do: ""

  defp format_args(map) when is_map(map) do
    map
    |> Enum.take(2)
    |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{inspect_short(v)}" end)
  end

  defp format_args(_), do: ""

  defp inspect_short(v) when is_binary(v) do
    if String.length(v) > 40, do: ~s("#{String.slice(v, 0, 40)}…"), else: ~s("#{v}")
  end

  defp inspect_short(v), do: v |> inspect() |> String.slice(0, 40)

  defp result_summary(status, output) do
    glyph = if status == :failed, do: "×", else: "✓"

    first =
      output
      |> to_string()
      |> String.split("\n", trim: true)
      |> Enum.find(&(String.trim(&1) != ""))

    case first do
      nil -> "#{glyph} done"
      line -> "#{glyph} #{String.slice(line, 0, 120)}"
    end
  end

  # ── Markdown rendering ─────────────────────────────────────────

  @think_regex ~r/<think>(.*?)<\/think>/s
  defp split_thinking(text) when is_binary(text) do
    case Regex.run(@think_regex, text) do
      [full_match, thinking] ->
        response = text |> String.replace(full_match, "") |> String.trim()
        {String.trim(thinking), response}

      nil ->
        {"", text}
    end
  end

  defp split_thinking(_), do: {"", ""}

  defp render_markdown(nil), do: ""
  defp render_markdown(""), do: ""

  defp render_markdown(text) do
    case MDEx.to_html(text) do
      {:ok, html} -> Phoenix.HTML.raw(html)
      _ -> text
    end
  end
end
