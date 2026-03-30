defmodule GameServer.Impl.GameTest do
  use ExUnit.Case, async: true

  alias GameServer.Impl.Game

  describe "new/1" do
    test "creates a game in initial state" do
      game = Game.new("game-1")
      assert game.id == "game-1"
      assert game.phase == :initial
      assert game.period == 0
      assert game.jam_number == 0
      assert game.score_home == 0
      assert game.score_away == 0
    end
  end

  describe "start_period/2" do
    test "transitions from :initial to :lineup, period 1" do
      game = Game.new("g1")
      {updated, snap} = Game.start_period(game, 0)

      assert updated.phase == :lineup
      assert updated.period == 1
      assert snap.phase == :lineup
      assert snap.period == 1
    end

    test "transitions from :halftime to :lineup, period 2" do
      game = in_halftime("g1")

      {updated, snap} = Game.start_period(game, 2_400_000)
      assert updated.phase == :lineup
      assert updated.period == 2
      assert snap.period == 2
    end

    test "error when already in lineup" do
      game = in_lineup("g1")

      assert {:error, :invalid_transition, :start_period, :lineup} =
               Game.start_period(game, 0)
    end

    test "error when in jam_running" do
      game = in_jam("g1")

      assert {:error, :invalid_transition, :start_period, :jam_running} =
               Game.start_period(game, 0)
    end
  end

  describe "start_jam/2" do
    test "transitions from :lineup to :jam_running, increments jam" do
      game = in_lineup("g1")

      {updated, snap} = Game.start_jam(game, 1000)
      assert updated.phase == :jam_running
      assert updated.jam_number == 1
      assert snap.jam_number == 1
    end

    test "error when not in lineup" do
      game = Game.new("g1")

      assert {:error, :invalid_transition, :start_jam, :initial} =
               Game.start_jam(game, 0)
    end
  end

  describe "end_jam/2" do
    test "transitions from :jam_running to :lineup" do
      game = in_jam("g1")

      {updated, snap} = Game.end_jam(game, 10_000)
      assert updated.phase == :lineup
      assert snap.phase == :lineup
    end

    test "error when not in jam_running" do
      game = Game.new("g1")

      assert {:error, :invalid_transition, :end_jam, :initial} =
               Game.end_jam(game, 0)
    end
  end

  describe "call_timeout/2" do
    test "transitions from :jam_running to :timeout" do
      game = in_jam("g1")

      {updated, snap} = Game.call_timeout(game, 5000)
      assert updated.phase == :timeout
      assert snap.phase == :timeout
    end

    test "transitions from :lineup to :timeout" do
      game = in_lineup("g1")

      {updated, snap} = Game.call_timeout(game, 5000)
      assert updated.phase == :timeout
      assert snap.phase == :timeout
    end

    test "error when in :initial" do
      game = Game.new("g1")

      assert {:error, :invalid_transition, :call_timeout, :initial} =
               Game.call_timeout(game, 0)
    end

    test "error when already in timeout" do
      game = in_timeout("g1")

      assert {:error, :invalid_transition, :call_timeout, :timeout} =
               Game.call_timeout(game, 0)
    end
  end

  describe "end_timeout/2" do
    test "transitions from :timeout to :lineup" do
      game = in_timeout("g1")

      {updated, snap} = Game.end_timeout(game, 65_000)
      assert updated.phase == :lineup
      assert snap.phase == :lineup
    end

    test "error when not in timeout" do
      game = Game.new("g1")

      assert {:error, :invalid_transition, :end_timeout, :initial} =
               Game.end_timeout(game, 0)
    end
  end

  describe "end_period/2" do
    test "transitions from :jam_running to :halftime in period 1" do
      game = in_jam("g1")

      {updated, snap} = Game.end_period(game, 1_800_000)
      assert updated.phase == :halftime
      assert snap.phase == :halftime
    end

    test "transitions from :lineup to :halftime in period 1" do
      game = in_lineup("g1")

      {updated, snap} = Game.end_period(game, 1_800_000)
      assert updated.phase == :halftime
      assert snap.phase == :halftime
    end

    test "error in period 2 lineup" do
      game = in_period2_lineup("g1")

      assert {:error, :invalid_transition, :end_period, :lineup} =
               Game.end_period(game, 0)
    end

    test "error when in :initial" do
      game = Game.new("g1")

      assert {:error, :invalid_transition, :end_period, :initial} =
               Game.end_period(game, 0)
    end
  end

  describe "end_game/2" do
    test "transitions from :lineup to :final in period 2" do
      game = in_period2_lineup("g1")

      {updated, snap} = Game.end_game(game, 5_000_000)
      assert updated.phase == :final
      assert snap.phase == :final
    end

    test "transitions from :jam_running to :final in period 2" do
      game = in_period2_jam("g1")

      {updated, snap} = Game.end_game(game, 5_000_000)
      assert updated.phase == :final
      assert snap.phase == :final
    end

    test "error when in period 1" do
      game = in_jam("g1")

      assert {:error, :invalid_transition, :end_game, :jam_running} =
               Game.end_game(game, 0)
    end

    test "error when in :initial" do
      game = Game.new("g1")

      assert {:error, :invalid_transition, :end_game, :initial} =
               Game.end_game(game, 0)
    end
  end

  describe "score/4" do
    test "adds points to home team" do
      game = in_jam("g1")

      {updated, snap} = Game.score(game, :home, 3, 5000)
      assert updated.score_home == 3
      assert snap.score_home == 3
    end

    test "adds points to away team" do
      game = in_jam("g1")

      {updated, snap} = Game.score(game, :away, 2, 5000)
      assert updated.score_away == 2
      assert snap.score_away == 2
    end

    test "accumulates across multiple calls" do
      game = in_jam("g1")
      {game, _} = Game.score(game, :home, 3, 5000)
      {game, _} = Game.score(game, :away, 2, 6000)
      {updated, _} = Game.score(game, :home, 4, 7000)
      assert updated.score_home == 7
      assert updated.score_away == 2
    end

    test "error in :initial phase" do
      game = Game.new("g1")

      assert {:error, :invalid_transition, :score, :initial} =
               Game.score(game, :home, 1, 0)
    end
  end

  describe "snapshot/2" do
    test "returns map with all expected keys" do
      game = Game.new("g1")
      snap = Game.snapshot(game, 0)

      assert Map.keys(snap) |> Enum.sort() ==
               ~w[jam_number period phase score_away score_home
                 period_clock_s lineup_clock_s jam_clock_s timeout_clock_s]a |> Enum.sort()
    end

    test "clocks count down in seconds" do
      game = in_lineup("g1")

      snap = Game.snapshot(game, 10_000)
      assert snap.period_clock_s == 1790
    end
  end

  describe "full game flow" do
    test "complete period 1 → halftime → period 2 → final" do
      t0 = 0

      game = Game.new("full-game")

      {game, snap} = Game.start_period(game, t0)
      assert snap.period == 1
      assert snap.phase == :lineup

      {game, snap} = Game.start_jam(game, t0 + 1000)
      assert snap.jam_number == 1
      assert snap.phase == :jam_running

      {game, _snap} = Game.score(game, :home, 4, t0 + 5000)

      {game, snap} = Game.end_jam(game, t0 + 120_000)
      assert snap.phase == :lineup

      {game, snap} = Game.start_jam(game, t0 + 150_000)
      assert snap.jam_number == 2

      {game, snap} = Game.call_timeout(game, t0 + 200_000)
      assert snap.phase == :timeout

      {game, snap} = Game.end_timeout(game, t0 + 260_000)
      assert snap.phase == :lineup

      {game, snap} = Game.end_period(game, t0 + 1_800_000)
      assert snap.phase == :halftime

      {game, snap} = Game.start_period(game, t0 + 2_400_000)
      assert snap.period == 2
      assert snap.phase == :lineup

      {game, snap} = Game.start_jam(game, t0 + 2_401_000)
      assert snap.jam_number == 3

      {_game, snap} = Game.end_jam(game, t0 + 2_521_000)

      {_game, snap} = Game.end_game(game, t0 + 3_600_000)
      assert snap.phase == :final
      assert snap.score_home == 4
    end
  end

  defp in_lineup(id) do
    {game, _} = Game.new(id) |> Game.start_period(0)
    game
  end

  defp in_jam(id) do
    {game, _} =
      Game.new(id) |> Game.start_period(0) |> then(fn {g, _} -> Game.start_jam(g, 1000) end)

    game
  end

  defp in_timeout(id) do
    {game, _} =
      Game.new(id)
      |> Game.start_period(0)
      |> then(fn {g, _} -> Game.start_jam(g, 1000) end)
      |> then(fn {g, _} -> Game.call_timeout(g, 5000) end)

    game
  end

  defp in_halftime(id) do
    {game, _} =
      Game.new(id)
      |> Game.start_period(0)
      |> then(fn {g, _} -> Game.start_jam(g, 1000) end)
      |> then(fn {g, _} -> Game.end_period(g, 1_800_000) end)

    game
  end

  defp in_period2_lineup(id) do
    {game, _} =
      in_halftime(id)
      |> then(fn g -> Game.start_period(g, 2_400_000) end)

    game
  end

  defp in_period2_jam(id) do
    {game, _} =
      in_period2_lineup(id)
      |> then(fn g -> Game.start_jam(g, 2_401_000) end)

    game
  end
end
