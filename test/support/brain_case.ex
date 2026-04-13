defmodule Worth.BrainCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      import Worth.BrainCase
    end
  end

  setup do
    :ok
  end
end
