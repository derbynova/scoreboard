defmodule ScoreboardWeb.ClockCorrectionTest do
  use ScoreboardWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog
  alias GameServer.Runtime.Server

  setup do
    id = "live-clock-correction"
    start_supervised!({Server, id})
    %{id: id}
  end

  test "preview, save, public sync and history survive reopening", %{conn: conn, id: id} do
    GameServer.start_period(id)
    GameServer.start_jam(id)
    stop_supervised!(Server)
    start_supervised!({Server, id})
    {:ok, view, _} = live(conn, ~p"/games/#{id}/operator")
    {:ok, audience, _} = live(conn, ~p"/games/#{id}/scoreboard")
    view |> element("#edit-jam_clock") |> render_click()
    assert has_element?(view, "#resume-recovered[disabled]")

    view
    |> form("#clock-correction-form", correction: %{minutes: "1", seconds: "15"})
    |> render_change()

    assert has_element?(view, "#clock-correction-preview", "01:15")
    assert has_element?(view, "#clock-correction-preview", "Stays paused")
    render_hook(view, "keydown", %{"key" => "1", "code" => "Digit1"})
    assert {:ok, %{score_home: 0}} = GameServer.snapshot(id)

    view
    |> form("#clock-correction-form", correction: %{minutes: "1", seconds: "15"})
    |> render_submit()

    refute has_element?(view, "#clock-correction-form")
    assert has_element?(view, "#clock-history-entries article", "01:15.000")
    assert has_element?(audience, "#audience-recovery-notice")
    assert has_element?(audience, "#audience-jam-clock", "01:15")
    assert has_element?(view, "#edit-jam_clock", "01:15")

    assert {:ok, %{jam_clock_s: 75, jam_clock_running: false, recovery_required: true}} =
             GameServer.snapshot(id)

    {:ok, reopened, _} = live(conn, ~p"/games/#{id}/operator")
    assert has_element?(reopened, "#clock-history-entries article", "01:15.000")
    reopened |> element("#resume-recovered") |> render_click()
    assert {:ok, %{jam_clock_running: true}} = GameServer.snapshot(id)
  end

  test "invalid time is rejected and cancel preserves the clock", %{conn: conn, id: id} do
    {:ok, view, _} = live(conn, ~p"/games/#{id}/operator")
    view |> element("#edit-period_clock") |> render_click()
    # Send past the browser's HTML bounds to exercise server-side validation.
    render_submit(view, "save_clock", %{"correction" => %{"minutes" => "30", "seconds" => "1"}})
    assert has_element?(view, "#save-clock-correction[disabled]")
    assert has_element?(view, "#clock-correction-form", "must fit within")
    render_submit(view, "save_clock", %{"correction" => %{"minutes" => "bad", "seconds" => "0"}})
    assert has_element?(view, "#save-clock-correction[disabled]")
    view |> element("#cancel-clock-correction") |> render_click()
    refute has_element?(view, "#clock-correction-form")
    assert {:ok, %{period_clock_s: 1800}} = GameServer.snapshot(id)
    assert {:ok, [], nil} = GameServer.EventStore.list_clock_corrections(id)
  end

  test "typing shortcuts while editing cannot score or change phase", %{conn: conn, id: id} do
    GameServer.start_period(id)
    GameServer.start_jam(id)
    {:ok, view, _} = live(conn, ~p"/games/#{id}/operator")
    view |> element("#edit-jam_clock") |> render_click()

    for {key, code} <- [{"1", "Digit1"}, {" ", "Space"}, {"t", "KeyT"}, {"e", "KeyE"}] do
      render_hook(view, "keydown", %{"key" => key, "code" => code})
    end

    assert {:ok, %{phase: :jam_running, score_home: 0}} = GameServer.snapshot(id)

    view
    |> form("#clock-correction-form", correction: %{minutes: "1", seconds: "0"})
    |> render_change()

    assert has_element?(view, "#clock-correction-preview", "Keeps running")

    view
    |> form("#clock-correction-form", correction: %{minutes: "1", seconds: "0"})
    |> render_submit()

    assert {:ok, %{jam_clock_s: 60, jam_clock_running: true}} = GameServer.snapshot(id)
  end

  test "concurrent correction is visible but cannot be silently overwritten", %{
    conn: conn,
    id: id
  } do
    {:ok, view, _} = live(conn, ~p"/games/#{id}/operator")
    view |> element("#edit-period_clock") |> render_click()
    GameServer.correct_clock(id, :period_clock, 1_700_000)
    assert has_element?(view, "#clock-history-entries article")

    view
    |> form("#clock-correction-form", correction: %{minutes: "20", seconds: "0"})
    |> render_submit()

    assert has_element?(view, "#flash-error", "state changed")
    assert {:ok, %{period_clock_s: 1700}} = GameServer.snapshot(id)
  end

  test "failed write keeps form open and exposes retry without publishing correction", %{
    conn: conn,
    id: id
  } do
    {:ok, view, _} = live(conn, ~p"/games/#{id}/operator")
    view |> element("#edit-period_clock") |> render_click()

    Ecto.Adapters.SQL.query!(Scoreboard.Repo, """
    CREATE TEMP TRIGGER reject_live_correction BEFORE INSERT ON game_events
    WHEN NEW.action = 'correct_clock'
    BEGIN SELECT RAISE(ABORT, 'simulated storage failure'); END
    """)

    capture_log(fn ->
      view
      |> form("#clock-correction-form", correction: %{minutes: "20", seconds: "0"})
      |> render_submit()
    end)

    assert has_element?(view, "#flash-error", "Action not saved")
    assert has_element?(view, "#clock-correction-form")
    refute has_element?(view, "#clock-history-entries article")
    Ecto.Adapters.SQL.query!(Scoreboard.Repo, "DROP TRIGGER reject_live_correction")

    view
    |> form("#clock-correction-form", correction: %{minutes: "20", seconds: "0"})
    |> render_submit()

    refute has_element?(view, "#clock-correction-form")
    assert has_element?(view, "#clock-history-entries article", "20:00.000")
  end

  test "older history can be loaded without mixing matches", %{conn: conn, id: id} do
    for seconds <- 1..22, do: GameServer.correct_clock(id, :jam_clock, seconds * 1000)
    {:ok, view, _} = live(conn, ~p"/games/#{id}/operator")
    assert has_element?(view, "#more-clock-history")
    refute has_element?(view, "#clock-history-entries article", "→ 00:01.000")
    view |> element("#more-clock-history") |> render_click()
    assert has_element?(view, "#clock-history-entries article", "→ 00:01.000")
    refute has_element?(view, "#more-clock-history")
  end
end
