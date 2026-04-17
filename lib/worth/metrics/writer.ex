defmodule Worth.Metrics.Writer do
  @moduledoc """
  Telemetry handler that persists orchestration metrics to SQLite.

  Attaches to `[:agentic, :session, :start]`, `[:agentic, :session, :stop]`,
  `[:agentic, :orchestration, :turn]`, and `[:agentic, :orchestration, :tool_executed]`
  events and writes corresponding rows to the metrics tables.
  """

  use GenServer

  import Ecto.Query

  alias Worth.Metrics.Repo
  alias Worth.Metrics.Schema.SessionMetric
  alias Worth.Metrics.Schema.ToolCallMetric
  alias Worth.Metrics.Schema.TurnMetric

  require Logger

  @handler_id "worth-metrics-writer"

  @flush_interval 5_000
  @flush_threshold 20

  defstruct buffer: [], last_flush: 0

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    attach_handlers()
    Process.send_after(self(), :flush, @flush_interval)
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_info(:flush, state) do
    new_state = do_flush(state)
    Process.send_after(self(), :flush, @flush_interval)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:buffer, entry}, state) do
    new_buffer = [entry | state.buffer]

    state =
      if length(new_buffer) >= @flush_threshold do
        do_flush(%{state | buffer: new_buffer})
      else
        %{state | buffer: new_buffer}
      end

    {:noreply, state}
  end

  defp do_flush(%{buffer: []} = state), do: state

  defp do_flush(%{buffer: buffer} = state) do
    session_starts = Enum.filter(buffer, &match?({:session_start, _, _}, &1))
    session_stops = Enum.filter(buffer, &match?({:session_stop, _, _}, &1))
    turns = Enum.filter(buffer, &match?({:turn, _, _}, &1))
    tool_calls = Enum.filter(buffer, &match?({:tool_call, _, _}, &1))

    Enum.each(session_starts, &write_session_start/1)
    Enum.each(session_stops, &write_session_stop/1)
    Enum.each(turns, &write_turn/1)
    Enum.each(tool_calls, &write_tool_call/1)

    %{state | buffer: [], last_flush: System.monotonic_time(:millisecond)}
  end

  defp attach_handlers do
    :telemetry.attach(
      @handler_id <> "_session_start",
      [:agentic, :session, :start],
      &__MODULE__.handle_session_start/4,
      nil
    )

    :telemetry.attach(
      @handler_id <> "_session_stop",
      [:agentic, :session, :stop],
      &__MODULE__.handle_session_stop/4,
      nil
    )

    :telemetry.attach(
      @handler_id <> "_turn",
      [:agentic, :orchestration, :turn],
      &__MODULE__.handle_turn/4,
      nil
    )

    :telemetry.attach(
      @handler_id <> "_tool",
      [:agentic, :orchestration, :tool_executed],
      &__MODULE__.handle_tool_executed/4,
      nil
    )
  end

  @doc false
  def handle_session_start(_event, _measurements, metadata, _config) do
    GenServer.cast(
      __MODULE__,
      {:buffer,
       {:session_start, metadata[:session_id],
        %{
          strategy: to_string(metadata[:strategy] || "default"),
          mode: to_string(metadata[:mode] || "agentic"),
          workspace: to_string(metadata[:workspace] || "unknown"),
          started_at: DateTime.utc_now()
        }}}
    )
  end

  @doc false
  def handle_session_stop(_event, measurements, metadata, _config) do
    GenServer.cast(
      __MODULE__,
      {:buffer,
       {:session_stop, metadata[:session_id],
        %{
          completed_at: DateTime.utc_now(),
          status: "completed",
          total_cost_usd: measurements[:cost] || 0,
          total_tokens_in: measurements[:tokens_in] || 0,
          total_tokens_out: measurements[:tokens_out] || 0,
          total_turns: measurements[:steps] || 0,
          duration: measurements[:duration]
        }}}
    )
  end

  @doc false
  def handle_turn(_event, _measurements, metadata, _config) do
    GenServer.cast(
      __MODULE__,
      {:buffer,
       {:turn, metadata[:session_id],
        %{
          turn_number: System.unique_integer([:positive]),
          started_at: DateTime.utc_now(),
          stop_reason: to_string(metadata[:stop_reason] || ""),
          strategy: to_string(metadata[:strategy] || "default"),
          mode: to_string(metadata[:mode] || ""),
          phase: to_string(metadata[:phase] || "")
        }}}
    )
  end

  @doc false
  def handle_tool_executed(_event, measurements, metadata, _config) do
    GenServer.cast(
      __MODULE__,
      {:buffer,
       {:tool_call, metadata[:session_id],
        %{
          tool_name: metadata[:tool_name],
          called_at: DateTime.utc_now(),
          duration_ms: measurements[:duration],
          success: metadata[:success] != false,
          output_bytes: measurements[:output_bytes]
        }}}
    )
  end

  defp write_session_start({_type, session_id, data}) do
    %SessionMetric{}
    |> Ecto.Changeset.change(%{
      session_id: session_id,
      strategy: data.strategy,
      mode: data.mode,
      workspace: data.workspace,
      status: "running",
      started_at: data.started_at
    })
    |> Repo.insert(on_conflict: :nothing)
  rescue
    e -> Logger.warning("[Metrics.Writer] Failed to write session_start: #{inspect(e)}")
  end

  defp write_session_stop({_type, session_id, data}) do
    query =
      from(s in SessionMetric,
        where: s.session_id == ^session_id,
        order_by: [desc: s.inserted_at],
        limit: 1
      )

    case Repo.one(query) do
      nil ->
        :ok

      session ->
        session
        |> Ecto.Changeset.change(%{
          completed_at: data.completed_at,
          status: data.status,
          total_cost_usd: data.total_cost_usd,
          total_turns: data.total_turns
        })
        |> Repo.update()
    end
  rescue
    e -> Logger.warning("[Metrics.Writer] Failed to write session_stop: #{inspect(e)}")
  end

  defp write_turn({_type, session_id, data}) do
    %TurnMetric{}
    |> Ecto.Changeset.change(%{
      session_id: session_id,
      turn_number: data.turn_number,
      started_at: data.started_at,
      stop_reason: to_string(data.stop_reason),
      model_id: data[:model_id],
      phase: data[:phase]
    })
    |> Repo.insert()
  rescue
    e -> Logger.warning("[Metrics.Writer] Failed to write turn: #{inspect(e)}")
  end

  defp write_tool_call({_type, session_id, data}) do
    %ToolCallMetric{}
    |> Ecto.Changeset.change(%{
      session_id: session_id,
      turn_number: data[:turn_number] || 0,
      tool_name: data.tool_name,
      called_at: data.called_at,
      duration_ms: data.duration_ms,
      success: data.success,
      result_size_bytes: data.output_bytes
    })
    |> Repo.insert()
  rescue
    e -> Logger.warning("[Metrics.Writer] Failed to write tool_call: #{inspect(e)}")
  end
end
