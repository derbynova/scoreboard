defmodule GameServer.Impl.ClockCorrectionTest do
  use ExUnit.Case, async: true
  alias GameServer.Impl.{Checkpoint, Game, Timer}

  test "each stopped clock can be set to zero or its duration without changing configuration" do
    game = Game.new("bounds")

    for {clock, details} <- Game.clock_details(game, 0), value <- [0, details.duration_ms] do
      {corrected, _} = Game.correct_clock(game, clock, value, 5000)
      timer = Map.fetch!(corrected, clock)
      assert Timer.remaining(timer, 100_000) == value
      assert timer.duration == details.duration_ms
      refute timer.running
      assert corrected.phase == :initial
    end
  end

  test "invalid names, types and out-of-range values return errors" do
    game = Game.new("invalid")

    for value <- [-1, 1_800_001, 1.5, "1000", nil] do
      assert {:error, :invalid_clock_time} = Game.correct_clock(game, :period_clock, value, 0)
    end

    assert {:error, :invalid_clock_time} = Game.correct_clock(game, :unknown, 0, 0)
    assert {:error, :invalid_clock_time} = Game.correct_clock(game, "period_clock", 0, 0)
  end

  test "running correction reanchors at acceptance without touching another clock" do
    {game, _} = Game.start_period(Game.new("live"), 0)
    {game, _} = Game.start_jam(game, 0)
    context = Game.snapshot(game, 5000).clocks.jam_clock.context
    {corrected, snapshot} = Game.correct_clock(game, :jam_clock, 90_000, 10_000, context)
    assert snapshot.jam_clock_s == 90
    assert snapshot.jam_clock_running
    assert corrected.period_clock == game.period_clock
    assert Game.snapshot(corrected, 11_000).jam_clock_s == 89
    assert corrected.jam_clock.duration == 120_000
    assert corrected.jam_number == 1
  end

  test "zero stops a running jam without ending it, with exact millisecond boundary" do
    {game, _} = Game.start_period(Game.new("zero"), 0)
    {game, _} = Game.start_jam(game, 0)
    {game, _} = Game.correct_clock(game, :jam_clock, 1, 100)
    assert Game.snapshot(game, 100).jam_clock_s == 1
    {game, snapshot} = Game.expire_clocks(game, 101)
    assert snapshot.jam_clock_s == 0
    refute snapshot.jam_clock_running
    assert game.phase == :jam_running
  end

  test "period correction to zero stops lineup and preserves the phase" do
    {game, _} = Game.start_period(Game.new("period-zero"), 0)
    {game, snapshot} = Game.correct_clock(game, :period_clock, 0, 5000)
    refute snapshot.lineup_clock_running
    assert game.phase == :lineup
    assert {:error, :period_expired} = Game.start_jam(game, 5000)
  end

  test "repeated checkpoint recovery retains corrected values and original resume intentions" do
    {game, _} = Game.start_period(Game.new("recover"), 0)
    {game, _} = Game.start_jam(game, 0)
    {:ok, game} = Checkpoint.decode(game.id, Checkpoint.encode(game, 12_000))
    {game, _} = Game.correct_clock(game, :period_clock, 1_700_000, 1_000_000)
    {game, _} = Game.correct_clock(game, :jam_clock, 0, 1_000_000)
    {game, _} = Game.correct_clock(game, :timeout_clock, 45_000, 1_000_000)
    intentions = game.recovery_clocks
    assert :jam_clock in intentions
    assert :period_clock in intentions
    refute :timeout_clock in intentions
    refute Game.ticking?(game)
    {:ok, again} = Checkpoint.decode(game.id, Checkpoint.encode(game, 2_000_000))
    assert again == game
    {resumed, snapshot} = Checkpoint.resume(again, 3_000_000)
    assert snapshot.period_clock_running
    refute snapshot.jam_clock_running
    refute snapshot.timeout_clock_running
    refute snapshot.recovery_required
    assert Game.snapshot(resumed, 3_001_000).period_clock_s == 1699
    assert Game.snapshot(resumed, 3_001_000).timeout_clock_s == 45
  end

  test "stale editor is rejected after transitions, competing corrections or expiry before tick" do
    {game, _} = Game.start_period(Game.new("stale"), 0)
    {game, _} = Game.start_jam(game, 0)
    context = Game.snapshot(game, 1000).clocks.jam_clock.context
    {ended, _} = Game.end_jam(game, 1000)
    {corrected, _} = Game.correct_clock(game, :jam_clock, 50_000, 1000)

    for {changed, now} <- [{ended, 1000}, {corrected, 1000}, {game, 120_000}] do
      assert {:error, :clock_changed} =
               Game.correct_clock(changed, :jam_clock, 60_000, now, context)
    end
  end

  test "expired clock corrected without a preview does not implicitly restart" do
    {game, _} = Game.start_period(Game.new("expired"), 0)
    {game, _} = Game.start_jam(game, 0)
    {game, snapshot} = Game.correct_clock(game, :jam_clock, 60_000, 120_000)
    refute snapshot.jam_clock_running
    assert Game.snapshot(game, 130_000).jam_clock_s == 60
  end

  test "resetting a running clock to the same value invalidates an earlier preview" do
    {game, _} = Game.start_period(Game.new("same-value"), 0)
    {game, _} = Game.start_jam(game, 0)
    context = Game.snapshot(game, 1000).clocks.jam_clock.context
    {game, _} = Game.correct_clock(game, :jam_clock, 120_000, 2000)

    assert {:error, :clock_changed} =
             Game.correct_clock(game, :jam_clock, 60_000, 3000, context)
  end

  test "intermission correction remains in halftime and ticks from the new value" do
    {game, _} = Game.start_period(Game.new("half"), 0)
    {game, _} = Game.end_period(game, 0)
    {game, _} = Game.correct_clock(game, :intermission_clock, 300_000, 1000)
    assert Game.snapshot(game, 2000).intermission_clock_s == 299
    assert game.phase == :halftime
  end
end
