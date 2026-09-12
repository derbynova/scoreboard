defmodule ScoreboardWeb.HomeLiveTest do
  use ScoreboardWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  test "GET /", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#game-library")
    assert has_element?(view, "#new-game")
  end
end
