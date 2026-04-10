defmodule WorthWeb.Commands.SkillCommands do
  import WorthWeb.Commands.Helpers

  def handle({:skill, :list}, socket) do
    skills = Worth.Skill.Registry.all()

    if skills == [] do
      append_system(socket, "No skills loaded.")
    else
      lines =
        skills
        |> Enum.map(fn s ->
          loading = if s.loading == :always, do: "[always]", else: "[on-demand]"
          "  [#{s.trust_level}] #{loading} #{s.name}: #{String.slice(s.description, 0, 60)}"
        end)
        |> Enum.join("\n")

      append_system(socket, "Skills:\n#{lines}")
    end
  end

  def handle({:skill, {:read, name}}, socket) do
    case Worth.Skill.Service.read_body(name) do
      {:ok, body} ->
        preview = String.slice(body, 0, 500)
        append_system(socket, "Skill '#{name}':\n#{preview}")

      {:error, reason} ->
        append_error(socket, "Failed to read skill: #{reason}")
    end
  end

  def handle({:skill, {:remove, name}}, socket) do
    case Worth.Skill.Service.remove(name) do
      {:ok, _} -> append_system(socket, "Skill '#{name}' removed.")
      {:error, reason} -> append_error(socket, reason)
    end
  end

  def handle({:skill, {:history, name}}, socket) do
    case Worth.Brain.skill_history(socket.assigns.workspace, name) do
      {:ok, versions} when is_list(versions) and versions != [] ->
        lines =
          versions
          |> Enum.map(fn {v, info} -> "  v#{v} (#{info.size} bytes)" end)
          |> Enum.join("\n")

        append_system(socket, "Skill '#{name}' versions:\n#{lines}")

      _ ->
        append_system(socket, "No version history for '#{name}'.")
    end
  end

  def handle({:skill, {:rollback, name, version}}, socket) do
    case Worth.Brain.skill_rollback(socket.assigns.workspace, name, version) do
      {:ok, info} ->
        append_system(socket, "Skill '#{name}' rolled back to v#{info.rolled_back_to}.")

      {:error, reason} ->
        append_error(socket, reason)
    end
  end

  def handle({:skill, {:refine, name}}, socket) do
    case Worth.Brain.skill_refine(socket.assigns.workspace, name) do
      {:ok, :no_refinement_needed} ->
        append_system(socket, "Skill '#{name}' does not need refinement.")

      {:ok, info} ->
        append_system(socket, "Skill '#{name}' refined to v#{info.version}.")

      {:error, reason} ->
        append_error(socket, reason)
    end
  end

  def handle({:skill, :help}, socket) do
    append_system(socket,
      "Skill commands:\n  /skill list\n  /skill read <name>\n  /skill remove <name>\n  /skill history <name>\n  /skill rollback <name> <version>\n  /skill refine <name>"
    )
  end
end
