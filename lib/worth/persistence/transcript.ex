defmodule Worth.Persistence.Transcript do
  @behaviour AgentEx.Persistence.Transcript

  require Logger

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
          |> Enum.flat_map(&decode_line/1)
          |> Enum.filter(&(&1["session_id"] == session_id))

        {:ok, entries}

      {:error, :enoent} ->
        {:ok, []}
    end
  end

  @impl true
  def load_since(session_id, timestamp, workspace_path) do
    {:ok, entries} = load(session_id, workspace_path)

    filtered =
      Enum.filter(entries, fn entry ->
        case entry["timestamp"] do
          nil -> true
          ts when is_binary(ts) -> ts >= to_string(timestamp)
          _ -> true
        end
      end)

    {:ok, filtered}
  end

  @impl true
  def list_sessions(workspace_path, _opts \\ []) do
    path = Path.join(workspace_path, ".worth/transcript.jsonl")

    case File.read(path) do
      {:ok, content} ->
        sessions =
          content
          |> String.split("\n", trim: true)
          |> Enum.flat_map(&decode_line/1)
          |> Enum.map(& &1["session_id"])
          |> Enum.uniq()

        {:ok, sessions}

      {:error, :enoent} ->
        {:ok, []}
    end
  end

  defp decode_line(line) do
    case Jason.decode(line) do
      {:ok, entry} -> [entry]
      {:error, _} ->
        Logger.warning("Transcript: skipping corrupt line")
        []
    end
  end
end
