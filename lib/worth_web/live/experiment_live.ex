defmodule WorthWeb.ExperimentLive do
  @moduledoc """
  LiveView for orchestration experiment dashboard.
  """

  use WorthWeb, :live_view

  import WorthWeb.ThemeHelper, only: [color: 1]

  alias Worth.Orchestration.ExperimentService

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Worth.PubSub, "experiments")
      send(self(), :load_experiments)
    end

    {:ok,
     socket
     |> assign(:experiments, [])
     |> assign(:comparison, nil)
     |> assign(:selected_experiment, nil)
     |> assign(:form, %{name: "", description: "", strategies: "default,stigmergy", prompts: "", repetitions: 1})}
  end

  @impl true
  def handle_event("load", _params, socket) do
    {:noreply, assign(socket, :experiments, ExperimentService.list())}
  end

  @impl true
  def handle_event("create", %{"experiment" => params}, socket) do
    strategies =
      params["strategies"]
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    prompts =
      params["prompts"]
      |> String.split("\n", trim: true)

    repetitions = String.to_integer(params["repetitions"] || "1")

    attrs = %{
      name: params["name"],
      description: params["description"],
      strategies: strategies,
      prompts: prompts,
      repetitions: repetitions
    }

    case ExperimentService.create(attrs) do
      {:ok, experiment} ->
        {:noreply,
         socket
         |> put_flash(:info, "Experiment '#{experiment.name}' created")
         |> assign(:experiments, ExperimentService.list())}

      {:error, changeset} ->
        errors = Enum.map_join(changeset.errors, ", ", fn {f, {m, _}} -> "#{f}: #{m}" end)
        {:noreply, put_flash(socket, :error, errors)}
    end
  end

  @impl true
  def handle_event("run", %{"id" => id}, socket) do
    case ExperimentService.run_experiment(id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Experiment started")
         |> assign(:experiments, ExperimentService.list())}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, inspect(reason))}
    end
  end

  @impl true
  def handle_event("select", %{"id" => id}, socket) do
    experiment = ExperimentService.get!(id)
    comparison = experiment.comparison || []
    results = experiment.results || []

    {:noreply,
     assign(socket,
       selected_experiment: experiment,
       comparison: comparison,
       results: results
     )}
  end

  @impl true
  def handle_info(:load_experiments, socket) do
    {:noreply, assign(socket, :experiments, ExperimentService.list())}
  end

  @impl true
  def handle_info({:experiment_complete, id}, socket) do
    experiments = ExperimentService.list()

    socket =
      if socket.assigns.selected_experiment && socket.assigns.selected_experiment.id == id do
        experiment = ExperimentService.get!(id)

        assign(socket,
          selected_experiment: experiment,
          comparison: experiment.comparison || [],
          results: experiment.results || [],
          experiments: experiments
        )
      else
        assign(socket, :experiments, experiments)
      end

    {:noreply, socket}
  end

  defp status_class("complete"), do: color(:success)
  defp status_class("running"), do: color(:warning)
  defp status_class("pending"), do: "#{color(:surface_elevated)} #{color(:text_muted)}"
  defp status_class("error"), do: color(:error)
  defp status_class(_), do: "#{color(:surface_elevated)} #{color(:text_muted)}"
end
