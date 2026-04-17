defmodule WorthWeb.Components.Chat.XRay do
  @moduledoc """
  X-Ray debug panel component showing internal system events.
  Toggle via the header button or `/xray` command.
  """
  use Phoenix.Component

  import WorthWeb.CoreComponents, only: [icon: 1]
  import WorthWeb.ThemeHelper, only: [color: 1]

  attr :events, :list, required: true
  attr :visible, :boolean, required: true

  def xray_panel(assigns) do
    ~H"""
    <div
      :if={@visible}
      class={"flex flex-col h-64 shrink-0 border-t #{color(:border)} #{color(:surface)}"}
    >
      <div class={"flex items-center gap-2 px-3 py-1.5 text-xs font-bold #{color(:surface_elevated)} border-b #{color(:border)}"}>
        <.icon name="hero-eye" class="size-3 color(:accent)" />
        <span class="color(:accent)">X-RAY</span>
        <span class="color(:text_dim)">({length(@events)} events)</span>
        <div class="flex-1" />
        <button
          phx-click="clear_xray"
          class={"px-2 py-0.5 rounded text-xs transition-colors #{color(:button_secondary)} cursor-pointer"}
        >
          clear
        </button>
      </div>

      <div class="flex-1 overflow-y-auto p-2 space-y-1 text-xs font-mono">
        <div :if={@events == []} class="color(:text_dim) italic p-2">
          Waiting for events...
        </div>
        <div :for={{event, idx} <- Enum.with_index(Enum.reverse(@events))}>
          <.xray_event event={event} index={idx} />
        </div>
      </div>
    </div>
    """
  end

  defp xray_event(assigns) do
    ~H"""
    <div class={"px-2 py-1 rounded #{color(:surface_elevated)} border-l-2 #{event_border_color(@event)}"}>
      <div class="flex items-center gap-1.5">
        <span class="color(:text_dim) shrink-0">{event_time(@event)}</span>
        <span class={event_type_class(@event)}>{event_type_label(@event)}</span>
        <span class="color(:text) truncate flex-1">{event_summary(@event)}</span>
      </div>
      <div :if={event_detail(@event)} class="mt-1 ml-4 color(:text_muted) whitespace-pre-wrap max-h-32 overflow-y-auto">
        <pre class="text-xs">{event_detail(@event)}</pre>
      </div>
    </div>
    """
  end

  # ── Border colors ───────────────────────────────────────────────

  defp event_border_color({:model_selection, _}), do: "border-ctp-blue"
  defp event_border_color({:tool_call, _}), do: "border-ctp-yellow"
  defp event_border_color({:tool_result, _}), do: "border-ctp-green"
  defp event_border_color({:tool_exec, _}), do: "border-ctp-yellow"
  defp event_border_color({:memory_search, _}), do: "border-ctp-mauve"
  defp event_border_color({:memory_write, _}), do: "border-ctp-pink"
  defp event_border_color({:memory_ingest, _}), do: "border-ctp-pink"
  defp event_border_color({:memory_evict, _}), do: "border-ctp-maroon"
  defp event_border_color({:memory_retrieval, _}), do: "border-ctp-mauve"
  defp event_border_color({:mcp, _}), do: "border-ctp-teal"
  defp event_border_color({:session, _}), do: "border-ctp-lavender"
  defp event_border_color({:llm_call, _}), do: "border-ctp-peach"
  defp event_border_color({:route_resolve, _}), do: "border-ctp-sky"
  defp event_border_color({:auto_selected, _}), do: "border-ctp-sky"
  defp event_border_color({:model_analysis, _}), do: "border-ctp-sapphire"
  defp event_border_color({:model_scoring, _}), do: "border-ctp-sapphire"
  defp event_border_color({:pipeline, _}), do: "border-ctp-overlay1"
  defp event_border_color({:context_compact, _}), do: "border-ctp-flamingo"
  defp event_border_color({:cost_limit, _}), do: "border-ctp-red"
  defp event_border_color({:circuit_breaker, _}), do: "border-ctp-red"
  defp event_border_color({:route_fallback, _}), do: "border-ctp-yellow"
  defp event_border_color({:phase_transition, _}), do: "border-ctp-rosewater"
  defp event_border_color({:mode_route, _}), do: "border-ctp-rosewater"
  defp event_border_color({:commitment, _}), do: "border-ctp-flamingo"
  defp event_border_color({:orch_turn, _}), do: "border-ctp-rosewater"
  defp event_border_color({:plan, _}), do: "border-ctp-green"
  defp event_border_color({:subagent, _}), do: "border-ctp-teal"
  defp event_border_color({:gateway_request, _}), do: "border-ctp-sapphire"
  defp event_border_color(_), do: "border-ctp-overlay0"

  # ── Type labels ─────────────────────────────────────────────────

  defp event_type_label({:model_selection, _}), do: "MODEL"
  defp event_type_label({:tool_call, _}), do: "TOOL>"
  defp event_type_label({:tool_result, _}), do: "TOOL<"
  defp event_type_label({:tool_exec, %{phase: :start}}), do: "EXEC>"
  defp event_type_label({:tool_exec, %{phase: :stop}}), do: "EXEC<"
  defp event_type_label({:memory_search, _}), do: "MEM?"
  defp event_type_label({:memory_write, _}), do: "MEM+"
  defp event_type_label({:memory_ingest, _}), do: "INGEST"
  defp event_type_label({:memory_evict, _}), do: "EVICT"
  defp event_type_label({:memory_retrieval, _}), do: "RECALL"
  defp event_type_label({:mcp, _}), do: "MCP"
  defp event_type_label({:session, %{phase: :start}}), do: "SESS>"
  defp event_type_label({:session, %{phase: :stop}}), do: "SESS<"
  defp event_type_label({:session, %{phase: :error}}), do: "SESS!"
  defp event_type_label({:session, %{phase: :resume}}), do: "RESM"
  defp event_type_label({:llm_call, %{phase: :start}}), do: "LLM>"
  defp event_type_label({:llm_call, %{phase: :stop}}), do: "LLM<"
  defp event_type_label({:route_resolve, _}), do: "ROUTE"
  defp event_type_label({:auto_selected, _}), do: "AUTO"
  defp event_type_label({:model_analysis, _}), do: "ANLYZ"
  defp event_type_label({:model_scoring, _}), do: "SCORE"
  defp event_type_label({:pipeline, %{phase: :start}}), do: "PIPE>"
  defp event_type_label({:pipeline, %{phase: :stop}}), do: "PIPE<"
  defp event_type_label({:context_compact, _}), do: "CMPCT"
  defp event_type_label({:cost_limit, _}), do: "COST!"
  defp event_type_label({:circuit_breaker, %{phase: :trip}}), do: "TRIP!"
  defp event_type_label({:circuit_breaker, _}), do: "RECVR"
  defp event_type_label({:route_fallback, _}), do: "FALLBK"
  defp event_type_label({:phase_transition, _}), do: "PHASE"
  defp event_type_label({:mode_route, _}), do: "MROUTE"
  defp event_type_label({:commitment, _}), do: "COMMIT"
  defp event_type_label({:orch_turn, _}), do: "ORCH"
  defp event_type_label({:plan, %{phase: :created}}), do: "PLAN+"
  defp event_type_label({:plan, %{phase: :step_done}}), do: "STEP✓"
  defp event_type_label({:plan, %{phase: :all_done}}), do: "PLAN✓"
  defp event_type_label({:subagent, %{phase: :spawn}}), do: "SUB>"
  defp event_type_label({:subagent, %{phase: :complete}}), do: "SUB<"
  defp event_type_label({:subagent, %{phase: :error}}), do: "SUB!"
  defp event_type_label({:gateway_request, %{phase: :start}}), do: "GWAY>"
  defp event_type_label({:gateway_request, %{phase: :stop}}), do: "GWAY<"
  defp event_type_label(_), do: "???"

  # ── Type CSS classes ────────────────────────────────────────────

  defp event_type_class({:model_selection, _}), do: "color(:info) font-bold"
  defp event_type_class({:tool_call, _}), do: "color(:warning) font-semibold"
  defp event_type_class({:tool_result, %{status: :failed}}), do: "color(:error) font-semibold"
  defp event_type_class({:tool_result, _}), do: "color(:success) font-semibold"
  defp event_type_class({:tool_exec, %{phase: :stop, success: false}}), do: "color(:error) font-semibold"
  defp event_type_class({:tool_exec, %{phase: :stop}}), do: "color(:success) font-semibold"
  defp event_type_class({:tool_exec, _}), do: "color(:warning) font-semibold"
  defp event_type_class({:memory_search, _}), do: "color(:secondary) font-semibold"
  defp event_type_class({:memory_write, _}), do: "color(:primary) font-semibold"
  defp event_type_class({:memory_ingest, _}), do: "color(:primary) font-semibold"
  defp event_type_class({:memory_evict, _}), do: "color(:warning) font-semibold"
  defp event_type_class({:memory_retrieval, _}), do: "color(:secondary) font-semibold"
  defp event_type_class({:mcp, _}), do: "color(:info) font-semibold"
  defp event_type_class({:session, %{phase: :error}}), do: "color(:error) font-bold"
  defp event_type_class({:session, _}), do: "color(:accent) font-bold"
  defp event_type_class({:llm_call, %{phase: :stop}}), do: "color(:success) font-semibold"
  defp event_type_class({:llm_call, _}), do: "color(:info) font-semibold"
  defp event_type_class({:route_resolve, _}), do: "color(:info) font-semibold"
  defp event_type_class({:auto_selected, _}), do: "color(:info) font-bold"
  defp event_type_class({:model_analysis, _}), do: "color(:info) font-semibold"
  defp event_type_class({:model_scoring, _}), do: "color(:info) font-semibold"
  defp event_type_class({:pipeline, _}), do: "color(:text_muted) font-semibold"
  defp event_type_class({:context_compact, _}), do: "color(:warning) font-semibold"
  defp event_type_class({:cost_limit, _}), do: "color(:error) font-bold"
  defp event_type_class({:circuit_breaker, %{phase: :trip}}), do: "color(:error) font-bold"
  defp event_type_class({:circuit_breaker, _}), do: "color(:success) font-semibold"
  defp event_type_class({:route_fallback, _}), do: "color(:warning) font-semibold"
  defp event_type_class({:phase_transition, _}), do: "color(:accent) font-semibold"
  defp event_type_class({:mode_route, _}), do: "color(:accent) font-semibold"
  defp event_type_class({:commitment, _}), do: "color(:info) font-semibold"
  defp event_type_class({:orch_turn, _}), do: "color(:accent) font-semibold"
  defp event_type_class({:plan, _}), do: "color(:success) font-semibold"
  defp event_type_class({:subagent, %{phase: :error}}), do: "color(:error) font-bold"
  defp event_type_class({:subagent, _}), do: "color(:info) font-semibold"
  defp event_type_class({:gateway_request, %{phase: :start}}), do: "color(:info) font-semibold"
  defp event_type_class({:gateway_request, %{phase: :stop}}), do: "color(:success) font-semibold"
  defp event_type_class(_), do: "color(:text_dim)"

  # ── Summaries ───────────────────────────────────────────────────

  defp event_summary({:model_selection, info}) do
    pref = Map.get(info, :preference, "?")
    filter = Map.get(info, :filter, "none")
    complexity = Map.get(info, :complexity, "?")
    selected = get_in(info, [:selected, :model_id]) || "?"
    "selected=#{selected} complexity=#{complexity} pref=#{pref} filter=#{filter}"
  end

  defp event_summary({:tool_call, %{name: name}}), do: "calling #{name}"
  defp event_summary({:tool_result, %{name: name, status: status}}), do: "#{name} → #{status}"

  defp event_summary({:tool_exec, %{phase: :start, tool_name: name}}), do: name
  defp event_summary({:tool_exec, %{phase: :stop, tool_name: name} = info}) do
    dur = format_duration(info[:duration_ms])
    status = if info[:success] == false, do: "FAILED", else: "ok"
    bytes = if info[:output_bytes], do: " #{format_bytes(info[:output_bytes])}", else: ""
    "#{name} #{dur} #{status}#{bytes}"
  end

  defp event_summary({:memory_search, %{query: query, result_count: count}}),
    do: "query=\"#{truncate_str(query, 60)}\" → #{count} results"

  defp event_summary({:memory_write, %{type: type, content: content}}),
    do: "write #{type}: \"#{truncate_str(content, 60)}\""

  defp event_summary({:memory_ingest, %{fact_count: n}}), do: "#{n} facts ingested"
  defp event_summary({:memory_evict, info}), do: "evicted #{info[:evicted_count]}, #{info[:remaining_count]} remaining"
  defp event_summary({:memory_retrieval, info}) do
    dur = format_duration(info[:duration_ms])
    chars = info[:context_chars] || 0
    hit = if info[:cache_hit], do: " (cached)", else: ""
    inc = if info[:incremental], do: " incremental", else: ""
    "#{dur} #{chars} chars#{hit}#{inc}"
  end

  defp event_summary({:session, %{phase: :start, mode: mode, profile: profile}}) do
    "mode=#{mode || "?"} profile=#{profile || "default"}"
  end

  defp event_summary({:session, %{phase: :stop} = info}) do
    dur = format_duration(info[:duration_ms])
    cost = format_cost(info[:cost_usd])
    "#{dur} cost=#{cost} steps=#{info[:steps] || "?"}"
  end

  defp event_summary({:session, %{phase: :error, error: err}}), do: truncate_str(to_string(err), 80)
  defp event_summary({:session, %{phase: :resume, turns_restored: n}}), do: "restored #{n} turns"

  defp event_summary({:llm_call, %{phase: :start} = info}) do
    "tier=#{info[:model_tier] || "?"} mode=#{info[:selection_mode] || "?"}"
  end

  defp event_summary({:llm_call, %{phase: :stop} = info}) do
    dur = format_duration(info[:duration_ms])
    model = info[:model] || "?"
    provider = info[:provider] || "?"
    tokens_in = info[:input_tokens] || 0
    tokens_out = info[:output_tokens] || 0
    cost = format_cost(info[:cost_usd])
    "#{provider}/#{model} #{dur} in=#{tokens_in} out=#{tokens_out} cost=#{cost}"
  end

  defp event_summary({:route_resolve, info}) do
    dur = format_duration(info[:duration_ms])
    "#{info[:selection_mode]} → #{info[:provider]}/#{info[:model] || "?"} routes=#{info[:route_count] || "?"} #{dur}"
  end

  defp event_summary({:auto_selected, info}) do
    "#{info[:provider]}/#{info[:model]} complexity=#{info[:complexity]} pref=#{info[:preference]}"
  end

  defp event_summary({:model_analysis, info}) do
    dur = format_duration(info[:duration_ms])
    "#{info[:method]} → complexity=#{info[:complexity]} #{dur}"
  end

  defp event_summary({:model_scoring, info}) do
    dur = format_duration(info[:duration_ms])
    "#{info[:provider]}/#{info[:model]} score=#{info[:best_score]} candidates=#{info[:candidate_count]} #{dur}"
  end

  defp event_summary({:pipeline, %{phase: :start, stage: stage}}), do: "#{stage}"
  defp event_summary({:pipeline, %{phase: :stop, stage: stage} = info}) do
    "#{stage} #{format_duration(info[:duration_ms])}"
  end

  defp event_summary({:context_compact, info}) do
    "#{info[:messages_before]} → #{info[:messages_after]} messages (#{info[:pct_before]}% → #{info[:pct_after]}%)"
  end

  defp event_summary({:cost_limit, info}) do
    "#{format_cost(info[:cost_usd])} / #{format_cost(info[:limit_usd])} limit reached"
  end

  defp event_summary({:circuit_breaker, %{phase: :trip, tool_name: name, failure_count: n}}) do
    "#{name} tripped after #{n} failures"
  end

  defp event_summary({:circuit_breaker, %{phase: :recover, tool_name: name}}), do: "#{name} recovered"
  defp event_summary({:route_fallback, %{reason: reason}}), do: "#{reason}"

  defp event_summary({:phase_transition, info}), do: "#{info[:from]} → #{info[:to]} (#{info[:mode]})"
  defp event_summary({:mode_route, info}) do
    "#{info[:mode]}/#{info[:phase]} stop=#{info[:stop_reason]} → #{info[:action]}"
  end

  defp event_summary({:commitment, %{continuations: n}}), do: "#{n} continuations detected"

  defp event_summary({:orch_turn, info}) do
    "#{info[:strategy]} #{info[:mode]}/#{info[:phase]} stop=#{info[:stop_reason]}"
  end

  defp event_summary({:plan, %{phase: :created, step_count: n}}), do: "created with #{n} steps"
  defp event_summary({:plan, %{phase: :step_done, step_index: i, total_steps: t}}), do: "step #{i + 1}/#{t}"
  defp event_summary({:plan, %{phase: :all_done, total_steps: t}}), do: "all #{t} steps complete"

  defp event_summary({:subagent, %{phase: :spawn} = info}) do
    "depth=#{info[:depth]} parent=#{info[:parent]}"
  end

  defp event_summary({:subagent, %{phase: :complete} = info}) do
    dur = format_duration(info[:duration_ms])
    "#{dur} cost=#{format_cost(info[:cost_usd])} steps=#{info[:steps]}"
  end

  defp event_summary({:subagent, %{phase: :error} = info}) do
    "#{format_duration(info[:duration_ms])} #{truncate_str(to_string(info[:error]), 60)}"
  end

  defp event_summary({:gateway_request, %{phase: :start} = info}) do
    provider = info[:provider] || "?"
    model = info[:model] || "?"
    stream_tag = if info[:stream], do: " [stream]", else: ""
    "#{provider}/#{model}#{stream_tag}"
  end

  defp event_summary({:gateway_request, %{phase: :stop} = info}) do
    provider = info[:provider] || "?"
    status = info[:status] || "?"
    dur = format_duration(info[:duration_ms])
    tokens_in = info[:input_tokens] || 0
    tokens_out = info[:output_tokens] || 0
    stream_tag = if info[:stream], do: " stream", else: ""
    "#{provider} status=#{status}#{stream_tag} #{dur} in=#{tokens_in} out=#{tokens_out}"
  end

  defp event_summary({:mcp, {:mcp_failed, name}}), do: "#{name} failed"
  defp event_summary({:mcp, {:mcp_reconnected, name}}), do: "#{name} reconnected"
  defp event_summary({:mcp, {:mcp_reconnect_failed, name}}), do: "#{name} reconnect failed"
  defp event_summary(_), do: ""

  # ── Detail (expandable) ────────────────────────────────────────

  defp event_detail({:model_selection, info}) do
    candidates = Map.get(info, :candidates, [])
    explanation = Map.get(info, :explanation, "")

    needs = collect_needs(info)
    parts = []
    parts = if explanation != "", do: ["Analysis: #{explanation}" | parts], else: parts
    parts = if needs != [], do: ["Needs: #{Enum.join(needs, ", ")}" | parts], else: parts

    parts =
      if candidates != [] do
        candidate_lines =
          Enum.map_join(candidates, "\n", fn c ->
            free_tag = if c[:free], do: " [FREE]", else: ""
            "  #{c[:score]}  #{c[:provider]}/#{c[:model_id]}#{free_tag}"
          end)

        ["Ranked candidates:\n#{candidate_lines}" | parts]
      else
        parts
      end

    join_parts(parts)
  end

  defp event_detail({:tool_call, %{input: input}}) when input != nil and input != %{} do
    "Input: #{format_input(input)}"
  end

  defp event_detail({:tool_result, %{output: output}}) when is_binary(output) and byte_size(output) > 0 do
    truncated = if String.length(output) > 500, do: String.slice(output, 0, 500) <> "\n... (truncated)", else: output
    "Output: #{truncated}"
  end

  defp event_detail({:tool_result, %{output: output}}) when output != nil do
    "Output: #{inspect(output, limit: 500)}"
  end

  defp event_detail({:llm_call, %{phase: :stop} = info}) do
    parts = []
    parts = if (info[:cache_read] || 0) > 0, do: ["Cache read: #{info[:cache_read]} tokens" | parts], else: parts
    parts = if (info[:cache_write] || 0) > 0, do: ["Cache write: #{info[:cache_write]} tokens" | parts], else: parts
    join_parts(parts)
  end

  defp event_detail({:route_resolve, %{error: err}}) when err != nil, do: "Error: #{inspect(err)}"

  defp event_detail({:route_resolve, info}) do
    parts = []
    parts = if info[:complexity], do: ["Complexity: #{info[:complexity]}" | parts], else: parts
    parts = if info[:preference], do: ["Preference: #{info[:preference]}" | parts], else: parts
    join_parts(parts)
  end

  defp event_detail({:auto_selected, info}) do
    needs = collect_needs(info)
    parts = []
    parts = if needs != [], do: ["Needs: #{Enum.join(needs, ", ")}" | parts], else: parts
    parts = if info[:estimated_input_tokens], do: ["Est. input tokens: #{info[:estimated_input_tokens]}" | parts], else: parts
    join_parts(parts)
  end

  defp event_detail({:model_analysis, info}) do
    needs = collect_needs(info)
    parts = []
    parts = if needs != [], do: ["Needs: #{Enum.join(needs, ", ")}" | parts], else: parts
    parts = if info[:estimated_input_tokens], do: ["Est. input tokens: #{info[:estimated_input_tokens]}" | parts], else: parts
    join_parts(parts)
  end

  defp event_detail({:model_scoring, %{top3: top3}}) when is_list(top3) and top3 != [] do
    lines = Enum.map_join(top3, "\n", fn t ->
      "  #{t[:score]}  #{t[:provider]}/#{t[:model_id]} #{t[:label]}"
    end)
    "Top candidates:\n#{lines}"
  end

  defp event_detail({:session, %{phase: :error, error: err}}), do: "Error: #{err}"

  defp event_detail({:gateway_request, %{phase: :start} = info}) do
    parts = []
    parts = if info[:system_preview], do: ["System: #{info[:system_preview]}" | parts], else: parts

    parts =
      if info[:tools] && info[:tools] != [] do
        ["Tools: #{Enum.join(info[:tools], ", ")}" | parts]
      else
        parts
      end

    parts =
      if info[:messages] && info[:messages] != [] do
        msg_lines = Enum.map_join(info[:messages], "\n", fn m -> "  #{m[:role]}: #{m[:preview]}" end)
        ["Messages:\n#{msg_lines}" | parts]
      else
        parts
      end

    join_parts(parts)
  end

  defp event_detail({:gateway_request, %{phase: :stop} = info}) do
    parts = []
    parts = if info[:ttft_ms], do: ["TTFT: #{info[:ttft_ms]}ms" | parts], else: parts
    parts = if info[:chunk_count], do: ["Chunks: #{info[:chunk_count]}" | parts], else: parts
    parts = if info[:cache_read] && info[:cache_read] > 0, do: ["Cache read: #{info[:cache_read]}" | parts], else: parts
    parts = if info[:cache_write] && info[:cache_write] > 0, do: ["Cache write: #{info[:cache_write]}" | parts], else: parts

    parts =
      case info[:raw_response] do
        nil -> parts
        raw -> ["Response: #{truncate_str(to_string(raw), 400)}" | parts]
      end

    join_parts(parts)
  end

  defp event_detail(_), do: nil

  # ── Helpers ─────────────────────────────────────────────────────

  defp event_time({_type, %{timestamp: ts}}) when is_integer(ts) do
    ts
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%H:%M:%S")
  end

  defp event_time(_), do: "??"

  defp format_input(input) when is_map(input) do
    inspected = inspect(input, limit: 300)
    if String.length(inspected) > 500, do: String.slice(inspected, 0, 500) <> "...", else: inspected
  end

  defp format_input(input), do: inspect(input, limit: 300)

  defp format_duration(nil), do: "?ms"
  defp format_duration(ms) when ms >= 1000, do: "#{Float.round(ms / 1000, 1)}s"
  defp format_duration(ms), do: "#{ms}ms"

  defp format_cost(nil), do: "?"
  defp format_cost(cost) when is_number(cost) and cost < 0.001, do: "$0"
  defp format_cost(cost) when is_number(cost), do: "$#{Float.round(cost * 1.0, 4)}"
  defp format_cost(_), do: "?"

  defp format_bytes(nil), do: ""
  defp format_bytes(b) when b >= 1024, do: "#{Float.round(b / 1024, 1)}KB"
  defp format_bytes(b), do: "#{b}B"

  defp truncate_str(str, max) when is_binary(str) do
    if String.length(str) > max, do: String.slice(str, 0, max) <> "...", else: str
  end

  defp truncate_str(_, _), do: ""

  defp collect_needs(info) do
    needs = []
    needs = if info[:needs_vision], do: ["vision" | needs], else: needs
    needs = if info[:needs_audio], do: ["audio" | needs], else: needs
    needs = if info[:needs_reasoning], do: ["reasoning" | needs], else: needs
    needs = if info[:needs_large_context], do: ["large_context" | needs], else: needs
    Enum.reverse(needs)
  end

  defp join_parts([]), do: nil
  defp join_parts(parts), do: parts |> Enum.reverse() |> Enum.join("\n")
end
