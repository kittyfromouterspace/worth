import Config

if System.get_env("PHX_SERVER") do
  config :worth, WorthWeb.Endpoint, server: true
end

desktop_mode = System.get_env("WORTH_DESKTOP") == "1"
port = String.to_integer(System.get_env("PORT", "4090"))

# --- Resolve data directory at runtime ---
# This MUST happen at runtime so that Path.expand("~") resolves to the
# *current* user's home rather than the build machine's home (e.g. /home/runner).
worth_data =
  case :os.type() do
    {:unix, :darwin} -> Path.expand("~/Library/Application Support/worth")
    {:win32, _} -> "LOCALAPPDATA" |> System.get_env(Path.expand("~/.local/share")) |> Path.join("worth")
    {:unix, _} -> "XDG_DATA_HOME" |> System.get_env(Path.expand("~/.local/share")) |> Path.join("worth")
  end

config :agent_ex, catalog: [persist_path: Path.join(worth_data, "catalog.json")]

scheme = if desktop_mode, do: "http", else: System.get_env("PHX_SCHEME", "http")
host = if desktop_mode, do: "localhost", else: System.get_env("PHX_HOST", "localhost")
gateway_base = "#{scheme}://#{host}:#{port}"
config :agent_ex, :llm_gateway_base_url, gateway_base

config :worth, Worth.Metrics.Repo, database: Path.join(worth_data, "metrics.db")
config :worth, Worth.Repo, database: Path.join(worth_data, "worth.db")

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
        48 |> :crypto.strong_rand_bytes() |> Base.encode64(padding: false)

    config :worth, WorthWeb.Endpoint,
      url: [host: "127.0.0.1", port: port, scheme: "http"],
      http: [
        ip: {127, 0, 0, 1},
        port: port
      ],
      check_origin: false,
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
