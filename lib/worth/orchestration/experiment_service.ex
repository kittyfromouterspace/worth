defmodule Worth.Orchestration.ExperimentService do
  @moduledoc """
  Service for creating, running, and querying orchestration experiments.
  """

  import Ecto.Query

  alias Worth.Orchestration.Experiment
  alias Worth.Repo

  def list do
    Repo.all(Experiment)
    |> Enum.sort_by(& &1.inserted_at, {:desc, NaiveDateTime})
  end

  def get!(id), do: Repo.get!(Experiment, id)

  def create(attrs) do
    %Experiment{}
    |> Experiment.changeset(attrs)
    |> Repo.insert()
  end

  def run_experiment(id) do
    experiment = get!(id)

    experiment =
      Repo.update!(Experiment.changeset(experiment, %{status: "running"}))

    Task.Supervisor.start_child(Worth.TaskSupervisor, fn ->
      agent_experiment = build_agent_experiment(experiment)

      result = AgentEx.Strategy.Experiment.run(agent_experiment)
      comparison = AgentEx.Strategy.Experiment.compare(result)

      Repo.update!(Experiment.changeset(experiment, %{
        status: "complete",
        results: serialize_results(result.results),
        comparison: comparison
      }))

      Phoenix.PubSub.broadcast(
        Worth.PubSub,
        "experiments",
        {:experiment_complete, experiment.id}
      )
    end)

    {:ok, experiment}
  end

  defp build_agent_experiment(experiment) do
    %AgentEx.Strategy.Experiment{
      id: experiment.id,
      name: experiment.name,
      description: experiment.description,
      strategies: Enum.map(experiment.strategies, &String.to_atom/1),
      prompts: experiment.prompts,
      repetitions: experiment.repetitions,
      base_opts: experiment.base_opts || [],
      results: nil,
      status: :pending
    }
  end

  defp serialize_results(results) when is_list(results) do
    Enum.map(results, fn r ->
      %{
        strategy: r.strategy,
        prompt: r.prompt,
        repetition: r.repetition,
        result: serialize_result(r.result),
        duration_ms: r.duration_ms
      }
    end)
  end

  defp serialize_results(_), do: nil

  defp serialize_result({:ok, map}), do: Map.put(map, :status, "ok")
  defp serialize_result({:error, reason}), do: %{status: "error", reason: inspect(reason)}
end
