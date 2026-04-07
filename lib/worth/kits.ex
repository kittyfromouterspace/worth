defmodule Worth.Kits do
  @base_url "https://journeykits.ai/api"

  def search(query, opts \\ []) do
    url = "#{@base_url}/kits/search?q=#{URI.encode_www_form(query)}"

    url =
      opts
      |> Enum.reduce(url, fn
        {:tag, tag}, acc -> acc <> "&tag[]=#{URI.encode_www_form(tag)}"
        {:tech, tech}, acc -> acc <> "&tech[]=#{URI.encode_www_form(tech)}"
        _, acc -> acc
      end)

    case Req.get(url, receive_timeout: 10_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, parse_search_results(body)}

      {:ok, %Req.Response{status: status}} ->
        {:error, "JourneyKits returned status #{status}"}

      {:error, reason} ->
        {:error, "Failed to reach JourneyKits: #{inspect(reason)}"}
    end
  end

  def info(owner, slug) do
    url = "#{@base_url}/kits/#{owner}/#{slug}"

    case Req.get(url, receive_timeout: 10_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, parse_kit_detail(body)}

      {:ok, %Req.Response{status: 404}} ->
        {:error, "Kit '#{owner}/#{slug}' not found"}

      {:ok, %Req.Response{status: status}} ->
        {:error, "JourneyKits returned status #{status}"}

      {:error, reason} ->
        {:error, "Failed to reach JourneyKits: #{inspect(reason)}"}
    end
  end

  def install(owner, slug, opts \\ []) do
    workspace_path = opts[:workspace_path]

    url = "#{@base_url}/kits/#{owner}/#{slug}/install"

    case Req.get(url, receive_timeout: 15_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        install_payload = parse_install_payload(body)
        extract_skills(install_payload, owner, slug)
        maybe_write_sources(install_payload, workspace_path)
        track_installation(owner, slug, install_payload)
        {:ok, install_payload}

      {:ok, %Req.Response{status: 404}} ->
        {:error, "Kit '#{owner}/#{slug}' not found"}

      {:ok, %Req.Response{status: status}} ->
        {:error, "Install failed with status #{status}"}

      {:error, reason} ->
        {:error, "Failed to reach JourneyKits: #{inspect(reason)}"}
    end
  end

  def list_installed do
    config_file = Path.expand("~/.worth/installed_kits.json")

    case File.read(config_file) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, kits} -> {:ok, kits}
          _ -> {:ok, %{}}
        end

      _ ->
        {:ok, %{}}
    end
  end

  def publish(kit_dir, opts \\ []) do
    kit_md = Path.join(kit_dir, "kit.md")

    unless File.exists?(kit_md) do
      {:error, "No kit.md found in #{kit_dir}"}
    else
      case build_publish_payload(kit_dir) do
        {:ok, payload} ->
          api_key = opts[:api_key] || System.get_env("JOURNEY_API_KEY")

          headers = if api_key, do: [{"Authorization", "Bearer #{api_key}"}], else: []

          case Req.post("#{@base_url}/kits/import",
                 json: payload,
                 headers: headers,
                 receive_timeout: 15_000
               ) do
            {:ok, %Req.Response{status: 201, body: body}} ->
              {:ok, body}

            {:ok, %Req.Response{status: status, body: body}} ->
              {:error, "Publish failed (#{status}): #{inspect(body)}"}

            {:error, reason} ->
              {:error, "Failed to reach JourneyKits: #{inspect(reason)}"}
          end

        error ->
          error
      end
    end
  end

  defp extract_skills(%{skills: skills}, owner, slug) when is_list(skills) do
    Enum.each(skills, fn skill ->
      case skill do
        %{name: name, content: content} ->
          Worth.Skill.Service.install(
            %{type: :content, name: name, content: content},
            description: skill[:description] || "From kit #{owner}/#{slug}",
            trust_level: :installed,
            provenance: :kit,
            allowed_tools: nil
          )

        _ ->
          :ok
      end
    end)
  end

  defp extract_skills(_, _, _), do: :ok

  defp maybe_write_sources(%{sources: sources}, nil) when is_list(sources), do: :ok

  defp maybe_write_sources(%{sources: sources}, workspace_path) when is_list(sources) do
    Enum.each(sources, fn
      %{path: path, content: content} ->
        full_path = Path.join(workspace_path, path)
        File.mkdir_p!(Path.dirname(full_path))
        File.write!(full_path, content)

      _ ->
        :ok
    end)
  end

  defp maybe_write_sources(_, _), do: :ok

  defp track_installation(owner, slug, payload) do
    config_file = Path.expand("~/.worth/installed_kits.json")
    File.mkdir_p!(Path.dirname(config_file))

    existing =
      case list_installed() do
        {:ok, kits} -> kits
        _ -> %{}
      end

    key = "#{owner}/#{slug}"

    updated =
      Map.put(existing, key, %{
        version: payload[:version] || "unknown",
        installed_at: DateTime.utc_now() |> DateTime.to_iso8601(),
        skills: (payload[:skills] || []) |> Enum.map(& &1[:name]) |> Enum.filter(& &1),
        status: "active"
      })

    File.write!(config_file, Jason.encode!(updated, pretty: true))
  end

  defp build_publish_payload(kit_dir) do
    kit_md = Path.join(kit_dir, "kit.md")
    content = File.read!(kit_md)
    sources = collect_sources(kit_dir)

    {:ok, %{kit_md: content, sources: sources}}
  end

  defp collect_sources(kit_dir) do
    src_dir = Path.join(kit_dir, "src")

    if File.dir?(src_dir) do
      src_dir
      |> File.ls!()
      |> Enum.map(fn filename ->
        path = Path.join(src_dir, filename)
        %{path: "src/#{filename}", content: File.read!(path)}
      end)
    else
      []
    end
  end

  defp parse_search_results(body) when is_map(body) do
    kits = body["kits"] || body[:kits] || []

    Enum.map(kits, fn kit ->
      %{
        slug: kit["slug"] || kit[:slug],
        owner: kit["owner"] || kit[:owner],
        title: kit["title"] || kit[:title] || "",
        summary: kit["summary"] || kit[:summary] || "",
        version: kit["version"] || kit[:version],
        tags: kit["tags"] || kit[:tags] || []
      }
    end)
  end

  defp parse_search_results(body) when is_list(body), do: parse_search_results(%{"kits" => body})
  defp parse_search_results(_), do: []

  defp parse_kit_detail(body) when is_map(body) do
    %{
      slug: body["slug"],
      owner: body["owner"],
      title: body["title"],
      summary: body["summary"],
      version: body["version"],
      tags: body["tags"] || [],
      tools: body["tools"] || [],
      skills: body["skills"] || [],
      tech: body["tech"] || [],
      parameters: body["parameters"] || [],
      failures: body["failures"] || [],
      prerequisites: body["prerequisites"] || []
    }
  end

  defp parse_install_payload(body) when is_map(body) do
    %{
      version: body["version"],
      skills: (body["skills"] || []) |> Enum.map(&normalize_skill/1),
      sources: (body["sources"] || body["files"] || []) |> Enum.map(&normalize_source/1),
      instructions: body["instructions"] || body["steps"] || ""
    }
  end

  defp normalize_skill(%{"name" => name, "content" => content} = s) do
    %{name: name, content: content, description: s["description"]}
  end

  defp normalize_skill(s), do: s

  defp normalize_source(%{"path" => path, "content" => content}), do: %{path: path, content: content}
  defp normalize_source(s), do: s
end
