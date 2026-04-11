import Config

if System.get_env("PHX_SERVER") do
  config :worth, WorthWeb.Endpoint, server: true
end

desktop_mode = System.get_env("WORTH_DESKTOP") == "1"
port = String.to_integer(System.get_env("PORT", "4090"))

if desktop_mode do
  config :worth, WorthWeb.Endpoint,
    http: [
      ip: {127, 0, 0, 1},
      port: port
    ]
else
  config :worth, WorthWeb.Endpoint, http: [port: port]
end

if config_env() == :prod do
  if desktop_mode do
    secret_key_base =
      System.get_env("SECRET_KEY_BASE") ||
        :crypto.strong_rand_bytes(48) |> Base.encode64(padding: false)

    config :worth, WorthWeb.Endpoint,
      url: [host: "localhost", port: port, scheme: "http"],
      http: [
        ip: {127, 0, 0, 1},
        port: port
      ],
      secret_key_base: secret_key_base,
      server: true
  else
    secret_key_base =
      System.get_env("SECRET_KEY_BASE") ||
        raise("""
        environment variable SECRET_KEY_BASE is missing.
        You can generate one by calling: mix phx.gen.secret
        """)

    host = System.get_env("PHX_HOST") || "example.com"

    config :worth, WorthWeb.Endpoint,
      url: [host: host, port: 443, scheme: "https"],
      http: [
        ip: {0, 0, 0, 0, 0, 0, 0, 0}
      ],
      secret_key_base: secret_key_base
  end
end
