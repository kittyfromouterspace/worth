defmodule Worth.Memory.Embeddings.Adapter do
  @moduledoc """
  Bridges Mneme's `Mneme.EmbeddingProvider` behaviour to the unified
  `AgentEx.LLM.embed_tier/3` stack.

  Configured in `config/config.exs`:

      config :mneme,
        embedding: [
          provider: Worth.Memory.Embeddings.Adapter,
          tier: :embeddings
        ]

  Tier resolution lives in `AgentEx.LLM.embed_tier/3` — it walks the
  catalog for `:embeddings`-tagged models, optionally filtered by the
  IDENTITY.md frontmatter tier override.
  """

  @behaviour Mneme.EmbeddingProvider

  @default_dimensions 1536
  @default_model "text-embedding-3-small"

  @impl true
  def dimensions(opts) do
    Keyword.get(opts, :dimensions, @default_dimensions)
  end

  @impl true
  def generate(texts, opts) when is_list(texts) do
    model_id = model_id(opts)
    provider = resolve_provider(opts)

    transport = provider.transport()

    case AgentEx.LLM.Credentials.resolve(provider) do
      {:ok, creds} ->
        base_url = creds.base_url_override || provider.default_base_url()

        opts = [
          base_url: base_url,
          api_key: creds.api_key,
          model: model_id,
          extra_headers: creds.headers
        ]

        request = transport.build_embedding_request(texts, opts)

        case Req.post(request.url,
               json: request.body,
               headers: request.headers,
               receive_timeout: 60_000
             ) do
          {:ok, %{status: 200, body: body}} ->
            case transport.parse_embedding_response(200, body, []) do
              {:ok, vectors} -> {:ok, vectors}
              {:error, reason} -> {:error, reason}
            end

          {:ok, %{status: status, body: _body}} ->
            {:error, "embedding request failed: #{status}"}

          {:error, reason} ->
            {:error, Exception.message(reason)}
        end

      :not_configured ->
        {:error, "#{provider.id()} not configured"}
    end
  end

  @impl true
  def embed(text, opts) when is_binary(text) do
    model_id = model_id(opts)
    provider = resolve_provider(opts)

    case embed_direct(text, provider, model_id) do
      {:ok, vector} -> {:ok, vector}
      {:error, reason} -> {:error, reason}
    end
  end

  defp embed_direct(text, provider, model_id) do
    transport = provider.transport()

    case AgentEx.LLM.Credentials.resolve(provider) do
      {:ok, creds} ->
        base_url = creds.base_url_override || provider.default_base_url()

        opts = [
          base_url: base_url,
          api_key: creds.api_key,
          model: model_id,
          extra_headers: creds.headers
        ]

        request = transport.build_embedding_request(text, opts)
        execute_embed(request, transport)

      :not_configured ->
        {:error, "#{provider.id()} not configured"}
    end
  end

  defp execute_embed(request, transport) do
    case Req.post(request.url,
           json: request.body,
           headers: request.headers,
           receive_timeout: 60_000
         ) do
      {:ok, %{status: 200, body: body}} ->
        case transport.parse_embedding_response(200, body, []) do
          {:ok, [vector | _]} -> {:ok, vector}
          {:ok, []} -> {:error, :no_embedding_returned}
          {:error, reason} -> {:error, reason}
        end

      {:ok, %{status: status, body: _body}} ->
        {:error, "embedding request failed: #{status}"}

      {:error, reason} ->
        {:error, Exception.message(reason)}
    end
  end

  defp resolve_provider(opts) do
    case Keyword.get(opts, :provider) do
      nil ->
        model = Keyword.get(opts, :model) || configured_model()

        if model do
          case catalog_model_provider(model) do
            nil -> default_provider()
            provider -> AgentEx.LLM.ProviderRegistry.get(provider)
          end
        else
          default_provider()
        end

      provider_id ->
        AgentEx.LLM.ProviderRegistry.get(provider_id)
    end
  end

  defp default_provider do
    AgentEx.LLM.ProviderRegistry.get(:openrouter)
  end

  defp catalog_model_provider(model_id) do
    models = AgentEx.LLM.Catalog.find(has: :embeddings)

    case Enum.find(models, fn m -> m.id == model_id end) do
      nil -> nil
      model -> model.provider
    end
  end

  @impl true
  def model_id(opts) do
    case Keyword.get(opts, :model) do
      nil ->
        case Keyword.get(opts, :model_override) do
          nil -> configured_model() || @default_model
          override when is_binary(override) -> override
        end

      model when is_binary(model) ->
        model
    end
  end

  defp configured_model do
    Worth.Config.get([:memory, :embedding_model])
  end
end
