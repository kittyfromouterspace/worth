defmodule WorthWeb.ChatLive do
  use WorthWeb, :live_view

  import WorthWeb.ChatComponents

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Worth.Brain.set_ui_pid(self())
      Phoenix.PubSub.subscribe(Worth.PubSub, "agents:updates")
      send(self(), :refresh_model)
      send(self(), :scan_files)
    end

    workspace = Application.get_env(:worth, :current_workspace, "personal")
    mode = Application.get_env(:worth, :current_mode, :code)

    {:ok,
     socket
     |> stream(:messages, [])
     |> assign(
       page_title: "Worth",
       input_text: "",
       status: :idle,
       cost: 0.0,
       workspace: workspace,
       mode: mode,
       models: %{primary: %{label: nil, source: nil}, lightweight: %{label: nil, source: nil}},
       turn: 0,
       streaming_text: "",
       sidebar_visible: true,
       selected_tab: :status,
       active_agents: [],
       workspace_files: [],
       input_history: [],
       history_index: -1
     )}
  end

  # ── Agent events ────────────────────────────────────────────────

  @impl true
  def handle_info({:agent_event, event}, socket) do
    {:noreply, process_event(event, socket)}
  end

  def handle_info(:agents_updated, socket) do
    {:noreply, assign(socket, active_agents: Worth.Agent.Tracker.list_active())}
  end

  def handle_info(:refresh_model, socket) do
    socket = poll_resolved_model(socket)
    if connected?(socket), do: Process.send_after(self(), :refresh_model, 2_000)
    {:noreply, socket}
  end

  def handle_info(:scan_files, socket) do
    files = Worth.Workspace.FileBrowser.scan(socket.assigns.workspace)
    if connected?(socket), do: Process.send_after(self(), :scan_files, 5_000)
    {:noreply, assign(socket, workspace_files: files)}
  end

  def handle_info({:reembed_done, result}, socket) do
    msg =
      case result do
        {:ok, count} -> "Re-embedding complete: #{count} memories processed."
        {:error, reason} -> "Re-embedding failed: #{inspect(reason)}"
      end

    {:noreply, append_system_message(socket, msg)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ── User events ─────────────────────────────────────────────────

  @impl true
  def handle_event("submit", %{"text" => text}, socket) when text != "" do
    socket =
      socket
      |> update(:turn, &(&1 + 1))
      |> push_input_history(text)
      |> stream_insert(:messages, %{id: msg_id(), type: :user, content: text})

    case Worth.UI.Commands.parse(text) do
      :message ->
        {:noreply, send_to_brain(text, socket)}

      {:command, cmd} ->
        {:noreply, WorthWeb.CommandHandler.handle(cmd, text, socket)}
    end
  end

  def handle_event("submit", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, update(socket, :sidebar_visible, &(!&1))}
  end

  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, selected_tab: String.to_existing_atom(tab))}
  end

  def handle_event("keydown", %{"key" => "Tab"}, socket) do
    {:noreply, update(socket, :sidebar_visible, &(!&1))}
  end

  def handle_event("keydown", %{"key" => key}, socket)
      when key in ["1", "2", "3", "4", "5"] do
    tabs = [:status, :usage, :tools, :skills, :logs]
    idx = String.to_integer(key) - 1
    {:noreply, assign(socket, selected_tab: Enum.at(tabs, idx, :status))}
  end

  def handle_event("keydown", _params, socket), do: {:noreply, socket}

  # ── Event processing (ported from Worth.UI.Events) ──────────────

  defp process_event(event, socket) do
    socket = assign(socket, cost: Worth.Metrics.session_cost())

    case event do
      {:text_chunk, chunk} ->
        update(socket, :streaming_text, &(&1 <> chunk))

      {:status, status} ->
        assign(socket, status: status)

      {:model_selected, info} ->
        tier = Map.get(info, :tier, :primary)
        label = Map.get(info, :label) || Map.get(info, :model_id) || "?"
        provider = Map.get(info, :provider_name, "?")
        source = Map.get(info, :source, :unknown)
        slot = %{label: label, source: "#{source}/#{provider}"}
        models = Map.put(socket.assigns.models, tier, slot)
        assign(socket, models: models)

      {:tool_use, name, _ws} when is_binary(name) ->
        stream_insert(socket, :messages, %{
          id: msg_id(),
          type: :tool_call,
          content: %{name: name, input: %{}, status: :running}
        })

      {:tool_use, nil, _ws} ->
        socket

      {:tool_trace, name, _input, output, is_error, _ws} ->
        status = if is_error, do: :failed, else: :success
        output_str = if is_binary(output), do: output, else: inspect(output)

        stream_insert(socket, :messages, %{
          id: msg_id(),
          type: :tool_result,
          content: %{name: name, output: output_str, status: status}
        })

      {:tool_call, %{name: name, input: input}} ->
        stream_insert(socket, :messages, %{
          id: msg_id(),
          type: :tool_call,
          content: %{name: name, input: input}
        })

      {:tool_result, %{name: name, output: output}} ->
        stream_insert(socket, :messages, %{
          id: msg_id(),
          type: :tool_result,
          content: %{name: name, output: output}
        })

      {:agent_reasoning, text, _tool_names, _ws} ->
        stream_insert(socket, :messages, %{id: msg_id(), type: :thinking, content: text})

      {:thinking_chunk, text} ->
        stream_insert(socket, :messages, %{id: msg_id(), type: :thinking, content: text})

      {:done, %{text: text}} ->
        final =
          if socket.assigns.streaming_text != "",
            do: socket.assigns.streaming_text,
            else: text || ""

        socket
        |> stream_insert(:messages, %{id: msg_id(), type: :assistant, content: final})
        |> assign(streaming_text: "", status: :idle)

      {:error, reason} ->
        reason_str = if is_binary(reason), do: reason, else: inspect(reason)

        socket
        |> stream_insert(:messages, %{id: msg_id(), type: :error, content: "Error: #{reason_str}"})
        |> assign(status: :idle, streaming_text: "")

      _ ->
        socket
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp send_to_brain(text, socket) do
    ui_pid = self()

    Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
      case Worth.Brain.send_message(text) do
        {:ok, response} ->
          send(ui_pid, {:agent_event, {:done, response}})

        {:error, reason} ->
          send(ui_pid, {:agent_event, {:error, reason}})
      end
    end)

    assign(socket, status: :running, streaming_text: "")
  end

  defp poll_resolved_model(socket) do
    try do
      primary = AgentEx.ModelRouter.resolve(:primary)
      lightweight = AgentEx.ModelRouter.resolve(:lightweight)

      models = %{
        primary: format_model_slot(primary),
        lightweight: format_model_slot(lightweight)
      }

      assign(socket, models: models)
    rescue
      _ -> socket
    end
  end

  defp format_model_slot(nil), do: %{label: nil, source: nil}

  defp format_model_slot(resolved) do
    %{
      label: Map.get(resolved, :label) || Map.get(resolved, :model_id),
      source: Map.get(resolved, :source),
      context_window: Map.get(resolved, :context_window)
    }
  end

  def append_system_message(socket, msg) do
    stream_insert(socket, :messages, %{id: msg_id(), type: :system, content: msg})
  end

  defp push_input_history(socket, text) do
    history = [text | socket.assigns.input_history] |> Enum.take(50)
    assign(socket, input_history: history, history_index: -1)
  end

  defp msg_id, do: System.unique_integer([:positive]) |> to_string()

  defp render_streaming(text) do
    case Earmark.as_html(text, compact_output: true) do
      {:ok, html, _} -> Phoenix.HTML.raw(html)
      _ -> text
    end
  end
end
