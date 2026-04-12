defmodule Worth.Desktop.Bridge do
  @moduledoc """
  Desktop integration bridge.

  When WORTH_DESKTOP=1 is set, this GenServer starts and can be used
  for coordination between the Elixir app and the Tauri shell.
  Currently the Tauri splash screen polls for HTTP readiness directly,
  so no TCP PubSub bridge is needed.
  """

  use GenServer

  require Logger

  def start_link(opts \\ []) do
    if desktop_mode?() do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    else
      :ignore
    end
  end

  def broadcast_ready(url) do
    if desktop_mode?() and Process.whereis(__MODULE__) do
      Logger.info("Desktop.Bridge: app ready at #{url}")
    end
  end

  def broadcast_shutdown do
    if desktop_mode?() and Process.whereis(__MODULE__) do
      Logger.info("Desktop.Bridge: shutting down")
    end
  end

  @impl true
  def init(_opts) do
    Logger.info("Desktop.Bridge: started in desktop mode")
    {:ok, %{}}
  end

  defp desktop_mode?, do: System.get_env("WORTH_DESKTOP") == "1"
end
