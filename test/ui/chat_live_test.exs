defmodule WorthWeb.ChatLiveTest do
  use WorthWeb.ConnCase, async: true

  test "renders the chat page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "Worth"
  end
end
