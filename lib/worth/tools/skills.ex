defmodule Worth.Tools.Skills do
  @moduledoc false

  alias Worth.Skill.Service

  def definitions do
    [
      %{
        name: "skill_list",
        description: "List all available skills with metadata and trust levels",
        input_schema: %{
          type: "object",
          properties: %{
            filter: %{
              type: "string",
              description: "Filter by trust level or loading: core, installed, learned, always, on_demand"
            }
          }
        }
      },
      %{
        name: "skill_read",
        description: "Load the full SKILL.md content for a specific skill (L2 disclosure)",
        input_schema: %{
          type: "object",
          properties: %{
            name: %{type: "string", description: "Skill name to read"}
          },
          required: ["name"]
        }
      },
      %{
        name: "skill_install",
        description: "Install a skill from a local path or create from content",
        input_schema: %{
          type: "object",
          properties: %{
            name: %{type: "string", description: "Name for the skill"},
            content: %{type: "string", description: "Skill instructions (body content)"},
            description: %{type: "string", description: "Brief description of the skill"}
          },
          required: ["name", "content"]
        }
      },
      %{
        name: "skill_remove",
        description: "Remove an installed skill (cannot remove core skills)",
        input_schema: %{
          type: "object",
          properties: %{
            name: %{type: "string", description: "Skill name to remove"}
          },
          required: ["name"]
        }
      },
      %{
        name: "skill_create",
        description: "Create a new learned skill from experience or analysis",
        input_schema: %{
          type: "object",
          properties: %{
            name: %{type: "string", description: "Skill name (lowercase, hyphens)"},
            description: %{type: "string", description: "Brief description"},
            content: %{type: "string", description: "Full skill instructions"},
            allowed_tools: %{
              type: "array",
              items: %{type: "string"},
              description: "Tools this skill is allowed to use (for learned skills)"
            }
          },
          required: ["name", "description", "content"]
        }
      }
    ]
  end

  def execute("skill_list", args, _workspace) do
    filter = args["filter"]

    skills =
      case filter do
        "core" -> Enum.filter(Worth.Skill.Registry.all(), &(&1.trust_level == :core))
        "installed" -> Enum.filter(Worth.Skill.Registry.all(), &(&1.trust_level == :installed))
        "learned" -> Enum.filter(Worth.Skill.Registry.all(), &(&1.trust_level == :learned))
        "always" -> Worth.Skill.Registry.always_loaded()
        "on_demand" -> Worth.Skill.Registry.on_demand()
        _ -> Worth.Skill.Registry.all()
      end

    if skills == [] do
      {:ok, "No skills found."}
    else
      lines =
        Enum.map_join(skills, "\n", fn s ->
          loading = if s.loading == :always, do: "[always]", else: "[on-demand]"
          "[#{s.trust_level}] #{loading} #{s.name}: #{s.description}"
        end)

      {:ok, "Available skills:\n#{lines}"}
    end
  end

  def execute("skill_read", %{"name" => name}, _workspace) do
    case Service.read(name) do
      {:ok, skill} ->
        {:ok, skill.body}

      {:error, reason} ->
        {:error, "Failed to read skill '#{name}': #{reason}"}
    end
  end

  def execute("skill_install", %{"name" => name, "content" => content} = args, _workspace) do
    opts = [
      description: args["description"] || "User-installed skill",
      trust_level: :installed,
      provenance: :human
    ]

    case Service.install(%{type: :content, name: name, content: content}, opts) do
      {:ok, ^name} -> {:ok, "Skill '#{name}' installed successfully."}
      other -> {:error, "Failed to install: #{inspect(other)}"}
    end
  end

  def execute("skill_remove", %{"name" => name}, _workspace) do
    case Service.remove(name) do
      {:ok, ^name} -> {:ok, "Skill '#{name}' removed."}
      {:error, reason} -> {:error, reason}
    end
  end

  def execute("skill_create", %{"name" => name, "description" => desc, "content" => content} = args, _workspace) do
    opts = [
      description: desc,
      trust_level: :learned,
      provenance: :agent,
      allowed_tools: args["allowed_tools"]
    ]

    case Service.install(%{type: :content, name: name, content: content}, opts) do
      {:ok, ^name} -> {:ok, "Learned skill '#{name}' created."}
      other -> {:error, "Failed to create skill: #{inspect(other)}"}
    end
  end

  def execute(name, _args, _workspace) do
    {:error, "Unknown skill tool: #{name}"}
  end
end
