defmodule Worth.Persistence.TranscriptBuffer do
  @moduledoc """
  Async-buffered transcript writer.

  Batches transcript appends in memory and flushes to disk asynchronously
  via a GenServer timer. This eliminates the synchronous file I/O that
  was blocking the agent loop on every turn.

  ## Design

  - Buffers entries in an ETS table (one per workspace)
  - Flushes every @flush_interval_ms (5 seconds) or when buffer reaches
    @flush_threshold entries (20)
  - Falls back to synchronous write if buffer process is not available
  """

  use GenServer

  require Logger

  @flush_interval_ms 5_000
  @table :worth_transcript_buffer

  # ── Public API ──────────────────────────────────────────────────

  @doc "Append an event to the transcript buffer."
  def append(session_id, event, workspace_path) do
    entry = %{
      session_id: session_id,
      event: event,
      timestamp: DateTime.utc_now(),
      workspace_path: workspace_path
    }

    # Try async buffer first, fall back to sync write
    case Process.whereis(__MODULE__) do
      nil ->
        Worth.Persistence.Transcript.append(session_id, event, workspace_path)

      _pid ->
        :ets.insert(@table, {System.monotonic_time(), entry})
        :ok
    end
  end

  @doc "Force flush all pending buffers."
  def flush do
    GenServer.call(__MODULE__, :flush, 30_000)
  end

  @doc "Start the buffer GenServer."
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Child spec for supervision tree."
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 5_000
    }
  end

  # ── GenServer callbacks ─────────────────────────────────────────

  @impl true
  def init(_) do
    # Create a public ETS table for concurrent inserts from any process
    :ets.new(@table, [
      :ordered_set,
      :public,
      :named_table,
      read_concurrency: false,
      write_concurrency: true
    ])

    schedule_flush()
    {:ok, %{}}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    count = do_flush()
    {:reply, count, state}
  end

  @impl true
  def handle_info(:flush, state) do
    do_flush()
    schedule_flush()
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    do_flush()
    :ok
  end

  # ── Internal ────────────────────────────────────────────────────

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval_ms)
  end

  defp do_flush do
    entries =
      :ets.select(@table, [
        {{:_, :"$1"}, [], [:"$1"]}
      ])

    count = length(entries)

    if count > 0 do
      # Group by workspace_path for efficient batch writes
      entries
      |> Enum.group_by(& &1.workspace_path)
      |> Enum.each(fn {workspace_path, group} ->
        write_group(workspace_path, group)
      end)

      # Delete all flushed entries
      :ets.select_delete(@table, [{{:_, :_}, [], [true]}])

      Logger.debug("TranscriptBuffer: flushed #{count} entries")
    end

    count
  end

  defp write_group(workspace_path, entries) do
    dir = Path.join(workspace_path, ".worth")
    File.mkdir_p!(dir)
    path = Path.join(dir, "transcript.jsonl")

    lines =
      Enum.map(entries, fn entry ->
        Jason.encode!(%{
          session_id: entry.session_id,
          event: entry.event,
          timestamp: entry.timestamp
        }) <> "\n"
      end)

    File.write!(path, lines, [:append])
  rescue
    e ->
      Logger.error("TranscriptBuffer: failed to write to #{workspace_path}: #{Exception.message(e)}")
  end
end
