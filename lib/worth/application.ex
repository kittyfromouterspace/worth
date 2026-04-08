defmodule Worth.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Worth.Repo,
      Worth.Config,
      Worth.UI.LogBuffer,
      {Phoenix.PubSub, name: Worth.PubSub},
      {Registry, keys: :unique, name: Worth.Registry},
      {Task.Supervisor, name: Worth.TaskSupervisor},
      Worth.Telemetry,
      Worth.Mcp.Broker,
      Worth.Mcp.ConnectionMonitor,
      Worth.Brain.Supervisor,
      {Task.Supervisor, name: Worth.SkillInit, max_retries: 0}
    ]

    case Supervisor.start_link(children, strategy: :one_for_one, name: Worth.Supervisor) do
      {:ok, pid} ->
        Task.Supervisor.start_child(Worth.SkillInit, fn ->
          Worth.Skill.Registry.init()
        end)

        Task.Supervisor.start_child(Worth.SkillInit, fn ->
          Worth.Mcp.Broker.connect_auto()
        end)

        {:ok, pid}

      error ->
        error
    end
  end

  @impl true
  def stop(_state) do
    :ok
  end
end
