defmodule Worth.Orchestration.Experiment do
  @moduledoc """
  Ecto schema for orchestration experiments.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "orchestration_experiments" do
    field(:name, :string)
    field(:description, :string)
    field(:strategies, {:array, :string})
    field(:prompts, {:array, :string})
    field(:repetitions, :integer, default: 1)
    field(:base_opts, :map)
    field(:results, {:array, :map})
    field(:comparison, :map)
    field(:status, :string, default: "pending")

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(experiment, attrs) do
    experiment
    |> cast(attrs, [
      :name,
      :description,
      :strategies,
      :prompts,
      :repetitions,
      :base_opts,
      :results,
      :comparison,
      :status
    ])
    |> validate_required([:name, :strategies, :prompts])
    |> validate_length(:strategies, min: 1)
    |> validate_length(:prompts, min: 1)
    |> validate_number(:repetitions, greater_than: 0)
  end
end
