defmodule Worth.Application do
  @moduledoc false
  use Application

  alias Worth.Desktop.Bridge
  alias Worth.Mcp.Broker

  @impl true
  def start(_type, _args) do
    if System.get_env("WORTH_DESKTOP") == "1" do
      Worth.Boot.run_migrations_before_start!()
      :ets.new(:session, [:named_table, :public, read_concurrency: true])
    end

    children = [
      Worth.Repo,
      Worth.Config,
      Worth.Vault,
      Worth.LogBuffer,
      {Phoenix.PubSub, name: Worth.PubSub},
      {Registry, keys: :unique, name: Worth.Registry},
      {Task.Supervisor, name: Worth.TaskSupervisor},
      Worth.Metrics,
      Worth.Metrics.Repo,
      Worth.Metrics.Writer,
      Worth.Persistence.TranscriptBuffer,
      Worth.Agent.Tracker,
      Broker,
      Worth.Mcp.ConnectionMonitor,
      Worth.Brain.Supervisor,
      Worth.Learning.TelemetryBridge,
      Worth.XRay.TelemetryBridge,
      {Task.Supervisor, name: Worth.SkillInit, max_retries: 0},
      WorthWeb.Telemetry,
      WorthWeb.Endpoint,
      Bridge
    ]

    children =
      if desktop_mode?() do
        children ++
          [
            {Desktop.Window,
             [
               app: :worth,
               id: WorthWindow,
               title: "Worth",
               size: {1200, 800},
               min_size: {800, 600},
               icon: "icon.png",
               url: &WorthWeb.Endpoint.url/0
             ]}
          ]
      else
        children
      end

    case Supervisor.start_link(children, strategy: :one_for_one, name: Worth.Supervisor) do
      {:ok, pid} ->
        Agentic.Sandbox.Platform.log_status()

        _ = start_init_task(:skill_registry_init, &Worth.Skill.Registry.init/0)
        _ = start_init_task(:mcp_auto_connect, &Broker.connect_auto/0)
        _ = start_init_task(:embeddings_stale_check, &Worth.Memory.Embeddings.StaleCheck.run/0)
        _ = start_init_task(:coding_agents_register, &Worth.CodingAgents.auto_register/0)
        _ = start_init_task(:catalog_refresh, &Agentic.LLM.Catalog.refresh/0)
        _ = start_init_task(:strategy_registration, &register_strategies/0)

        {:ok, pid}

      error ->
        error
    end
  end

  @impl true
  def stop(_state) do
    Bridge.broadcast_shutdown()
    :ok
  end

  defp start_init_task(name, fun) do
    {:ok, _pid} =
      Task.Supervisor.start_child(Worth.SkillInit, fn ->
        try do
          fun.()
        rescue
          e ->
            require Logger

            Logger.error("[Application] Init task #{name} failed: #{inspect(e)}")
            reraise e, __STACKTRACE__
        catch
          kind, reason ->
            require Logger

            Logger.error("[Application] Init task #{name} crashed: #{kind} #{inspect(reason)}")
            :ok
        end
      end)
  end

  defp register_strategies do
    Agentic.Strategy.Registry.register(Worth.Orchestration.Strategies.Stigmergy)
  end

  defp desktop_mode?, do: System.get_env("WORTH_DESKTOP") == "1"
end