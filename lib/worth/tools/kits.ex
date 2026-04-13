defmodule Worth.Tools.Kits do
  @moduledoc false
  def definitions do
    [
      %{
        name: "kit_search",
        description: "Search JourneyKits for packaged AI agent workflows",
        input_schema: %{
          type: "object",
          properties: %{
            query: %{type: "string", description: "Search query"},
            tag: %{type: "string", description: "Filter by tag"},
            tech: %{type: "string", description: "Filter by technology"}
          },
          required: ["query"]
        }
      },
      %{
        name: "kit_install",
        description: "Install a kit (extracts skills + source files)",
        input_schema: %{
          type: "object",
          properties: %{
            owner: %{type: "string", description: "Kit owner"},
            slug: %{type: "string", description: "Kit slug"},
            workspace: %{type: "string", description: "Workspace path for source files"}
          },
          required: ["owner", "slug"]
        }
      },
      %{
        name: "kit_list",
        description: "List installed kits",
        input_schema: %{type: "object", properties: %{}}
      },
      %{
        name: "kit_info",
        description: "Get kit details and dependencies",
        input_schema: %{
          type: "object",
          properties: %{
            owner: %{type: "string"},
            slug: %{type: "string"}
          },
          required: ["owner", "slug"]
        }
      },
      %{
        name: "kit_publish",
        description: "Package and publish a workflow as a kit",
        input_schema: %{
          type: "object",
          properties: %{
            directory: %{type: "string", description: "Directory containing kit.md"}
          },
          required: ["directory"]
        }
      }
    ]
  end

  def execute("kit_search", %{"query" => query} = args, _workspace) do
    opts = []
    opts = if args["tag"], do: [{:tag, args["tag"]} | opts], else: opts
    opts = if args["tech"], do: [{:tech, args["tech"]} | opts], else: opts

    case Worth.Kits.search(query, opts) do
      {:ok, []} ->
        {:ok, "No kits found for '#{query}'."}

      {:ok, kits} ->
        lines =
          Enum.map(kits, fn k ->
            "#{k.owner}/#{k.slug} v#{k.version}: #{k.title}"
          end)

        {:ok, "JourneyKits results:\n" <> Enum.join(lines, "\n")}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def execute("kit_install", %{"owner" => owner, "slug" => slug} = args, _workspace) do
    opts = [workspace_path: args["workspace"]]

    case Worth.Kits.install(owner, slug, opts) do
      {:ok, payload} ->
        skill_names = (payload[:skills] || []) |> Enum.map(& &1[:name]) |> Enum.filter(& &1)
        {:ok, "Installed kit #{owner}/#{slug}. Skills: #{Enum.join(skill_names, ", ")}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def execute("kit_list", _args, _workspace) do
    case Worth.Kits.list_installed() do
      {:ok, kits} when map_size(kits) == 0 ->
        {:ok, "No kits installed."}

      {:ok, kits} ->
        lines =
          Enum.map(kits, fn {key, info} ->
            "#{key} v#{info["version"]} (#{info["status"]})"
          end)

        {:ok, "Installed kits:\n" <> Enum.join(lines, "\n")}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def execute("kit_info", %{"owner" => owner, "slug" => slug}, _workspace) do
    case Worth.Kits.info(owner, slug) do
      {:ok, kit} ->
        text =
          "#{kit.title}\n" <>
            "Owner: #{kit.owner}\n" <>
            "Version: #{kit.version}\n" <>
            "Summary: #{kit.summary}\n" <>
            "Tags: #{Enum.join(kit.tags, ", ")}\n" <>
            "Skills: #{Enum.join(kit.skills, ", ")}\n" <>
            "Prerequisites: #{length(kit.prerequisites)} items"

        {:ok, text}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def execute("kit_publish", %{"directory" => dir}, _workspace) do
    case Worth.Kits.publish(dir) do
      {:ok, body} ->
        {:ok, "Kit published successfully: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Publish failed: #{reason}"}
    end
  end

  def execute(_, _, _), do: {:error, "Unknown kit tool"}
end
