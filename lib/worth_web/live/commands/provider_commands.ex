defmodule WorthWeb.Commands.ProviderCommands do
  @moduledoc false
  import WorthWeb.Commands.Helpers

  alias Agentic.LLM.Catalog
  alias Agentic.LLM.ProviderRegistry
  alias Agentic.LLM.UsageManager

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
    # Phase 6: open the Subscription & Usage dashboard.
    # The previous text dump is preserved as `/usage text`.
    usage_view = Worth.LLM.UsageSummary.build()

    socket
    |> Phoenix.Component.assign(view: :usage, usage_view: usage_view)
  end

  def handle({:usage, :refresh}, socket) do
    UsageManager.refresh()
    Agentic.LLM.Catalog.refresh()
    usage_view = Worth.LLM.UsageSummary.build()

    socket
    |> Phoenix.Component.assign(usage_view: usage_view)
    |> append_system("Usage refresh triggered.")
  end
end
