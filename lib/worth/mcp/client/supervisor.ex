defmodule Worth.Mcp.Client.Supervisor do
  @moduledoc false
  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{
      id: {__MODULE__, name},
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :temporary
    }
  end

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    transport = Keyword.fetch!(opts, :transport)
    server_name = Keyword.fetch!(opts, :server_name)
    protocol_version = Keyword.get(opts, :protocol_version, "2024-11-05")

    do_start(name, transport, server_name, protocol_version)
  end

  defp do_start(name, transport, server_name, protocol_version) do
    Hermes.Client.Supervisor.start_link(name,
      transport: transport,
      client_info: %{"name" => "worth", "version" => "0.1.0"},
      capabilities: %{"roots" => %{"listChanged" => true}},
      protocol_version: protocol_version
    )
  rescue
    e ->
      require Logger

      Logger.warning(
        "MCP supervisor start failed for #{server_name}: #{Exception.message(e)}, falling back to base client"
      )

      client_name = String.to_atom("worth_mcp_#{server_name}")

      Hermes.Client.Base.start_link(
        name: client_name,
        transport: [layer: transport_layer(transport), name: Module.concat(client_name, "Transport")],
        client_info: %{"name" => "worth", "version" => "0.1.0"},
        capabilities: %{"roots" => %{}},
        protocol_version: protocol_version
      )
  end

  defp transport_layer({:stdio, _opts}), do: Hermes.Transport.STDIO
  defp transport_layer({:streamable_http, _opts}), do: Hermes.Transport.StreamableHTTP
  defp transport_layer({:sse, _opts}), do: Hermes.Transport.SSE
end
