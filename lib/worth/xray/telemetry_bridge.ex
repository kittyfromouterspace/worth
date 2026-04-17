defmodule Worth.XRay.TelemetryBridge do
  @moduledoc """
  Bridges AgentEx telemetry events to the x-ray panel via PubSub.

  Attaches to relevant `:telemetry` events and broadcasts them on the
  `"xray:events"` PubSub topic so ChatLive can display the full call
  stack from message submission to response.
  """

  use GenServer

  require Logger

  @handler_id "worth-xray-telemetry-bridge"

  @events [
    # Session lifecycle
    [:agent_ex, :session, :start],
    [:agent_ex, :session, :stop],
    [:agent_ex, :session, :error],
    [:agent_ex, :session, :resume],
    # Pipeline stages
    [:agent_ex, :pipeline, :stage, :start],
    [:agent_ex, :pipeline, :stage, :stop],
    # LLM calls
    [:agent_ex, :llm_call, :start],
    [:agent_ex, :llm_call, :stop],
    # Tool execution
    [:agent_ex, :tool, :start],
    [:agent_ex, :tool, :stop],
    # Model routing
    [:agent_ex, :model_router, :resolve, :stop],
    [:agent_ex, :model_router, :auto, :selected],
    [:agent_ex, :model_router, :auto, :fallback],
    [:agent_ex, :model_router, :analysis, :stop],
    [:agent_ex, :model_router, :selection, :stop],
    # Context management
    [:agent_ex, :context, :compact],
    [:agent_ex, :context, :cost_limit],
    # Phase transitions & orchestration
    [:agent_ex, :phase, :transition],
    [:agent_ex, :mode_router, :route],
    [:agent_ex, :commitment, :detected],
    [:agent_ex, :orchestration, :turn],
    # Planning
    [:agent_ex, :plan, :created],
    [:agent_ex, :plan, :step, :complete],
    [:agent_ex, :plan, :all_complete],
    # Circuit breaker
    [:agent_ex, :circuit_breaker, :trip],
    [:agent_ex, :circuit_breaker, :recover],
    # Memory
    [:agent_ex, :memory, :ingest],
    [:agent_ex, :memory, :evict],
    [:agent_ex, :memory, :retrieval, :stop],
    # Sub-agents
    [:agent_ex, :subagent, :spawn],
    [:agent_ex, :subagent, :complete],
    [:agent_ex, :subagent, :error],
    # Gateway proxy
    [:agent_ex, :gateway, :request, :start],
    [:agent_ex, :gateway, :request, :stop]
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :telemetry.detach(@handler_id)
    :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle_event/4, nil)
    {:ok, %{}}
  end

  @doc false
  def handle_event(event_name, measurements, metadata, _config) do
    xray_event = translate(event_name, measurements, metadata)

    if xray_event do
      Phoenix.PubSub.broadcast(Worth.PubSub, "xray:events", {:xray_telemetry, xray_event})
    end
  rescue
    _ -> :ok
  end

  # ── Session ──────────────────────────────────────────────────────

  defp translate([:agent_ex, :session, :start], _m, meta) do
    {:session, %{phase: :start, session_id: meta[:session_id], mode: meta[:mode], profile: meta[:profile]}}
  end

  defp translate([:agent_ex, :session, :stop], m, meta) do
    {:session, %{
      phase: :stop, session_id: meta[:session_id], mode: meta[:mode],
      duration_ms: native_to_ms(m[:duration]), cost_usd: m[:cost], tokens: m[:tokens], steps: m[:steps]
    }}
  end

  defp translate([:agent_ex, :session, :error], m, meta) do
    {:session, %{
      phase: :error, session_id: meta[:session_id], mode: meta[:mode],
      error: inspect(meta[:error]), duration_ms: native_to_ms(m[:duration])
    }}
  end

  defp translate([:agent_ex, :session, :resume], _m, meta) do
    {:session, %{phase: :resume, session_id: meta[:session_id], turns_restored: meta[:turns_restored]}}
  end

  # ── Pipeline ─────────────────────────────────────────────────────

  defp translate([:agent_ex, :pipeline, :stage, :start], _m, meta) do
    {:pipeline, %{phase: :start, stage: meta[:stage]}}
  end

  defp translate([:agent_ex, :pipeline, :stage, :stop], m, meta) do
    {:pipeline, %{phase: :stop, stage: meta[:stage], duration_ms: native_to_ms(m[:duration])}}
  end

  # ── LLM calls ───────────────────────────────────────────────────

  defp translate([:agent_ex, :llm_call, :start], _m, meta) do
    {:llm_call, %{phase: :start, model_tier: meta[:model_tier], selection_mode: meta[:model_selection_mode]}}
  end

  defp translate([:agent_ex, :llm_call, :stop], m, meta) do
    {:llm_call, %{
      phase: :stop, provider: meta[:provider], model: meta[:route], model_tier: meta[:model_tier],
      input_tokens: m[:input_tokens], output_tokens: m[:output_tokens],
      cache_read: m[:cache_read], cache_write: m[:cache_write],
      cost_usd: m[:cost_usd], duration_ms: native_to_ms(m[:duration])
    }}
  end

  # ── Tool execution ──────────────────────────────────────────────

  defp translate([:agent_ex, :tool, :start], _m, meta) do
    {:tool_exec, %{phase: :start, tool_name: meta[:tool_name]}}
  end

  defp translate([:agent_ex, :tool, :stop], m, meta) do
    {:tool_exec, %{
      phase: :stop, tool_name: meta[:tool_name], success: meta[:success],
      duration_ms: native_to_ms(m[:duration]), output_bytes: m[:output_bytes]
    }}
  end

  # ── Model routing ───────────────────────────────────────────────

  defp translate([:agent_ex, :model_router, :resolve, :stop], m, meta) do
    {:route_resolve, %{
      selection_mode: meta[:selection_mode], provider: meta[:selected_provider],
      model: meta[:selected_model_id], complexity: meta[:complexity],
      preference: meta[:preference], route_count: m[:route_count],
      duration_ms: native_to_ms(m[:duration]), error: meta[:error]
    }}
  end

  defp translate([:agent_ex, :model_router, :auto, :selected], _m, meta) do
    {:auto_selected, %{
      complexity: meta[:complexity], preference: meta[:preference],
      model: meta[:selected_model], provider: meta[:selected_provider],
      needs_vision: meta[:needs_vision], needs_audio: meta[:needs_audio],
      needs_reasoning: meta[:needs_reasoning], needs_large_context: meta[:needs_large_context],
      estimated_input_tokens: meta[:estimated_input_tokens]
    }}
  end

  defp translate([:agent_ex, :model_router, :auto, :fallback], _m, meta) do
    {:route_fallback, %{session_id: meta[:session_id], reason: meta[:reason]}}
  end

  defp translate([:agent_ex, :model_router, :analysis, :stop], m, meta) do
    {:model_analysis, %{
      method: meta[:method], complexity: meta[:complexity],
      needs_vision: meta[:needs_vision], needs_reasoning: meta[:needs_reasoning],
      needs_large_context: meta[:needs_large_context],
      estimated_input_tokens: meta[:estimated_input_tokens],
      duration_ms: native_to_ms(m[:duration])
    }}
  end

  defp translate([:agent_ex, :model_router, :selection, :stop], m, meta) do
    {:model_scoring, %{
      candidate_count: m[:candidate_count], best_score: m[:best_score],
      provider: meta[:selected_provider], model: meta[:selected_model_id],
      label: meta[:selected_label], complexity: meta[:complexity],
      top3: meta[:top3], duration_ms: native_to_ms(m[:duration])
    }}
  end

  # ── Context management ──────────────────────────────────────────

  defp translate([:agent_ex, :context, :compact], m, meta) do
    {:context_compact, %{
      messages_before: m[:messages_before], messages_after: m[:messages_after],
      pct_before: m[:pct_before], pct_after: m[:pct_after], session_id: meta[:session_id]
    }}
  end

  defp translate([:agent_ex, :context, :cost_limit], m, _meta) do
    {:cost_limit, %{cost_usd: m[:cost_usd], limit_usd: m[:limit_usd]}}
  end

  # ── Phase transitions & orchestration ───────────────────────────

  defp translate([:agent_ex, :phase, :transition], _m, meta) do
    {:phase_transition, %{mode: meta[:mode], from: meta[:from], to: meta[:to]}}
  end

  defp translate([:agent_ex, :mode_router, :route], _m, meta) do
    {:mode_route, %{
      mode: meta[:mode], phase: meta[:phase],
      stop_reason: meta[:stop_reason], action: meta[:action]
    }}
  end

  defp translate([:agent_ex, :commitment, :detected], m, _meta) do
    {:commitment, %{continuations: m[:continuations]}}
  end

  defp translate([:agent_ex, :orchestration, :turn], _m, meta) do
    {:orch_turn, %{
      strategy: meta[:strategy], mode: meta[:mode],
      phase: meta[:phase], stop_reason: meta[:stop_reason]
    }}
  end

  # ── Planning ────────────────────────────────────────────────────

  defp translate([:agent_ex, :plan, :created], m, _meta) do
    {:plan, %{phase: :created, step_count: m[:step_count]}}
  end

  defp translate([:agent_ex, :plan, :step, :complete], _m, meta) do
    {:plan, %{phase: :step_done, step_index: meta[:step_index], total_steps: meta[:total_steps]}}
  end

  defp translate([:agent_ex, :plan, :all_complete], _m, meta) do
    {:plan, %{phase: :all_done, total_steps: meta[:total_steps]}}
  end

  # ── Circuit breaker ─────────────────────────────────────────────

  defp translate([:agent_ex, :circuit_breaker, :trip], m, meta) do
    {:circuit_breaker, %{phase: :trip, tool_name: meta[:tool_name], failure_count: m[:failure_count]}}
  end

  defp translate([:agent_ex, :circuit_breaker, :recover], _m, meta) do
    {:circuit_breaker, %{phase: :recover, tool_name: meta[:tool_name]}}
  end

  # ── Memory ──────────────────────────────────────────────────────

  defp translate([:agent_ex, :memory, :ingest], m, _meta) do
    {:memory_ingest, %{fact_count: m[:fact_count]}}
  end

  defp translate([:agent_ex, :memory, :evict], m, _meta) do
    {:memory_evict, %{evicted_count: m[:evicted_count], remaining_count: m[:remaining_count]}}
  end

  defp translate([:agent_ex, :memory, :retrieval, :stop], m, meta) do
    {:memory_retrieval, %{
      duration_ms: native_to_ms(m[:duration]), context_chars: m[:context_chars],
      cache_hit: m[:cache_hit], incremental: meta[:incremental]
    }}
  end

  # ── Sub-agents ──────────────────────────────────────────────────

  defp translate([:agent_ex, :subagent, :spawn], _m, meta) do
    {:subagent, %{phase: :spawn, session_id: meta[:session_id], parent: meta[:parent_session_id], depth: meta[:depth]}}
  end

  defp translate([:agent_ex, :subagent, :complete], m, meta) do
    {:subagent, %{
      phase: :complete, session_id: meta[:session_id], parent: meta[:parent_session_id],
      duration_ms: native_to_ms(m[:duration]), cost_usd: m[:cost], steps: m[:steps]
    }}
  end

  defp translate([:agent_ex, :subagent, :error], m, meta) do
    {:subagent, %{
      phase: :error, session_id: meta[:session_id], parent: meta[:parent_session_id],
      error: inspect(meta[:error]), duration_ms: native_to_ms(m[:duration])
    }}
  end

  # ── Gateway proxy ───────────────────────────────────────────────

  defp translate([:agent_ex, :gateway, :request, :start], _m, meta) do
    {:gateway_request, %{
      phase: :start,
      call_id: meta[:call_id],
      provider: meta[:provider],
      model: meta[:model],
      stream: meta[:stream],
      messages: meta[:messages],
      tools: meta[:tools],
      system_preview: meta[:system_preview]
    }}
  end

  defp translate([:agent_ex, :gateway, :request, :stop], m, meta) do
    {:gateway_request, %{
      phase: :stop,
      call_id: meta[:call_id],
      provider: meta[:provider],
      status: meta[:status],
      input_tokens: m[:input_tokens] || 0,
      output_tokens: m[:output_tokens] || 0,
      cache_read: m[:cache_read] || 0,
      cache_write: m[:cache_write] || 0,
      stream: meta[:stream],
      chunk_count: meta[:chunk_count],
      ttft_ms: meta[:ttft_ms],
      duration_ms: native_to_ms(m[:duration]),
      raw_response: meta[:raw_response]
    }}
  end

  defp translate(_, _, _), do: nil

  defp native_to_ms(nil), do: nil
  defp native_to_ms(native), do: System.convert_time_unit(native, :native, :millisecond)
end
