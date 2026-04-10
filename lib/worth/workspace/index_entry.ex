defmodule Worth.Workspace.IndexEntry do
  @moduledoc """
  Tracks which content from a workspace has been indexed into Mneme.

  Each record represents a file or data source that has been processed
  and stored in memory. The content_hash allows detecting changes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "workspace_index_entries" do
    field(:workspace_name, :string)
    field(:source_type, :string)
    field(:source_path, :string)
    field(:content_hash, :string)
    field(:file_size, :integer)
    field(:last_modified, :utc_datetime_usec)
    field(:mneme_entry_ids, {:array, :binary_id}, default: [])
    field(:indexed_at, :utc_datetime_usec)
    field(:status, :string, default: "indexed")

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Returns the changeset for an index entry.
  """
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :workspace_name,
      :source_type,
      :source_path,
      :content_hash,
      :file_size,
      :last_modified,
      :mneme_entry_ids,
      :indexed_at,
      :status
    ])
    |> validate_required([
      :workspace_name,
      :source_type,
      :source_path,
      :content_hash,
      :indexed_at
    ])
  end

  @doc """
  Calculates a content hash for a file or content.
  """
  def calculate_hash(content) when is_binary(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end

  def calculate_hash(nil), do: nil
end
