defmodule GameServer.Impl.Game do
  alias GameServer.Impl.Timer

  # WFTDA timing constants (see: https://rules.wftda.com)
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
    recovery_clocks: [],
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
      period_clock: Timer.reset(game.period_clock),
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
    if Timer.finished?(game.period_clock, now) do
      {:error, :period_expired}
    else
      do_start_jam(game, now)
    end
  end

  def start_jam(%{phase: phase}, _now),
    do: {:error, :invalid_transition, :start_jam, phase}

  defp do_start_jam(game, now) do
    game
    |> Map.merge(%{
      phase: :jam_running,
      period_clock: Timer.start(game.period_clock, now),
      jam_number: game.jam_number + 1,
      lineup_clock: game.lineup_clock |> Timer.reset(),
      jam_clock: Timer.reset(game.jam_clock) |> Timer.start(now)
    })
    |> return_with_snapshot(now)
  end

  def end_jam(%{phase: :jam_running} = game, now) do
    game
    |> Map.merge(%{
      phase: :lineup,
      lineup_clock: next_lineup(game, now),
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
      period_clock: game.period_clock |> Timer.stop(now),
      lineup_clock: next_lineup(game, now),
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

  def score(%{phase: phase} = game, :home, points, now) when phase == :jam_running do
    %{game | score_home: game.score_home + points} |> return_with_snapshot(now)
  end

  def score(%{phase: phase} = game, :away, points, now) when phase == :jam_running do
    %{game | score_away: game.score_away + points} |> return_with_snapshot(now)
  end

  def score(%{phase: phase}, _team, _points, _now),
    do: {:error, :invalid_transition, :score, phase}

  def snapshot(game, now) do
    %{
      recovery_required: game.recovery_clocks != [],
      clocks:
        Map.new(clock_details(game, now), fn {name, details} ->
          {name, Map.update!(details, :remaining_ms, &(div(&1 + 999, 1000) * 1000))}
        end),
      phase: game.phase,
      period: game.period,
      jam_number: game.jam_number,
      score_home: game.score_home,
      score_away: game.score_away,
      period_clock_s: Timer.remaining(game.period_clock, now) |> then(&div(&1 + 999, 1000)),
      lineup_clock_s: Timer.remaining(game.lineup_clock, now) |> then(&div(&1 + 999, 1000)),
      jam_clock_s: Timer.remaining(game.jam_clock, now) |> then(&div(&1 + 999, 1000)),
      timeout_clock_s: Timer.remaining(game.timeout_clock, now) |> then(&div(&1 + 999, 1000)),
      intermission_clock_s:
        Timer.remaining(game.intermission_clock, now) |> then(&div(&1 + 999, 1000)),
      period_expired: Timer.finished?(game.period_clock, now),
      period_clock_running: game.period_clock.running,
      lineup_clock_running: game.lineup_clock.running,
      jam_clock_running: game.jam_clock.running,
      timeout_clock_running: game.timeout_clock.running,
      intermission_clock_running: game.intermission_clock.running
    }
  end

  @clocks [:period_clock, :lineup_clock, :jam_clock, :timeout_clock, :intermission_clock]

  def clock_details(game, now) do
    Map.new(@clocks, fn name ->
      timer = Map.fetch!(game, name)

      {name,
       %{
         remaining_ms: Timer.remaining(timer, now),
         duration_ms: timer.duration,
         running: timer.running,
         resume_on_confirmation: name in game.recovery_clocks,
         context: clock_context(game, timer)
       }}
    end)
  end

  # Elapsed time may advance while editing, but a phase change, recovery, expiry
  # or another correction must not silently change the effect being confirmed.
  defp clock_context(game, timer) do
    context =
      {game.phase, game.period, game.jam_number, game.recovery_clocks, timer.duration,
       timer.accumulated, timer.running, timer.started_at}

    :crypto.hash(:sha256, :erlang.term_to_binary(context)) |> Base.encode16()
  end

  def correct_clock(game, name, remaining_ms, now, expected_context \\ nil)

  def correct_clock(game, name, remaining_ms, now, expected_context)
      when name in @clocks and is_integer(remaining_ms) and remaining_ms >= 0 do
    {game, _snapshot} = expire_clocks(game, now)
    timer = Map.fetch!(game, name)

    cond do
      remaining_ms > timer.duration ->
        {:error, :invalid_clock_time}

      expected_context != nil and expected_context != clock_context(game, timer) ->
        {:error, :clock_changed}

      true ->
        corrected = %{
          timer
          | accumulated: timer.duration - remaining_ms,
            started_at: if(timer.running, do: now, else: nil)
        }

        game |> Map.put(name, corrected) |> return_with_snapshot(now)
    end
  end

  def correct_clock(_game, _name, _remaining_ms, _now, _context),
    do: {:error, :invalid_clock_time}

  # Expiration stops clocks, never issues an official's phase command.
  def expire_clocks(game, now) do
    updated =
      Enum.reduce(@clocks, game, fn name, game ->
        Map.update!(game, name, &Timer.expire(&1, now))
      end)

    updated =
      if updated.phase == :lineup and Timer.finished?(updated.period_clock, now) do
        %{updated | lineup_clock: Timer.stop(updated.lineup_clock, now)}
      else
        updated
      end

    {updated, snapshot(updated, now)}
  end

  def ticking?(game),
    do: game.recovery_clocks == [] and Enum.any?(@clocks, &Map.fetch!(game, &1).running)

  defp next_lineup(game, now) do
    timer = Timer.reset(game.lineup_clock)
    if Timer.finished?(game.period_clock, now), do: timer, else: Timer.start(timer, now)
  end

  defp return_with_snapshot(game, now), do: expire_clocks(game, now)
end
