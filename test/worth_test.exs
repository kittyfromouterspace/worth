defmodule WorthTest do
  use ExUnit.Case, async: true

  test "worth application starts" do
    assert Process.whereis(Worth.Supervisor)
    assert Process.whereis(Worth.Repo)
  end
end
