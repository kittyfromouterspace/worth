defmodule WorthWeb.Commands.MemoryCommands do
  import WorthWeb.Commands.Helpers

  def handle({:memory, {:query, query}}, socket) do
    case Worth.Memory.Manager.search(query, workspace: socket.assigns.workspace, limit: 5) do
      {:ok, %{entries: entries}} when is_list(entries) and entries != [] ->
        lines =
          entries
          |> Enum.map(fn e -> "  [#{Float.round(e.confidence || 0.5, 2)}] #{e.content}" end)
          |> Enum.join("\n")

        append_system(socket, "Memory results for '#{query}':\n#{lines}")

      _ ->
        append_system(socket, "No memories found for '#{query}'")
    end
  end

  def handle({:memory, {:note, note}}, socket) do
    case Worth.Memory.Manager.working_push(note,
           workspace: socket.assigns.workspace,
           importance: 0.5,
           metadata: %{entry_type: "note", role: "user"}
         ) do
      {:ok, _} ->
        append_system(socket, "Note added to working memory.")

      {:error, reason} ->
        append_error(socket, "Failed to add note: #{inspect(reason)}")
    end
  end

  def handle({:memory, :reembed}, socket) do
    parent = self()

    Task.start(fn ->
      result = Worth.Tools.Memory.Reembed.run([])
      send(parent, {:reembed_done, result})
    end)

    append_system(socket, "Re-embedding memories in the background... (results will follow)")
  end

  def handle({:memory, :recent}, socket) do
    case Worth.Memory.Manager.recent(workspace: socket.assigns.workspace, limit: 10) do
      {:ok, entries} when is_list(entries) and entries != [] ->
        lines =
          entries
          |> Enum.map(fn e -> "  [#{e.entry_type}] #{String.slice(e.content, 0, 80)}" end)
          |> Enum.join("\n")

        append_system(socket, "Recent memories:\n#{lines}")

      _ ->
        append_system(socket, "No recent memories.")
    end
  end
end
