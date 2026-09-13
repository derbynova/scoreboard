defmodule GameServer.Impl.CheckpointTest do
  use ExUnit.Case, async: true
  alias GameServer.Impl.{Checkpoint, Game}

  test "clock state survives a new VM time origin without counting downtime" do
    {game, _} = Game.start_period(Game.new("portable"), -500_000)
    {game, _} = Game.start_jam(game, -495_000)
    saved = Checkpoint.encode(game, -490_000)
    assert {:ok, restored} = Checkpoint.decode("portable", saved)
    assert restored.period_clock.started_at == nil
    assert Game.snapshot(restored, 9_000_000).jam_clock_s == 115
    assert Game.snapshot(restored, 99_000_000).jam_clock_s == 115
    {resumed, snapshot} = Checkpoint.resume(restored, 99_000_000)
    refute snapshot.recovery_required
    assert Game.snapshot(resumed, 99_002_000).jam_clock_s == 113
  end

  test "restoring an already paused recovery preserves which clocks must resume" do
    {game, _} = Game.start_period(Game.new("paused"), 0)
    {:ok, restored} = Checkpoint.decode("paused", Checkpoint.encode(game, 1000))
    {:ok, twice} = Checkpoint.decode("paused", Checkpoint.encode(restored, 1_000_000))
    assert twice == restored
  end

  test "the original checkpoint shape remains readable, including expired running clocks" do
    saved = %{
      "phase" => "halftime",
      "period" => 1,
      "jam_number" => 4,
      "score_home" => 12,
      "score_away" => 9,
      "clocks" => %{
        "period_clock" => %{"duration" => 1_800_000, "elapsed" => 1_800_000, "running" => false},
        "jam_clock" => %{"duration" => 120_000, "elapsed" => 120_000, "running" => false},
        "lineup_clock" => %{"duration" => 30_000, "elapsed" => 0, "running" => false},
        "timeout_clock" => %{"duration" => 60_000, "elapsed" => 0, "running" => false},
        "intermission_clock" => %{"duration" => 600_000, "elapsed" => 601_000, "running" => true}
      }
    }

    assert {:ok, restored} = Checkpoint.decode("legacy", saved)
    assert restored.recovery_clocks == [:intermission_clock]
    {game, snapshot} = Checkpoint.resume(restored, 5_000_000)
    assert snapshot.phase == :halftime
    assert snapshot.score_home == 12
    assert snapshot.intermission_clock_s == 0
    refute snapshot.intermission_clock_running
    refute snapshot.recovery_required
    refute Game.ticking?(game)
  end

  test "malformed timers and phases are rejected" do
    saved = Checkpoint.encode(Game.new("invalid"), 0)

    assert {:error, :invalid_checkpoint} =
             Checkpoint.decode("invalid", put_in(saved, ["clocks", "jam_clock", "elapsed"], -1))

    assert {:error, :invalid_checkpoint} =
             Checkpoint.decode("invalid", %{saved | "phase" => "unknown"})

    assert {:error, :invalid_checkpoint} = Checkpoint.decode("invalid", %{})
  end
end
