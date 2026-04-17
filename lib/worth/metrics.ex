defmodule Worth.Metrics do
  @moduledoc """
  Per-session aggregator that listens to `[:agentic, :llm_call, :stop]`
  and `[:agentic, :llm, :embed, :stop]` telemetry events and tracks
  cost / token / call counts for the current worth session.

  Resets on `/clear` and on workspace switch via `Worth.Brain` calling
  `reset/0`.

  ## Public API

      Worth.Metrics.session()                 # current snapshot
      Worth.Metrics.session_cost()            # total USD
      Worth.Metrics.reset()                   # zero everything
      Worth.Metrics.by_provider()             # %{openrouter: %{cost:, calls:, ...}}
  """

  use GenServer

  require Logger

  @handler_id "worth-metrics-handler"

  defstruct cost: 0.0,
            calls: 0,
            input_tokens: 0,
            output_tokens: 0,
            cache_read: 0,
            cache_write: 0,
            embed_calls: 0,
            embed_cost: 0.0,
            by_provider: %{},
            started_at: nil

  @type t :: %__MODULE__{}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Return the current session's metrics snapshot."
  def session do
    GenServer.call(__MODULE__, :session)
  catch
    :exit, _ -> %__MODULE__{}
  end

  @doc "Return just the total session cost in USD."
  def session_cost do
    session().cost
  end

  @doc "Return the per-provider breakdown."
  def by_provider do
    session().by_provider
  end

  @doc "Reset all counters. Called from `/clear` and on workspace switch."
  def reset do
    GenServer.call(__MODULE__, :reset)
  catch
    :exit, _ -> :ok
  end

  # ----- GenServer callbacks -----

  @impl true
  def init(_opts) do
    :telemetry.attach_many(
      @handler_id,
      [
        [:agentic, :llm_call, :stop],
        [:agentic, :llm, :embed, :stop]
      ],
      &__MODULE__.handle_event/4,
      nil
    )

    {:ok, %__MODULE__{started_at: System.system_time(:millisecond)}}
  end

  @impl true
  def handle_call(:session, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:reset, _from, _state) do
    {:reply, :ok, %__MODULE__{started_at: System.system_time(:millisecond)}}
  end

  @impl true
  def handle_cast({:llm_call, measurements, metadata}, state) do
    provider = metadata[:provider] || "unknown"

    by_provider =
      Map.update(
        state.by_provider,
        provider,
        provider_init(measurements),
        fn p ->
          %{
            cost: p.cost + (measurements[:cost_usd] || 0.0),
            calls: p.calls + 1,
            input_tokens: p.input_tokens + (measurements[:input_tokens] || 0),
            output_tokens: p.output_tokens + (measurements[:output_tokens] || 0)
          }
        end
      )

    state = %{
      state
      | cost: state.cost + (measurements[:cost_usd] || 0.0),
        calls: state.calls + 1,
        input_tokens: state.input_tokens + (measurements[:input_tokens] || 0),
        output_tokens: state.output_tokens + (measurements[:output_tokens] || 0),
        cache_read: state.cache_read + (measurements[:cache_read] || 0),
        cache_write: state.cache_write + (measurements[:cache_write] || 0),
        by_provider: by_provider
    }

    {:noreply, state}
  end

  def handle_cast({:embed, measurements, _metadata}, state) do
    state = %{
      state
      | embed_calls: state.embed_calls + 1,
        embed_cost: state.embed_cost + (measurements[:cost_usd] || 0.0)
    }

    {:noreply, state}
  end

  # ----- telemetry handler -----

  @doc false
  def handle_event([:agentic, :llm_call, :stop], measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:llm_call, measurements, metadata})
  end

  def handle_event([:agentic, :llm, :embed, :stop], measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:embed, measurements, metadata})
  end

  defp provider_init(measurements) do
    %{
      cost: measurements[:cost_usd] || 0.0,
      calls: 1,
      input_tokens: measurements[:input_tokens] || 0,
      output_tokens: measurements[:output_tokens] || 0
    }
  end
end
