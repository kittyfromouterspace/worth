defmodule WorthWeb.Commands.ModelCommands do
  @moduledoc """
  Handles /model commands for searching and setting LLM models.
  """

  import Phoenix.Component, only: [assign: 3]
  import WorthWeb.Commands.Helpers

  alias AgentEx.LLM.Catalog

  def handle({:model, :status}, socket) do
    routing = current_routing()

    msg =
      case routing do
        %{mode: "manual", manual_model: %{provider: p, model_id: m}} ->
          "Model: #{p}/#{m} (manual)"

        %{mode: "auto", preference: pref, filter: filter} ->
          suffix = if filter == "free_only", do: ", free only", else: ""
          "Model: auto (#{pref}#{suffix})"

        _ ->
          "Model: auto (default)"
      end

    append_system(socket, msg <> "\nUse /model list, /model <query>, /model set <provider/id>, or /model auto")
  end

  def handle({:model, :auto}, socket) do
    routing = current_routing()
    new_routing = routing |> Map.delete(:manual_model) |> Map.put(:mode, "auto")
    save_routing(new_routing)

    socket
    |> assign(:model_routing, new_routing)
    |> append_system("Switched to automatic model selection.")
  end

  def handle({:model, :list}, socket) do
    models = Catalog.all()

    if models == [] do
      append_system(socket, "No models in catalog. Try /catalog refresh")
    else
      lines =
        models
        |> Enum.group_by(fn m -> to_string(m.provider) end)
        |> Enum.sort_by(fn {provider, _} -> provider end)
        |> Enum.map_join("\n", fn {provider, provider_models} ->
          # Deduplicate models that appear under both atom and string provider keys
          deduped =
            provider_models
            |> Enum.uniq_by(& &1.id)
            |> Enum.sort_by(& &1.id)

          model_lines =
            Enum.map_join(deduped, "\n", fn m -> "    #{format_model(m)}" end)

          "  #{provider} (#{length(deduped)}):\n#{model_lines}"
        end)

      append_system(socket, "Available models:\n#{lines}")
    end
  end

  def handle({:model, {:search, query}}, socket) do
    models = Catalog.all()
    query_down = String.downcase(query)

    matches =
      models
      |> Enum.filter(fn m ->
        id_match = String.contains?(String.downcase(m.id), query_down)
        label_match = m.label && String.contains?(String.downcase(m.label), query_down)
        provider_match = String.contains?(to_string(m.provider), query_down)
        id_match or label_match or provider_match
      end)
      |> Enum.uniq_by(fn m -> {to_string(m.provider), m.id} end)
      |> Enum.sort_by(fn m ->
        # Exact prefix matches first, then alphabetical
        id_down = String.downcase(m.id)

        cond do
          id_down == query_down -> {0, id_down}
          String.starts_with?(id_down, query_down) -> {1, id_down}
          true -> {2, id_down}
        end
      end)

    case matches do
      [] ->
        append_system(socket, "No models matching '#{query}'. Try /model list")

      matches ->
        lines =
          matches
          |> Enum.take(20)
          |> Enum.map_join("\n", fn m ->
            "  #{to_string(m.provider)}/#{m.id}  #{format_meta(m)}"
          end)

        count_suffix = if length(matches) > 20, do: "\n  ... and #{length(matches) - 20} more", else: ""

        append_system(
          socket,
          "Models matching '#{query}':\n#{lines}#{count_suffix}\n\nSet one with: /model set <provider/model_id>"
        )
    end
  end

  def handle({:model, {:set, input}}, socket) do
    case parse_model_ref(input) do
      {:ok, provider, model_id} ->
        # Verify the model exists in catalog (try both atom and string provider keys)
        case catalog_lookup(provider, model_id) do
          nil ->
            # Try a fuzzy lookup - maybe they gave a partial id
            suggest_close_matches(socket, provider, model_id)

          _model ->
            routing =
              current_routing()
              |> Map.put(:mode, "manual")
              |> Map.put(:manual_model, %{provider: provider, model_id: model_id})

            save_routing(routing)

            socket
            |> assign(:model_routing, routing)
            |> append_system("Model set to #{provider}/#{model_id} (manual mode)")
        end

      :error ->
        append_system(
          socket,
          "Usage: /model set <provider>/<model_id>\nExample: /model set anthropic/claude-sonnet-4-20250514"
        )
    end
  end

  # ── Helpers ──────────────────────────────────────────────────

  defp catalog_lookup(provider, model_id) do
    # Catalog may store provider as atom or string
    result = Catalog.lookup(safe_to_existing_atom(provider), model_id)
    result || Catalog.lookup(provider, model_id)
  end

  defp safe_to_existing_atom(str) when is_binary(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> nil
  end

  defp parse_model_ref(input) do
    input = String.trim(input)

    case String.split(input, "/", parts: 2) do
      [provider, model_id] when provider != "" and model_id != "" ->
        {:ok, provider, model_id}

      _ ->
        :error
    end
  end

  defp suggest_close_matches(socket, provider, model_id) do
    provider_models =
      case safe_to_existing_atom(provider) do
        nil -> []
        atom -> Catalog.for_provider(atom)
      end

    provider_models = Enum.uniq_by(provider_models, & &1.id)
    query_down = String.downcase(model_id)

    close =
      provider_models
      |> Enum.filter(fn m -> String.contains?(String.downcase(m.id), query_down) end)
      |> Enum.take(5)

    if close == [] do
      append_system(socket, "Model '#{provider}/#{model_id}' not found. Check /model list")
    else
      suggestions =
        Enum.map_join(close, "\n", fn m -> "  #{provider}/#{m.id}" end)

      append_system(socket, "Model '#{provider}/#{model_id}' not found. Did you mean:\n#{suggestions}")
    end
  end

  defp format_model(m) do
    parts = [m.id]
    parts = if m.tier_hint, do: parts ++ ["[#{m.tier_hint}]"], else: parts
    parts = parts ++ cost_parts(m.cost)
    parts = if is_free?(m), do: parts ++ ["(free)"], else: parts
    Enum.join(parts, "  ")
  end

  defp format_meta(m) do
    parts = []
    parts = if m.tier_hint, do: parts ++ ["[#{m.tier_hint}]"], else: parts
    parts = parts ++ cost_parts(m.cost)
    parts = if is_free?(m), do: parts ++ ["(free)"], else: parts
    if parts == [], do: "", else: Enum.join(parts, " ")
  end

  defp cost_parts(nil), do: []

  defp cost_parts(cost) when is_map(cost) do
    input = cost[:input] || cost["input"]
    output = cost[:output] || cost["output"]

    if input && output do
      ["$#{Float.round(input / 1, 2)}/$#{Float.round(output / 1, 2)}"]
    else
      []
    end
  end

  defp cost_parts(_), do: []

  defp is_free?(m) do
    caps = m.capabilities || MapSet.new()
    :free in caps or "free" in caps
  end

  defp current_routing do
    case Worth.Config.get([:model_routing]) do
      %{} = routing -> routing
      _ -> %{mode: "auto", preference: "optimize_price", filter: "free_only"}
    end
  end

  defp save_routing(routing) do
    Worth.Config.put([:model_routing], routing)
    Worth.Settings.put("model_routing_mode", routing.mode, "preference")

    if routing[:manual_model] do
      ref = "#{routing.manual_model.provider}/#{routing.manual_model.model_id}"
      Worth.Settings.put("model_routing_manual_model", ref, "preference")
    else
      Worth.Settings.put("model_routing_manual_model", "", "preference")
    end

    :ok
  catch
    :exit, {:noproc, _} -> :ok
    :exit, _ -> :ok
  end
end
