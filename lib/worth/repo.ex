defmodule Worth.Repo do
  use Ecto.Repo,
    otp_app: :worth,
    adapter: Ecto.Adapters.Postgres,
    types: Worth.PostgrexTypes

  def installed_extensions do
    ["vector", "pg_trgm"]
  end
end
