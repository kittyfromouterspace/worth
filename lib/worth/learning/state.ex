defmodule Worth.Learning.State do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Query

  alias Worth.Repo

  @primary_key {:id, :id, autogenerate: true}
  schema "worth_learning_state" do
    field(:workspace_name, :string)
    field(:key, :string)
    field(:value, :map, default: %{})

    timestamps(updated_at: :updated_at)
  end

  @type t :: %__MODULE__{}

  def load(workspace_name, key) when is_binary(workspace_name) and is_binary(key) do
    case Repo.get_by(__MODULE__, workspace_name: workspace_name, key: key) do
      nil -> nil
      state -> state.value
    end
  end

  def save(workspace_name, key, value) when is_binary(workspace_name) and is_binary(key) and is_map(value) do
    case Repo.get_by(__MODULE__, workspace_name: workspace_name, key: key) do
      nil ->
        Repo.insert(%__MODULE__{workspace_name: workspace_name, key: key, value: value})

      existing ->
        existing
        |> Ecto.Changeset.change(%{value: value})
        |> Repo.update()
    end
  end

  def delete(workspace_name, key) when is_binary(workspace_name) and is_binary(key) do
    Repo.delete_all(from(s in __MODULE__, where: s.workspace_name == ^workspace_name and s.key == ^key))
  end

  def load_all(workspace_name) when is_binary(workspace_name) do
    from(s in __MODULE__, where: s.workspace_name == ^workspace_name, select: {s.key, s.value})
    |> Repo.all()
    |> Map.new()
  end
end
