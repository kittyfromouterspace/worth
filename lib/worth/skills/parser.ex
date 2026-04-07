defmodule Worth.Skill.Parser do
  @frontmatter_delimiter ~r/^-{3,}\s*$/

  def parse(skill_md_content) when is_binary(skill_md_content) do
    case split_frontmatter(skill_md_content) do
      {nil, body} ->
        {:error, "No frontmatter found in SKILL.md"}

      {frontmatter_str, body} ->
        case parse_frontmatter(frontmatter_str) do
          {:ok, frontmatter} ->
            skill = build_skill(frontmatter, String.trim(body))
            {:ok, skill}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  def parse(_), do: {:error, "Invalid input"}

  def parse_file(path) do
    case File.read(path) do
      {:ok, content} -> parse(content)
      {:error, reason} -> {:error, "Failed to read #{path}: #{reason}"}
    end
  end

  defp split_frontmatter(content) do
    lines = String.split(content, "\n")

    case lines do
      [first | rest] ->
        if Regex.match?(@frontmatter_delimiter, first) do
          case Enum.split_while(rest, fn line -> not Regex.match?(@frontmatter_delimiter, line) end) do
            {fm_lines, [_delimiter | body_lines]} ->
              {Enum.join(fm_lines, "\n"), Enum.join(body_lines, "\n")}

            {_, []} ->
              {nil, content}
          end
        else
          {nil, content}
        end

      _ ->
        {nil, content}
    end
  end

  defp parse_frontmatter(frontmatter_str) do
    try do
      case YamlElixir.read_from_string(frontmatter_str) do
        {:ok, map} when is_map(map) ->
          {:ok, map}

        {:ok, other} ->
          {:error, "Frontmatter must be a YAML map, got: #{inspect(other)}"}

        {:error, %YamlElixir.ParsingError{} = e} ->
          {:error, "YAML parse error: #{Exception.message(e)}"}

        {:error, reason} ->
          {:error, "YAML parse error: #{inspect(reason)}"}
      end
    rescue
      e -> {:error, "YAML parse error: #{Exception.message(e)}"}
    end
  end

  defp build_skill(frontmatter, body) do
    evolution = frontmatter["evolution"] || %{}

    %{
      name: frontmatter["name"],
      description: frontmatter["description"],
      license: frontmatter["license"],
      compatibility: frontmatter["compatibility"],
      metadata: frontmatter["metadata"] || %{},
      loading: parse_loading(frontmatter["loading"]),
      model_tier: parse_model_tier(frontmatter["model_tier"]),
      provenance: parse_provenance(frontmatter["provenance"]),
      trust_level: parse_trust_level(frontmatter["trust_level"]),
      allowed_tools: frontmatter["allowed-tools"] || nil,
      evolution: %{
        created_at: evolution["created_at"],
        created_by: evolution["created_by"],
        version: evolution["version"] || 1,
        refinement_count: evolution["refinement_count"] || 0,
        success_rate: evolution["success_rate"] || 0.0,
        usage_count: evolution["usage_count"] || 0,
        last_used: evolution["last_used"],
        last_refined: evolution["last_refined"],
        superseded_by: evolution["superseded_by"],
        superseded_from: evolution["superseded_from"] || [],
        feedback_summary: evolution["feedback_summary"]
      },
      body: body
    }
  end

  defp parse_loading(nil), do: :on_demand
  defp parse_loading("always"), do: :always
  defp parse_loading("on_demand"), do: :on_demand
  defp parse_loading("trigger:" <> _ = t), do: {:trigger, t}
  defp parse_loading(other) when is_binary(other), do: :on_demand

  defp parse_model_tier(nil), do: :any
  defp parse_model_tier("primary"), do: :primary
  defp parse_model_tier("lightweight"), do: :lightweight
  defp parse_model_tier("any"), do: :any
  defp parse_model_tier(_), do: :any

  defp parse_provenance(nil), do: :human
  defp parse_provenance("human"), do: :human
  defp parse_provenance("agent"), do: :agent
  defp parse_provenance("hybrid"), do: :hybrid
  defp parse_provenance(_), do: :human

  defp parse_trust_level(nil), do: :installed
  defp parse_trust_level("core"), do: :core
  defp parse_trust_level("installed"), do: :installed
  defp parse_trust_level("learned"), do: :learned
  defp parse_trust_level("unverified"), do: :unverified
  defp parse_trust_level(_), do: :unverified

  def to_frontmatter_string(skill) do
    lines = [
      "---",
      "name: #{skill.name}",
      "description: #{yaml_string(skill.description)}",
      "loading: #{loading_to_string(skill.loading)}",
      "model_tier: #{Atom.to_string(skill.model_tier)}",
      "provenance: #{Atom.to_string(skill.provenance)}",
      "trust_level: #{Atom.to_string(skill.trust_level)}"
    ]

    lines = if skill.license, do: lines ++ ["license: #{yaml_string(skill.license)}"], else: lines
    lines = if skill.allowed_tools, do: lines ++ ["allowed-tools: #{inspect(skill.allowed_tools)}"], else: lines

    evo = skill.evolution

    evo_lines = [
      "evolution:",
      "  created_at: #{evo[:created_at] || "null"}",
      "  created_by: #{evo[:created_by] || "null"}",
      "  version: #{evo[:version] || 1}",
      "  refinement_count: #{evo[:refinement_count] || 0}",
      "  success_rate: #{evo[:success_rate] || 0.0}",
      "  usage_count: #{evo[:usage_count] || 0}",
      "  last_used: #{evo[:last_used] || "null"}",
      "  last_refined: #{evo[:last_refined] || "null"}",
      "  superseded_by: #{evo[:superseded_by] || "null"}",
      "  superseded_from: #{inspect(evo[:superseded_from] || [])}",
      "  feedback_summary: #{evo[:feedback_summary] || "null"}"
    ]

    (lines ++ evo_lines ++ ["---", "", skill.body])
    |> Enum.join("\n")
  end

  defp yaml_string(nil), do: "null"
  defp yaml_string(s), do: String.replace(s, "\"", "\\\"")

  defp loading_to_string(:always), do: "always"
  defp loading_to_string(:on_demand), do: "on_demand"
  defp loading_to_string({:trigger, t}), do: t
  defp loading_to_string(_), do: "on_demand"
end
