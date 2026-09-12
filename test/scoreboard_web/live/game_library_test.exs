defmodule ScoreboardWeb.GameLibraryTest do
  use ScoreboardWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias GameServer.{EventStore, Impl.Game}

  setup do
    on_exit(&Scoreboard.GameTestHelpers.cleanup_game_processes/0)
    :ok
  end

  test "home and legacy new-game URL provide creation and joining", %{conn: conn} do
    for path <- [~p"/", ~p"/games/new"] do
      {:ok, view, _} = live(conn, path)
      assert has_element?(view, "#new-game")
      assert has_element?(view, "#join-game-form")
      assert has_element?(view, "#no-saved-games")
    end
  end

  test "resume opens an existing saved match and waits for clock confirmation", %{conn: conn} do
    game = Game.new("library-resume")
    EventStore.append(game, 1, "create", %{}, 0)
    {game, _} = Game.start_period(game, 0)
    EventStore.append(game, 2, "start_period", %{}, 1000)
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#games-library-resume")
    assert [] == Registry.lookup(GameRegistry, game.id)

    {:ok, operator, _} =
      view |> element("#resume-library-resume") |> render_click() |> follow_redirect(conn)

    assert has_element?(operator, "#recovery-notice")

    assert {:ok, %{recovery_required: true, period_clock_running: false}} =
             GameServer.snapshot(game.id)
  end

  test "finished summary and public display do not start a runtime", %{conn: conn} do
    game = %{Game.new("finished") | phase: :final, period: 2, score_home: 123, score_away: 98}
    EventStore.append(game, 1, "create", %{}, 0)
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#summary-finished", "123")
    refute has_element?(view, "#resume-finished")
    {:ok, audience, _} = live(conn, ~p"/games/finished/scoreboard")
    assert has_element?(audience, "#audience-score-home", "123")
    refute has_element?(audience, "#audience-recovery-notice")
    assert [] == Registry.lookup(GameRegistry, "finished")
  end

  test "older matches can be loaded and refresh resets pagination", %{conn: conn} do
    for number <- 1..21 do
      EventStore.append(Game.new("page-#{number}"), 1, "create", %{}, 0)
    end

    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "#load-more-games")
    view |> element("#load-more-games") |> render_click()
    refute has_element?(view, "#load-more-games")
    assert has_element?(view, "#games-page-1")
    view |> element("#refresh-games") |> render_click()
    assert has_element?(view, "#load-more-games")
    refute has_element?(view, "#games-page-1")
  end

  test "join trims the ID and supports saved matches without starting them", %{conn: conn} do
    EventStore.append(Game.new("join-saved"), 1, "create", %{}, 0)
    {:ok, view, _} = live(conn, ~p"/")

    assert {:error, {:live_redirect, %{to: "/games/join-saved/scoreboard"}}} =
             view |> form("#join-game-form", game_id: " join-saved ") |> render_submit()

    assert [] == Registry.lookup(GameRegistry, "join-saved")
  end
end
