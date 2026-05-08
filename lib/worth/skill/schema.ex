defmodule Worth.Skill.Schema do
  @moduledoc """
  Ecto schema for skills stored in the database.

  Skills can be:
  - **core**: Bundled with Worth, read-only
  - **installed**: Added by user from a source (git, file, etc.)
  - **learned**: Created by the agent during sessions
  - **unverified**: From external sources, not yet trusted

  The `workspace` field scopes skills:
  - `"global"` or `"core"` → available everywhere
  - `"personal"` or specific workspace → scoped to that workspace
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Worth.Repo

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "skills" do
    field(:name, :string)
    field(:description, :string)
    field(:body, :string)
    field(:license, :string)
    field(:compatibility, :string)
    field(:metadata, :map, default: %{})
    field(:loading, :string, default: "on_demand")
    field(:model_tier, :string, default: "any")
    field(:provenance, :string, default: "human")
    field(:trust_level, :string, default: "installed")
    field(:allowed_tools, {:array, :string})
    field(:evolution, :map, default: %{})
    field(:workspace, :string, default: "global")
    field(:installed_at, :utc_datetime_usec)
    field(:source_path, :string)

    timestamps(type: :utc_datetime_usec)
  end

  @required_fields [:name, :body]
  @optional_fields [
    :description,
    :license,
    :compatibility,
    :metadata,
    :loading,
    :model_tier,
    :provenance,
    :trust_level,
    :allowed_tools,
    :evolution,
    :workspace,
    :installed_at,
    :source_path
  ]

  @doc false
  def changeset(skill, attrs) do
    skill
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1, max: 64)
    |> validate_format(:name, ~r/^[a-z0-9][a-z0-9-]{0,63}$/)
    |> validate_length(:description, max: 1024)
    |> validate_inclusion(:loading, ["always", "on_demand"])
    |> validate_inclusion(:model_tier, ["primary", "lightweight", "any"])
    |> validate_inclusion(:provenance, ["human", "agent", "hybrid"])
    |> validate_inclusion(:trust_level, ["core", "installed", "learned", "unverified"])
    |> unique_constraint([:name, :workspace])
  end

  # --- Query helpers ---

  @doc "List skills scoped to a workspace (including global)."
  def for_workspace(workspace) do
    import Ecto.Query

    Repo.all(
      from(s in __MODULE__,
        where: s.workspace == ^workspace or s.workspace in ["global", "core"],
        order_by: [asc: s.name]
      )
    )
  end

  @doc "List skills installed in a specific workspace."
  def installed_in_workspace(workspace) do
    import Ecto.Query

    Repo.all(from(s in __MODULE__, where: s.workspace == ^workspace, order_by: [asc: s.name]))
  end

  @doc "Find a skill by name, scoped to workspace (with global fallback)."
  def find(name, workspace) do
    import Ecto.Query

    query =
      from(s in __MODULE__,
        where: s.name == ^name,
        where: s.workspace == ^workspace or s.workspace in ["global", "core"],
        order_by: [asc: s.workspace],
        limit: 1
      )

    Repo.one(query)
  end

  @doc "Search skills by name or description."
  def search(query_string, workspace) do
    import Ecto.Query

    pattern = "%#{query_string}%"

    Repo.all(
      from(s in __MODULE__,
        where:
          (s.workspace == ^workspace or s.workspace in ["global", "core"]) and
            (ilike(s.name, ^pattern) or ilike(s.description, ^pattern)),
        order_by: [asc: s.name]
      )
    )
  end
end
