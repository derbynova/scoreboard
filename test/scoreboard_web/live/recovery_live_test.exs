defmodule ScoreboardWeb.RecoveryLiveTest do
  use ScoreboardWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog
  alias GameServer.Runtime.Server

  test "operator sees recovery and explicitly resumes saved clocks", %{conn: conn} do
    id = "live-recovery"
    start_supervised!({Server, id})
    GameServer.start_period(id)
    GameServer.start_jam(id)
    GameServer.add_score(id, :home, 4)
    stop_supervised!(Server)
    start_supervised!({Server, id})

    {:ok, view, _} = live(conn, ~p"/games/#{id}/operator")
    assert has_element?(view, "#recovery-notice")
    assert has_element?(view, "#score-home", "4")
    refute has_element?(view, "button[phx-click=start_jam]")
    view |> element("#resume-recovered") |> render_click()
    refute has_element?(view, "#recovery-notice")
    assert {:ok, %{recovery_required: false, jam_clock_running: true}} = GameServer.snapshot(id)
  end

  test "public view indicates that recovered clocks are paused", %{conn: conn} do
    id = "audience-recovery"
    start_supervised!({Server, id})
    GameServer.start_period(id)
    stop_supervised!(Server)
    start_supervised!({Server, id})
    {:ok, view, _} = live(conn, ~p"/games/#{id}/scoreboard")
    assert has_element?(view, "#audience-recovery-notice")
  end

  test "failed score write is visible for both clicks and keyboard commands", %{conn: conn} do
    id = "live-storage-error"
    start_supervised!({Server, id})
    GameServer.start_period(id)
    GameServer.start_jam(id)
    {:ok, view, _} = live(conn, ~p"/games/#{id}/operator")

    Ecto.Adapters.SQL.query!(Scoreboard.Repo, """
    CREATE TEMP TRIGGER reject_live_score BEFORE INSERT ON game_events
    WHEN NEW.action = 'score'
    BEGIN SELECT RAISE(ABORT, 'simulated storage failure'); END
    """)

    capture_log(fn ->
      view
      |> element("button[phx-click=score][phx-value-team=home][phx-value-points='1']")
      |> render_click()

      assert has_element?(view, "#flash-error", "Action not saved")
      render_hook(view, "keydown", %{"key" => "1", "code" => "Digit1"})
      assert has_element?(view, "#flash-error", "Action not saved")
    end)

    assert {:ok, %{score_home: 0}} = GameServer.snapshot(id)
    Ecto.Adapters.SQL.query!(Scoreboard.Repo, "DROP TRIGGER reject_live_score")
  end
end
