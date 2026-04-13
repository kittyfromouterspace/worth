defmodule Worth.DataCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import Ecto.Query

      alias Worth.Repo
    end
  end

  setup tags do
    Worth.DataCase.setup_sandbox(tags)
    :ok
  end

  def setup_sandbox(tags) do
    pid = Sandbox.start_owner!(Worth.Repo, shared: not tags[:async])

    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end
end
