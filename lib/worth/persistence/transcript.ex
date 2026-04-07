defmodule Worth.Persistence.Transcript do
  @behaviour AgentEx.Persistence.Transcript

  @impl true
  def append(session_id, event, workspace_path) do
    dir = Path.join(workspace_path, ".worth")
    File.mkdir_p!(dir)

    path = Path.join(dir, "transcript.jsonl")
    line = Jason.encode!(%{session_id: session_id, event: event, timestamp: DateTime.utc_now()}) <> "\n"
    File.write!(path, line, [:append])
    :ok
  end

  @impl true
  def load(session_id, workspace_path) do
    path = Path.join(workspace_path, ".worth/transcript.jsonl")

    case File.read(path) do
      {:ok, content} ->
        entries =
          content
          |> String.split("\n", trim: true)
          |> Enum.map(&Jason.decode!/1)
          |> Enum.filter(&(&1["session_id"] == session_id))

        {:ok, entries}

      {:error, :enoent} ->
        {:ok, []}
    end
  end

  @impl true
  def load_since(session_id, _timestamp, workspace_path) do
    {:ok, entries} = load(session_id, workspace_path)
    {:ok, entries}
  end

  @impl true
  def list_sessions(workspace_path, _opts \\ []) do
    path = Path.join(workspace_path, ".worth/transcript.jsonl")

    case File.read(path) do
      {:ok, content} ->
        sessions =
          content
          |> String.split("\n", trim: true)
          |> Enum.map(&Jason.decode!/1)
          |> Enum.map(& &1["session_id"])
          |> Enum.uniq()

        {:ok, sessions}

      {:error, :enoent} ->
        {:ok, []}
    end
  end
end
