defmodule GameServer.ClockCorrectionTest do
  use Scoreboard.DataCase, async: false
  import ExUnit.CaptureLog
  alias GameServer.{EventStore, Runtime.Server}

  setup do
    id = "correction"
    pid = start_supervised!({Server, id})
    %{id: id, pid: pid}
  end

  test "correction before resume survives another restart and has a durable audit", %{id: id} do
    GameServer.start_period(id)
    GameServer.start_jam(id)
    stop_supervised!(Server)
    start_supervised!({Server, id})
    GameServer.subscribe(id)

    assert {:ok, %{jam_clock_s: 75, recovery_required: true, jam_clock_running: false}} =
             GameServer.correct_clock(id, :jam_clock, 75_000)

    assert_receive {:clock_corrected, event}
    assert event.payload["after_ms"] == 75_000
    assert event.payload["resume_on_confirmation"]
    assert event.payload["phase"] == "jam_running"
    assert event.payload["period"] == 1
    assert event.payload["jam_number"] == 1
    assert {:ok, [saved], nil} = EventStore.list_clock_corrections(id)
    assert saved.id == event.id
    assert {:ok, first} = GameServer.snapshot(id)
    stop_supervised!(Server)
    start_supervised!({Server, id})
    assert {:ok, ^first} = GameServer.snapshot(id)

    assert {:ok, %{jam_clock_running: true, recovery_required: false}} =
             GameServer.resume_recovered(id)

    stop_supervised!(Server)
    start_supervised!({Server, id})
    assert {:ok, %{jam_clock_s: 75, recovery_required: true}} = GameServer.snapshot(id)
  end

  test "SQLite rejection preserves state and history and permits retry", %{id: id, pid: pid} do
    GameServer.subscribe(id)
    before = :sys.get_state(pid)

    Ecto.Adapters.SQL.query!(Repo, """
    CREATE TEMP TRIGGER reject_correction BEFORE INSERT ON game_events
    WHEN NEW.action = 'correct_clock'
    BEGIN SELECT RAISE(ABORT, 'simulated storage failure'); END
    """)

    capture_log(fn ->
      assert {:error, :storage_unavailable} =
               GameServer.correct_clock(id, :period_clock, 1_700_000)
    end)

    assert :sys.get_state(pid) == before
    refute_received {:clock_corrected, _}
    refute_received {:game_update, _}
    assert {:ok, [], nil} = EventStore.list_clock_corrections(id)
    Ecto.Adapters.SQL.query!(Repo, "DROP TRIGGER reject_correction")
    assert {:ok, %{period_clock_s: 1700}} = GameServer.correct_clock(id, :period_clock, 1_700_000)
    assert {:ok, [_], nil} = EventStore.list_clock_corrections(id)
  end

  test "invalid correction does not write or crash and history is paginated by match", %{
    id: id,
    pid: pid
  } do
    assert {:error, :invalid_clock_time} = GameServer.correct_clock(id, :bad, 50)
    assert %{sequence: 1} = :sys.get_state(pid)

    for seconds <- 1..22 do
      assert {:ok, _} = GameServer.correct_clock(id, :jam_clock, seconds * 1000)
    end

    assert {:ok, page, cursor} = EventStore.list_clock_corrections(id)
    assert length(page) == 20
    assert Enum.map(page, & &1.sequence) == Enum.to_list(23..4//-1)
    assert {:ok, older, nil} = EventStore.list_clock_corrections(id, cursor)
    assert Enum.map(older, & &1.sequence) == [3, 2]
    assert {:ok, [], nil} = EventStore.list_clock_corrections("another-match")
    assert {:ok, %{jam_clock: %{accumulated: 98_000}}, 23} = EventStore.load(id)
  end
end
