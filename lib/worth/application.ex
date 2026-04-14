defmodule Worth.Application do
  @moduledoc false
  use Application

  alias Worth.Desktop.Bridge
  alias Worth.Mcp.Broker

  @impl true
  def start(_type, _args) do
    children = [
      Worth.Repo,
      Worth.Config,
      Worth.Vault,
      Worth.LogBuffer,
      {Phoenix.PubSub, name: Worth.PubSub},
      {Registry, keys: :unique, name: Worth.Registry},
      {Task.Supervisor, name: Worth.TaskSupervisor},
      Worth.Metrics,
      Worth.Agent.Tracker,
      Broker,
      Worth.Mcp.ConnectionMonitor,
      Worth.Brain.Supervisor,
      Worth.Learning.TelemetryBridge,
      {Task.Supervisor, name: Worth.SkillInit, max_retries: 0},
      WorthWeb.Telemetry,
      WorthWeb.Endpoint,
      Bridge
    ]

    case Supervisor.start_link(children, strategy: :one_for_one, name: Worth.Supervisor) do
      {:ok, pid} ->
        if System.get_env("WORTH_DESKTOP") == "1" do
          Worth.Boot.run_migrations!()
        end

        Task.Supervisor.start_child(Worth.SkillInit, fn ->
          Worth.Skill.Registry.init()
        end)

        Task.Supervisor.start_child(Worth.SkillInit, fn ->
          Broker.connect_auto()
        end)

        Task.Supervisor.start_child(Worth.SkillInit, fn ->
          Worth.Memory.Embeddings.StaleCheck.run()
        end)

        # AgentEx.LLM.Catalog runs its first refresh ~100ms after agent_ex
        # boots — that races Worth.Config.start_link/1, which is the only
        # thing that exports user-saved provider keys (e.g. OPENROUTER_API_KEY)
        # into the process env. The refresh wins the race, every provider
        # resolves as :no_creds, the static fallback is persisted to
        # ~/.worth/catalog.json, and the next scheduled refresh isn't for
        # 10 minutes. Force one more refresh now that Worth.Config is up.
        Task.Supervisor.start_child(Worth.SkillInit, fn ->
          Worth.CodingAgents.auto_register()
        end)

        Task.Supervisor.start_child(Worth.SkillInit, fn ->
          AgentEx.LLM.Catalog.refresh()
        end)

        Task.Supervisor.start_child(Worth.SkillInit, fn ->
          register_strategies()
        end)

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

  defp register_strategies do
    AgentEx.Strategy.Registry.register(Worth.Orchestration.Strategies.Stigmergy)
  end
end
