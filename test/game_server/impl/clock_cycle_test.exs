defmodule GameServer.Impl.ClockCycleTest do
  use ExUnit.Case, async: true
  alias GameServer.Impl.{Checkpoint, Game, Timer}

  test "preparation, successive jams and repeated timeouts preserve period time" do
    {game, _} = Game.start_period(Game.new("cycles"), 0)
    assert Game.snapshot(game, 60_000).period_clock_s == 1800
    {game, _} = Game.start_jam(game, 60_000)
    {game, _} = Game.end_jam(game, 70_000)
    {game, _} = Game.start_jam(game, 100_000)
    assert Game.snapshot(game, 110_000).period_clock_s == 1750
    {game, _} = Game.call_timeout(game, 110_000)
    {game, snapshot} = Game.end_timeout(game, 180_000)
    refute snapshot.period_clock_running
    assert snapshot.lineup_clock_s == 30
    assert Game.snapshot(game, 190_000).period_clock_s == 1750
    {game, _} = Game.start_jam(game, 200_000)
    {game, _} = Game.call_timeout(game, 210_000)
    {game, _} = Game.end_timeout(game, 280_000)
    {game, _} = Game.start_jam(game, 300_000)
    assert Game.snapshot(game, 310_000).period_clock_s == 1730
  end

  test "last millisecond displays one second and lineup expiry never starts a jam" do
    {game, _} = Game.start_period(Game.new("lineup"), 0)
    {before, snapshot} = Game.expire_clocks(game, 29_999)
    assert snapshot.lineup_clock_s == 1
    assert before.lineup_clock.running
    {game, snapshot} = Game.expire_clocks(game, 30_000)
    assert snapshot.lineup_clock_s == 0
    refute snapshot.lineup_clock_running
    assert snapshot.phase == :lineup
    assert {^game, ^snapshot} = Game.expire_clocks(game, 60_000)
    assert {%Game{phase: :jam_running}, _} = Game.start_jam(game, 60_000)
  end

  test "period expiry between jams blocks starts even before a tick" do
    {game, _} = Game.start_period(Game.new("period"), 0)
    game = %{game | period_clock: Timer.new(10_000)}
    {game, _} = Game.start_jam(game, 0)
    {game, _} = Game.end_jam(game, 5_000)
    refute Game.snapshot(game, 9_999).period_expired
    assert {:error, :period_expired} = Game.start_jam(game, 10_000)
    {game, snapshot} = Game.expire_clocks(game, 10_000)
    assert snapshot.period_expired
    refute snapshot.period_clock_running
    refute snapshot.lineup_clock_running
    assert snapshot.phase == :lineup
    assert {%Game{phase: :halftime}, _} = Game.end_period(game, 10_000)
  end

  test "period expiry during a jam leaves that jam available until officials end it" do
    {game, _} = Game.start_period(Game.new("last-jam"), 0)
    game = %{game | period_clock: Timer.new(10_000)}
    {game, _} = Game.start_jam(game, 0)
    {game, snapshot} = Game.expire_clocks(game, 10_000)
    assert snapshot.phase == :jam_running
    assert snapshot.jam_clock_running
    refute snapshot.period_clock_running
    {game, snapshot} = Game.expire_clocks(game, 120_000)
    assert snapshot.phase == :jam_running
    assert snapshot.jam_clock_s == 0
    refute snapshot.jam_clock_running
    {game, snapshot} = Game.end_jam(game, 121_000)
    refute snapshot.lineup_clock_running
    assert {:error, :period_expired} = Game.start_jam(game, 121_000)
    assert {%Game{phase: :halftime}, _} = Game.end_period(game, 121_000)
  end

  test "timeout expiry does not automatically end an official interruption" do
    {game, _} = Game.start_period(Game.new("timeout"), 0)
    {game, _} = Game.call_timeout(game, 0)
    {game, snapshot} = Game.expire_clocks(game, 60_000)
    assert snapshot.phase == :timeout
    refute snapshot.timeout_clock_running
    {_, snapshot} = Game.end_timeout(game, 90_000)
    refute snapshot.period_clock_running
    assert snapshot.lineup_clock_s == 30
  end

  test "intermission expires without starting period two and survives recovery" do
    {game, _} = Game.start_period(Game.new("halftime"), 0)
    {game, _} = Game.end_period(game, 10_000)
    assert Game.ticking?(game)
    assert Game.snapshot(game, 20_000).intermission_clock_s == 590
    {:ok, restored} = Checkpoint.decode(game.id, Checkpoint.encode(game, 20_000))
    assert restored.recovery_clocks == [:intermission_clock]
    refute Game.ticking?(restored)
    {game, snapshot} = Checkpoint.resume(restored, 1_000_000)
    assert snapshot.intermission_clock_running
    assert snapshot.intermission_clock_s == 590
    {game, snapshot} = Game.expire_clocks(game, 1_590_000)
    assert snapshot.intermission_clock_s == 0
    assert snapshot.phase == :halftime
    refute Game.ticking?(game)
    {game, snapshot} = Game.start_period(game, 1_600_000)
    assert snapshot.period == 2
    assert snapshot.period_clock_s == 1800
    refute snapshot.period_clock_running
    {game, _} = Game.start_jam(game, 1_610_000)
    assert Game.snapshot(game, 1_620_000).period_clock_s == 1790
    {game, snapshot} = Game.end_game(game, 1_620_000)
    assert snapshot.phase == :final
    refute Game.ticking?(game)
  end
end
