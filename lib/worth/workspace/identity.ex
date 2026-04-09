defmodule Worth.Workspace.Identity do
  @moduledoc """
  Parses IDENTITY.md frontmatter to extract workspace-level config,
  including the `llm:` block with tier overrides, cost ceiling, and
  other provider preferences.

  The IDENTITY.md format supports optional YAML frontmatter:

      ---
      name: my-project
      description: A project that does ...
      llm:
        tiers:
          primary: "anthropic/claude-opus-4-6"
          lightweight: "anthropic/claude-haiku-4-5"
          embeddings: "openai/text-embedding-3-small"
        prefer_free: true
        cost_ceiling_per_turn: 0.05
        prompt_caching: true
      ---

      # Project description goes here as usual

  Resolution order (highest priority first):
    1. Workspace `IDENTITY.md` frontmatter `llm:` block
    2. Global `~/.worth/config.exs` `[:llm, :tiers]` setting
    3. Compile-time provider defaults in `agent_ex`
  """

  @frontmatter_delimiter ~r/^-{3,}\s*$/

  @llm_schema [
    tiers: [
      type: {:map, :string},
      default: %{},
      doc: "Map of tier atom to \"provider/model_id\" string"
    ],
    prefer_free: [
      type: :boolean,
      default: false,
      doc: "Prefer free models when available"
    ],
    cost_ceiling_per_turn: [
      type: {:or, [:float, :integer]},
      default: nil,
      doc: "Maximum USD cost per turn"
    ],
    prompt_caching: [
      type: :boolean,
      default: true,
      doc: "Enable prompt caching for supported providers"
    ]
  ]

  @doc """
  Load and parse the IDENTITY.md from a workspace path.

  Returns `{:ok, %{frontmatter: map, body: string, llm: map}}` or
  `{:ok, %{frontmatter: nil, body: string, llm: %{}}}` when no
  frontmatter is present.
  """
  def load(workspace_path) do
    identity_path = Path.join(workspace_path, "IDENTITY.md")

    case File.read(identity_path) do
      {:ok, content} ->
        {frontmatter, body} = split_frontmatter(content)
        llm = parse_llm_config(frontmatter)
        {:ok, %{frontmatter: frontmatter, body: body, llm: llm}}

      {:error, _} ->
        {:ok, %{frontmatter: nil, body: nil, llm: %{}}}
    end
  end

  @doc """
  Extract just the LLM tier overrides from a workspace path.

  Returns a map like `%{primary: "anthropic/claude-sonnet-4", lightweight: "openai/gpt-4o-mini"}`
  suitable for passing to `AgentEx.ModelRouter.set_tier_overrides/1`.
  """
  def tier_overrides(workspace_path) do
    case load(workspace_path) do
      {:ok, %{llm: %{tiers: tiers}}} when is_map(tiers) and map_size(tiers) > 0 ->
        tiers

      _ ->
        %{}
    end
  end

  @doc """
  Extract the full llm config from a workspace path.
  """
  def llm_config(workspace_path) do
    case load(workspace_path) do
      {:ok, %{llm: llm}} -> llm
      _ -> %{}
    end
  end

  # ----- parsing -----

  defp split_frontmatter(content) do
    lines = String.split(content, "\n")

    case lines do
      [first | rest] ->
        if Regex.match?(@frontmatter_delimiter, first) do
          case Enum.split_while(rest, fn line -> not Regex.match?(@frontmatter_delimiter, line) end) do
            {fm_lines, [_delimiter | body_lines]} ->
              fm = Enum.join(fm_lines, "\n")
              body = Enum.join(body_lines, "\n") |> String.trim()
              {parse_yaml(fm), body}

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

  defp parse_yaml(yaml_str) when is_binary(yaml_str) do
    try do
      case YamlElixir.read_from_string(yaml_str) do
        {:ok, map} when is_map(map) -> atomize_keys(map)
        _ -> nil
      end
    rescue
      e ->
        require Logger
        Logger.warning("Failed to parse YAML frontmatter: #{Exception.message(e)}")
        nil
    end
  end

  defp parse_yaml(_), do: nil

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), atomize_keys(v)}
      {k, v} -> {k, atomize_keys(v)}
    end)
  end

  defp atomize_keys(list) when is_list(list), do: Enum.map(list, &atomize_keys/1)
  defp atomize_keys(other), do: other

  defp parse_llm_config(nil), do: %{}

  defp parse_llm_config(%{llm: llm_map}) when is_map(llm_map) do
    tiers = parse_tiers(llm_map[:tiers] || %{})

    config = %{
      tiers: tiers,
      prefer_free: llm_map[:prefer_free] == true,
      cost_ceiling_per_turn: parse_float(llm_map[:cost_ceiling_per_turn]),
      prompt_caching: llm_map[:prompt_caching] != false
    }

    try do
      kw = Keyword.new(config, fn {k, v} -> {k, v} end)

      case NimbleOptions.validate(kw, @llm_schema) do
        {:ok, validated} -> Map.new(validated)
        {:error, _} -> config
      end
    rescue
      e ->
        require Logger
        Logger.warning("Failed to validate LLM config: #{Exception.message(e)}")
        config
    end
  end

  defp parse_llm_config(_), do: %{}

  defp parse_tiers(tiers) when is_map(tiers) do
    tiers
    |> Enum.flat_map(fn
      {k, v} when is_atom(k) and is_binary(v) -> [{k, v}]
      {k, v} when is_binary(k) and is_binary(v) -> [{String.to_atom(k), v}]
      _ -> []
    end)
    |> Map.new()
  end

  defp parse_tiers(_), do: %{}

  defp parse_float(nil), do: nil
  defp parse_float(n) when is_number(n), do: n / 1
  defp parse_float(_), do: nil
end
