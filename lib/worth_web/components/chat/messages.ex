defmodule WorthWeb.Components.Chat.Messages do
  @moduledoc """
  Message rendering components for the Worth chat UI.
  """
  use Phoenix.Component

  import WorthWeb.CoreComponents, only: [icon: 1]
  import WorthWeb.ThemeHelper, only: [color: 1]

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
      <span class={"font-semibold shrink-0 #{color(:text_muted)}"}>you</span>
      <span class={color(:text)}>{@msg.content}</span>
    </div>
    """
  end

  defp message_content(%{msg: %{type: :assistant}} = assigns) do
    {thinking, response} = split_thinking(assigns.msg.content)
    assigns = assign(assigns, thinking: thinking, response: response)

    ~H"""
    <div class="flex gap-2">
      <span class={"font-semibold shrink-0 #{color(:text)}"}>ai</span>
      <div class="flex-1 min-w-0">
        <div :if={@thinking != ""} class={"text-xs italic mb-2 pl-3 border-l-2 #{color(:message_thinking_border)} #{color(:text_dim)}"}>
          {String.slice(@thinking, 0, 500)}{if String.length(@thinking) > 500, do: "…", else: ""}
        </div>
        <div class="markdown-content">{render_markdown(@response)}</div>
      </div>
    </div>
    """
  end

  defp message_content(%{msg: %{type: :system}} = assigns) do
    has_consent = Map.has_key?(assigns.msg, :learning_consent)
    has_learning = Map.has_key?(assigns.msg, :learning_report)
    has_permission = Map.has_key?(assigns.msg, :permission_agents)
    has_mapping = Map.has_key?(assigns.msg, :project_mapping)
    assigns = assign(assigns, :has_consent, has_consent)
    assigns = assign(assigns, :has_learning, has_learning)
    assigns = assign(assigns, :has_permission, has_permission)
    assigns = assign(assigns, :has_mapping, has_mapping)

    ~H"""
    <div class="flex gap-2">
      <span class={"font-semibold shrink-0 #{color(:text_dim)}"}>sys</span>
      <div class="flex-1 min-w-0">
        <pre class={"whitespace-pre-wrap text-xs #{color(:text_muted)}"}>{@msg.content}</pre>
        <.learning_consent_actions :if={@has_consent} />
        <.permission_actions :if={@has_permission} agents={@msg.permission_agents} />
        <.project_mapping_actions :if={@has_mapping} projects={@msg.project_mapping} workspace={@msg.mapping_workspace} />
        <.learning_actions :if={@has_learning} report={@msg.learning_report} />
      </div>
    </div>
    """
  end

  defp message_content(%{msg: %{type: :error}} = assigns) do
    ~H"""
    <div class="flex gap-2">
      <span class={"font-semibold shrink-0 #{color(:error)}"}>err</span>
      <span class={color(:error)}>{@msg.content}</span>
    </div>
    """
  end

  defp message_content(%{msg: %{type: :tool_call, content: content}} = assigns) do
    assigns = assign(assigns, :name, content.name)

    ~H"""
    <div class="flex items-center gap-2 text-xs">
      <.icon name="hero-wrench-screwdriver" class={"size-3 #{color(:text_muted)}"} />
      <span class={"font-semibold #{color(:text_muted)}"}>{@name}</span>
      <span :if={@msg.content[:status] == :running} class={"spinner #{color(:warning)}"}></span>
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
        <span class={if @status == :failed, do: color(:error), else: color(:success)}>
          {if @status == :failed, do: "× ", else: "✓ "}
        </span>
        <span class={color(:text_muted)}>{@name}</span>
      </div>
      <pre :if={@output != ""} class={"whitespace-pre-wrap ml-5 mt-1 max-h-32 overflow-y-auto #{color(:text_dim)}"}>{@output}</pre>
    </div>
    """
  end

  defp message_content(%{msg: %{type: :thinking}} = assigns) do
    ~H"""
    <div class="flex gap-2 text-xs">
      <span class={"italic shrink-0 #{color(:text_dim)}"}>thinking</span>
      <span class={"italic #{color(:text_dim)}"}>{String.slice(@msg.content, 0, 200)}</span>
    </div>
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

  defp message_wrapper_class(:user), do: "py-2 px-3 rounded-md #{color(:message_user_bg)}"
  defp message_wrapper_class(:assistant), do: "py-2 px-3"
  defp message_wrapper_class(:error), do: "py-2 px-3 rounded-md #{color(:message_error_bg)}"
  defp message_wrapper_class(:tool_call), do: "py-1 px-3 ml-4"
  defp message_wrapper_class(:tool_result), do: "py-1 px-3 ml-4"
  defp message_wrapper_class(:thinking), do: "py-1 px-3 ml-4 #{color(:message_thinking_border)}"
  defp message_wrapper_class(:system), do: "py-2 px-3 rounded-md #{color(:message_system_bg)}"
  defp message_wrapper_class(_), do: "py-1 px-3"

  # ── Markdown rendering ─────────────────────────────────────────

  @think_regex ~r/<think>(.*?)<\/think>/s
  defp split_thinking(text) when is_binary(text) do
    case Regex.run(@think_regex, text) do
      [full_match, thinking] ->
        response = String.replace(text, full_match, "") |> String.trim()
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
