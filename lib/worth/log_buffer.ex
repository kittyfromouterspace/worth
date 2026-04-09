defmodule Worth.LogBuffer do
  @moduledoc """
  Bounded ring buffer of recent log events.
  Entries are simple maps: `%{level: atom, text: binary, ts: integer}`.
  """

  use GenServer

  @max_entries 500

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def push(entry) do
    GenServer.cast(__MODULE__, {:push, entry})
  end

  def recent(n \\ 100) do
    GenServer.call(__MODULE__, {:recent, n})
  end

  def count do
    GenServer.call(__MODULE__, :count)
  end

  def clear do
    GenServer.cast(__MODULE__, :clear)
  end

  @impl true
  def init(_opts) do
    {:ok, %{queue: :queue.new(), count: 0}}
  end

  @impl true
  def handle_cast({:push, entry}, state) do
    queue = :queue.in(entry, state.queue)

    {queue, count} =
      if state.count >= @max_entries do
        {_, q} = :queue.out(queue)
        {q, @max_entries}
      else
        {queue, state.count + 1}
      end

    {:noreply, %{state | queue: queue, count: count}}
  end

  def handle_cast(:clear, _state) do
    {:noreply, %{queue: :queue.new(), count: 0}}
  end

  @impl true
  def handle_call({:recent, n}, _from, state) do
    list = :queue.to_list(state.queue)
    take = if n >= length(list), do: list, else: Enum.slice(list, -n, n)
    {:reply, take, state}
  end

  def handle_call(:count, _from, state), do: {:reply, state.count, state}
end
