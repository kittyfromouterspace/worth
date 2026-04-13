defmodule WorthWeb.Commands.ProviderCommands do
  @moduledoc false
  import WorthWeb.Commands.Helpers

  alias AgentEx.LLM.Catalog
  alias AgentEx.LLM.ProviderRegistry
  alias AgentEx.LLM.UsageManager

  def handle({:provider, :list}, socket) do
    providers = ProviderRegistry.list()

    if providers == [] do
      append_system(socket, "No providers registered.")
    else
      lines =
        Enum.map_join(providers, "\n", fn p ->
          status = if p.status == :enabled, do: "enabled", else: "disabled"

          models =
            try do
              length(p.module.default_models())
            rescue
              _ -> "?"
            end

          "  [#{status}] #{p.module.label()} (#{p.id}) - #{models} models"
        end)

      append_system(socket, "Providers:\n#{lines}")
    end
  end

  def handle({:provider, {:enable, id}}, socket) do
    case ProviderRegistry.enable(id) do
      :ok -> append_system(socket, "Provider #{id} enabled.")
      {:error, :not_found} -> append_error(socket, "Provider '#{id}' not found.")
    end
  end

  def handle({:provider, {:disable, id}}, socket) do
    case ProviderRegistry.disable(id) do
      :ok -> append_system(socket, "Provider #{id} disabled.")
      {:error, :not_found} -> append_error(socket, "Provider '#{id}' not found.")
    end
  end

  def handle({:catalog, :refresh}, socket) do
    Catalog.refresh()
    info = Catalog.info()
    append_system(socket, "Catalog refresh triggered. #{info.model_count} models loaded.")
  end

  def handle(:usage, socket) do
    metrics = Worth.Metrics.session()
    snapshots = UsageManager.snapshot()

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
    UsageManager.refresh()
    append_system(socket, "Usage refresh triggered.")
  end
end
