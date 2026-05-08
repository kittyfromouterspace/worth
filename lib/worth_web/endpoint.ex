defmodule WorthWeb.Endpoint do
  @moduledoc """
  Phoenix endpoint for the Worth web UI.
  Uses Desktop.Endpoint for native desktop window support.
  """

  use Desktop.Endpoint, otp_app: :worth

  if System.get_env("WORTH_DESKTOP") == "1" do
    @session_options [
      store: :ets,
      key: "_worth_key",
      table: :session
    ]
  else
    @session_options [
      store: :cookie,
      key: "_worth_key",
      signing_salt: "Iefw9TRf",
      same_site: "Lax"
    ]
  end

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :worth,
    gzip: not code_reloading?,
    only: WorthWeb.static_paths(),
    raise_on_missing_only: code_reloading?

  if Mix.env() == :dev do
    plug Tidewave
  end

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options

  if System.get_env("WORTH_DESKTOP") == "1" and not code_reloading? do
    plug Desktop.Auth
  end

  plug WorthWeb.Router
end