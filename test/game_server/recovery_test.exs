defmodule GameServer.RecoveryTest do
  use Scoreboard.DataCase, async: false
  import ExUnit.CaptureLog
  alias GameServer.{EventStore, Impl.Checkpoint, Impl.Game, Runtime.Server}

  defp start_game(id), do: start_supervised!({Server, id}, id: id)

  test "creation and acknowledged scores are durable and ordered" do
    start_game("durable")
    assert {:ok, %Game{phase: :initial}, 1} = EventStore.load("durable")
    GameServer.start_period("durable")
    GameServer.start_jam("durable")
    assert {:ok, %{score_home: 4}} = GameServer.add_score("durable", :home, 4)
    assert {:ok, %Game{score_home: 4, phase: :jam_running}, 4} = EventStore.load("durable")
    assert {:error, :invalid_transition, _, _} = GameServer.start_period("durable")
    assert {:ok, _, 4} = EventStore.load("durable")
  end

  test "crash restores confirmed score, broadcasts recovery, and requires explicit resume" do
    pid = start_game("crash")
    GameServer.start_period("crash")
    GameServer.start_jam("crash")
    GameServer.add_score("crash", :away, 3)
    GameServer.subscribe("crash")
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

    assert_receive {:game_update,
                    %{score_away: 3, recovery_required: true, jam_clock_running: false}}

    assert {:error, :recovery_required} = GameServer.add_score("crash", :home, 1)

    assert {:ok, %{recovery_required: false, jam_clock_running: true}} =
             GameServer.resume_recovered("crash")

    assert {:ok, _, 5} = EventStore.load("crash")
  end

  test "another restart while awaiting recovery preserves the paused clocks" do
    start_game("twice")
    GameServer.start_period("twice")
    GameServer.start_jam("twice")
    GameServer.add_score("twice", :home, 2)
    stop_supervised!("twice")
    start_game("twice")
    assert {:ok, first} = GameServer.snapshot("twice")
    stop_supervised!("twice")
    start_game("twice")
    assert {:ok, ^first} = GameServer.snapshot("twice")
    assert first.recovery_required
  end

  test "failed SQLite write neither changes score nor publishes a successful result" do
    pid = start_game("write-failure")
    GameServer.start_period("write-failure")
    GameServer.start_jam("write-failure")
    GameServer.subscribe("write-failure")
    before = :sys.get_state(pid)

    Ecto.Adapters.SQL.query!(Repo, """
    CREATE TEMP TRIGGER reject_score BEFORE INSERT ON game_events
    WHEN NEW.action = 'score'
    BEGIN SELECT RAISE(ABORT, 'simulated storage failure'); END
    """)

    capture_log(fn ->
      assert {:error, :storage_unavailable} = GameServer.add_score("write-failure", :home, 4)
    end)

    after_failure = :sys.get_state(pid)
    assert after_failure.game == before.game
    assert after_failure.sequence == before.sequence
    refute_received {:game_update, %{score_home: 4}}
    assert {:ok, %Game{score_home: 0}, 3} = EventStore.load("write-failure")

    Ecto.Adapters.SQL.query!(Repo, "DROP TRIGGER reject_score")
    assert {:ok, %{score_home: 4}} = GameServer.add_score("write-failure", :home, 4)
    assert {:ok, %Game{score_home: 4}, 4} = EventStore.load("write-failure")
  end

  test "expired clocks are saved once and do not resume after restart" do
    pid = start_game("expiry")
    GameServer.start_period("expiry")
    GameServer.end_period("expiry")
    GameServer.subscribe("expiry")

    :sys.replace_state(pid, fn state ->
      put_in(state.game.intermission_clock.accumulated, 600_000)
    end)

    send(pid, :tick)
    assert_receive {:game_update, %{intermission_clock_s: 0, intermission_clock_running: false}}
    assert %{sequence: sequence, ticking: false} = :sys.get_state(pid)

    assert {:ok, %Game{phase: :halftime, recovery_clocks: []}, ^sequence} =
             EventStore.load("expiry")

    send(pid, :tick)
    assert %{sequence: ^sequence} = :sys.get_state(pid)
    stop_supervised!("expiry")
    start_game("expiry")

    assert {:ok, %{phase: :halftime, intermission_clock_s: 0, recovery_required: false}} =
             GameServer.snapshot("expiry")
  end

  test "failed expiration write is retried without publishing an unsaved stop" do
    pid = start_game("expiry-failure")
    GameServer.start_period("expiry-failure")
    GameServer.end_period("expiry-failure")
    GameServer.subscribe("expiry-failure")

    Ecto.Adapters.SQL.query!(Repo, """
    CREATE TEMP TRIGGER reject_expiry BEFORE INSERT ON game_events
    WHEN NEW.action = 'expire_clocks'
    BEGIN SELECT RAISE(ABORT, 'simulated storage failure'); END
    """)

    capture_log(fn ->
      :sys.replace_state(pid, fn state ->
        put_in(state.game.intermission_clock.accumulated, 600_000)
      end)

      send(pid, :tick)
      assert %{sequence: 3, game: %{intermission_clock: %{running: true}}} = :sys.get_state(pid)
    end)

    refute_received {:game_update, %{intermission_clock_running: false}}

    assert {:ok, %Game{recovery_clocks: [:intermission_clock]}, 3} =
             EventStore.load("expiry-failure")

    Ecto.Adapters.SQL.query!(Repo, "DROP TRIGGER reject_expiry")
    send(pid, :tick)
    assert_receive {:game_update, %{intermission_clock_running: false, intermission_clock_s: 0}}
    assert {:ok, %Game{recovery_clocks: []}, 4} = EventStore.load("expiry-failure")
  end

  test "intermission continues broadcasting after recovery is confirmed" do
    start_game("half-recovery")
    GameServer.start_period("half-recovery")
    GameServer.end_period("half-recovery")
    stop_supervised!("half-recovery")
    pid = start_game("half-recovery")

    assert {:ok, %{intermission_clock_running: false, recovery_required: true}} =
             GameServer.snapshot("half-recovery")

    assert {:ok, %{intermission_clock_running: true}} =
             GameServer.resume_recovered("half-recovery")

    assert %{ticking: true} = :sys.get_state(pid)
    GameServer.subscribe("half-recovery")

    :sys.replace_state(pid, fn state ->
      put_in(state.game.intermission_clock.accumulated, 2000)
    end)

    send(pid, :tick)
    assert_receive {:game_update, %{phase: :halftime, intermission_clock_s: seconds}}
    assert seconds <= 598
  end

  test "duplicate sequence cannot overwrite a saved action" do
    game = Game.new("duplicate")
    assert {:ok, _} = EventStore.append(game, 1, "create", %{}, 0)
    assert {:error, _} = EventStore.append(%{game | score_home: 99}, 1, "score", %{}, 0)
    assert {:ok, %Game{score_home: 0}, 1} = EventStore.load("duplicate")
  end

  test "invalid or unsupported journal is refused without creating a replacement match" do
    state = Checkpoint.encode(Game.new("invalid"), 0)
    event = %{game_id: "invalid", sequence: 1, action: "create", version: 1, state: state}
    assert {:error, :invalid_journal} = EventStore.replay("invalid", [%{event | version: 2}])

    assert {:error, :invalid_journal} =
             EventStore.replay("invalid", [event, %{event | sequence: 3}])

    assert {:error, :invalid_journal} = EventStore.replay("invalid", [event, event])
    assert {:error, :invalid_journal} = EventStore.replay("invalid", [%{event | state: %{}}])
    Scoreboard.Derby.append_game_event!(Map.put(event, :version, 2))

    assert {:error, {{:recovery_failed, :invalid_journal}, _child}} =
             start_supervised({Server, "invalid"})

    assert [] = Registry.lookup(GameRegistry, "invalid")
  end

  test "unknown saved ID cannot be restored as a new match" do
    assert {:error, :not_found} = GameServer.restore_game("missing")
    assert {:ok, nil, 0} = EventStore.load("missing")
  end
end
