defmodule ScoreboardWeb.ClockCycleLiveTest do
  use ScoreboardWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias GameServer.Impl.Game
  alias GameServer.Runtime.Server

  test "operator and both clock layouts show live and recovered intermission", %{conn: conn} do
    pid = start_supervised!({Server, "intermission-ui"})
    GameServer.start_period("intermission-ui")
    GameServer.end_period("intermission-ui")
    {:ok, operator, _} = live(conn, ~p"/games/intermission-ui/operator")
    {:ok, audience, _} = live(conn, ~p"/games/intermission-ui/scoreboard?layout=full")
    {:ok, clock, _} = live(conn, ~p"/games/intermission-ui/scoreboard?layout=clock")
    assert has_element?(operator, "#operator-active-clock[data-running=true]", "10:00")

    for view <- [audience, clock] do
      assert has_element?(view, "#audience-intermission-clock[data-running=true]", "10:00")
    end

    :sys.replace_state(pid, fn state ->
      put_in(state.game.intermission_clock.accumulated, 2000)
    end)

    send(pid, :tick)
    %{game: game} = :sys.get_state(pid)
    snapshot = Game.snapshot(game, System.monotonic_time(:millisecond))
    # Synchronize the views with the same broadcast before inspecting their DOM.
    for view <- [operator, audience, clock], do: send(view.pid, {:game_update, snapshot})
    assert has_element?(operator, "#operator-active-clock", "09:58")

    for view <- [audience, clock] do
      assert has_element?(view, "#audience-intermission-clock", "09:58")
    end

    stop_supervised!(Server)
    start_supervised!({Server, "intermission-ui"})
    {:ok, recovered} = GameServer.snapshot("intermission-ui")
    for view <- [operator, audience, clock], do: send(view.pid, {:game_update, recovered})
    assert has_element?(operator, "#operator-active-clock[data-running=false]", "10:00")
    assert has_element?(operator, "#resume-recovered")

    for view <- [audience, clock] do
      assert has_element?(view, "#audience-intermission-clock[data-running=false]", "10:00")
    end

    operator |> element("#resume-recovered") |> render_click()
    assert has_element?(operator, "#operator-active-clock[data-running=true]")
  end

  test "period expiry keeps the final jam visible and provides an explicit end button", %{
    conn: conn
  } do
    pid = start_supervised!({Server, "expiry-ui"})
    GameServer.start_period("expiry-ui")
    GameServer.start_jam("expiry-ui")

    :sys.replace_state(pid, fn state ->
      %{
        state
        | game: %{state.game | period_clock: %{state.game.period_clock | accumulated: 1_800_000}}
      }
    end)

    {:ok, operator, _} = live(conn, ~p"/games/expiry-ui/operator")
    {:ok, audience, _} = live(conn, ~p"/games/expiry-ui/scoreboard?layout=clock")
    assert has_element?(audience, "#audience-jam-clock")
    assert has_element?(operator, "#period-expired-notice")
    assert has_element?(operator, "#phase-action", "End Jam")
    operator |> element("#phase-action") |> render_click()
    refute has_element?(operator, "#phase-action")
    assert has_element?(operator, "#confirm-period-end", "Confirm Period End")
    operator |> element("#confirm-period-end") |> render_click()
    assert has_element?(operator, "#phase-action", "Prepare Period 2")
    operator |> element("#phase-action") |> render_click()
    assert has_element?(operator, "#period-waiting-notice")

    assert {:ok, %{period: 2, period_clock_s: 1800, period_clock_running: false}} =
             GameServer.snapshot("expiry-ui")
  end
end
