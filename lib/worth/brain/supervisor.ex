defmodule Worth.Brain.Supervisor do
  @moduledoc """
  DynamicSupervisor that starts one Worth.Brain process per workspace.
  Brain processes are started on demand and registered via Worth.Registry.
  """
  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Ensure a Brain process is running for the given workspace.
  Returns the PID if one exists, or starts a new one.
  """
  def ensure_started(workspace, opts \\ []) do
    case Worth.Brain.whereis(workspace) do
      nil ->
        child_spec = {Worth.Brain, Keyword.put(opts, :workspace, workspace)}

        case DynamicSupervisor.start_child(__MODULE__, child_spec) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          error -> error
        end

      pid ->
        {:ok, pid}
    end
  end
end
