defmodule GameServer.Impl.Game do
  alias GameServer.Impl.Timer

  @period_ms 1_800_000
  @lineup_ms 30_000
  @jam_ms 120_000
  @timeout_ms 60_000
  @intermission_ms 600_000

  defstruct [
    :id,
    :last_update,
    phase: :initial,
    period: 0,
    jam_number: 0,
    score_home: 0,
    score_away: 0,
    period_clock: Timer.new(@period_ms),
    lineup_clock: Timer.new(@lineup_ms),
    jam_clock: Timer.new(@jam_ms),
    timeout_clock: Timer.new(@timeout_ms),
    intermission_clock: Timer.new(@intermission_ms)
  ]

  def new(id), do: %__MODULE__{id: id}

  def start_period(%{phase: phase, period: period} = game, now)
      when phase in [:initial, :halftime] and period < 2 do
    game
    |> Map.merge(%{
      phase: :lineup,
      period: period + 1,
      period_clock: Timer.reset(game.period_clock) |> Timer.start(now),
      lineup_clock: Timer.reset(game.lineup_clock) |> Timer.start(now),
      jam_clock: Timer.reset(game.jam_clock),
      timeout_clock: Timer.reset(game.timeout_clock),
      intermission_clock:
        case phase do
          :initial -> Timer.reset(game.intermission_clock)
          :halftime -> Timer.reset(game.intermission_clock, 0)
        end
    })
    |> return_with_snapshot(now)
  end

  def start_period(%{phase: phase}, _now),
    do: {:error, :invalid_transition, :start_period, phase}

  def start_jam(%{phase: :lineup} = game, now) do
    game
    |> Map.merge(%{
      phase: :jam_running,
      jam_number: game.jam_number + 1,
      lineup_clock: game.lineup_clock |> Timer.reset(),
      jam_clock: Timer.reset(game.jam_clock) |> Timer.start(now)
    })
    |> return_with_snapshot(now)
  end

  def start_jam(%{phase: phase}, _now),
    do: {:error, :invalid_transition, :start_jam, phase}

  def end_jam(%{phase: :jam_running} = game, now) do
    game
    |> Map.merge(%{
      phase: :lineup,
      lineup_clock: game.lineup_clock |> Timer.start(now),
      jam_clock: game.jam_clock |> Timer.stop(now)
    })
    |> return_with_snapshot(now)
  end

  def end_jam(%{phase: phase}, _now),
    do: {:error, :invalid_transition, :end_jam, phase}

  def call_timeout(%{phase: phase} = game, now) when phase in [:jam_running, :lineup] do
    game
    |> Map.merge(%{
      phase: :timeout,
      period_clock: game.period_clock |> Timer.stop(now),
      lineup_clock: game.lineup_clock |> Timer.stop(now),
      jam_clock: game.jam_clock |> Timer.stop(now),
      timeout_clock: Timer.reset(game.timeout_clock) |> Timer.start(now)
    })
    |> return_with_snapshot(now)
  end

  def call_timeout(%{phase: phase}, _now),
    do: {:error, :invalid_transition, :call_timeout, phase}

  def end_timeout(%{phase: :timeout} = game, now) do
    game
    |> Map.merge(%{
      phase: :lineup,
      period_clock: game.period_clock |> Timer.start(now),
      lineup_clock: game.lineup_clock |> Timer.start(now),
      timeout_clock: game.timeout_clock |> Timer.stop(now)
    })
    |> return_with_snapshot(now)
  end

  def end_timeout(%{phase: phase}, _now),
    do: {:error, :invalid_transition, :end_timeout, phase}

  def end_period(%{phase: phase, period: 1} = game, now)
      when phase in [:jam_running, :lineup] do
    game
    |> Map.merge(%{
      phase: :halftime,
      period_clock: game.period_clock |> Timer.stop(now),
      lineup_clock: game.lineup_clock |> Timer.stop(now),
      jam_clock: game.jam_clock |> Timer.stop(now),
      intermission_clock: game.intermission_clock |> Timer.start(now)
    })
    |> return_with_snapshot(now)
  end

  def end_period(%{phase: phase}, _now),
    do: {:error, :invalid_transition, :end_period, phase}

  def end_game(%{phase: phase, period: 2} = game, now)
      when phase in [:jam_running, :lineup] do
    game
    |> Map.merge(%{
      phase: :final,
      period_clock: game.period_clock |> Timer.stop(now),
      lineup_clock: game.lineup_clock |> Timer.stop(now),
      jam_clock: game.jam_clock |> Timer.stop(now)
    })
    |> return_with_snapshot(now)
  end

  def end_game(%{phase: phase}, _now),
    do: {:error, :invalid_transition, :end_game, phase}

  def score(%{phase: phase} = game, :home, points, now) when phase not in [:initial] do
    %{game | score_home: game.score_home + points} |> return_with_snapshot(now)
  end

  def score(%{phase: phase} = game, :away, points, now) when phase not in [:initial] do
    %{game | score_away: game.score_away + points} |> return_with_snapshot(now)
  end

  def score(%{phase: phase}, _team, _points, _now),
    do: {:error, :invalid_transition, :score, phase}

  def snapshot(game, now) do
    %{
      phase: game.phase,
      period: game.period,
      jam_number: game.jam_number,
      score_home: game.score_home,
      score_away: game.score_away,
      period_clock_s: Timer.remaining(game.period_clock, now) |> div(1000),
      lineup_clock_s: Timer.remaining(game.lineup_clock, now) |> div(1000),
      jam_clock_s: Timer.remaining(game.jam_clock, now) |> div(1000),
      timeout_clock_s: Timer.remaining(game.timeout_clock, now) |> div(1000)
    }
  end

  defp return_with_snapshot(game, now), do: {game, snapshot(game, now)}
end
