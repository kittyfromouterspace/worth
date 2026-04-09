defmodule WorthWeb.Commands.ProviderCommands do
  import WorthWeb.Commands.Helpers

  def handle({:provider, :list}, socket) do
    providers = AgentEx.LLM.ProviderRegistry.list()

    if providers == [] do
      append_system(socket, "No providers registered.")
    else
      lines =
        providers
        |> Enum.map(fn p ->
          status = if p.status == :enabled, do: "enabled", else: "disabled"

          models =
            try do
              p.module.default_models() |> length()
            rescue
              _ -> "?"
            end

          "  [#{status}] #{p.module.label()} (#{p.id}) - #{models} models"
        end)
        |> Enum.join("\n")

      append_system(socket, "Providers:\n#{lines}")
    end
  end

  def handle({:provider, {:enable, id}}, socket) do
    case AgentEx.LLM.ProviderRegistry.enable(id) do
      :ok -> append_system(socket, "Provider #{id} enabled.")
      {:error, :not_found} -> append_error(socket, "Provider '#{id}' not found.")
    end
  end

  def handle({:provider, {:disable, id}}, socket) do
    case AgentEx.LLM.ProviderRegistry.disable(id) do
      :ok -> append_system(socket, "Provider #{id} disabled.")
      {:error, :not_found} -> append_error(socket, "Provider '#{id}' not found.")
    end
  end

  def handle({:catalog, :refresh}, socket) do
    AgentEx.LLM.Catalog.refresh()
    info = AgentEx.LLM.Catalog.info()
    append_system(socket, "Catalog refresh triggered. #{info.model_count} models loaded.")
  end

  def handle(:usage, socket) do
    metrics = Worth.Metrics.session()
    snapshots = AgentEx.LLM.UsageManager.snapshot()

    provider_section =
      if snapshots == [] do
        "Providers: (no quota endpoints)"
      else
        lines =
          Enum.map_join(snapshots, "\n", fn s ->
            credit =
              case s.credits do
                %{used: u, limit: l} -> " - credits $#{Float.round(u, 2)}/$#{Float.round(l, 2)}"
                _ -> ""
              end

            "  #{s.label}#{credit}"
          end)

        "Providers:\n#{lines}"
      end

    by_provider =
      case Map.to_list(metrics.by_provider) do
        [] ->
          ""

        entries ->
          lines =
            Enum.map_join(entries, "\n", fn {provider, p} ->
              "  #{provider}  $#{Float.round(p.cost, 4)} (#{p.calls} calls)"
            end)

          "\nBy provider:\n#{lines}"
      end

    msg =
      "#{provider_section}\nSession: $#{Float.round(metrics.cost, 4)} | #{metrics.calls} calls | #{metrics.input_tokens} in / #{metrics.output_tokens} out#{by_provider}"

    append_system(socket, String.trim(msg))
  end

  def handle({:usage, :refresh}, socket) do
    AgentEx.LLM.UsageManager.refresh()
    append_system(socket, "Usage refresh triggered.")
  end
end
