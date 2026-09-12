defmodule GameServer.Impl.Checkpoint do
  @moduledoc "Portable, versioned game state. Monotonic timestamps never leave the runtime."
  alias GameServer.Impl.{Game, Timer}

  @clocks [:period_clock, :lineup_clock, :jam_clock, :timeout_clock, :intermission_clock]
  @phases [:initial, :lineup, :jam_running, :timeout, :halftime, :final]
  @numbers [:period, :jam_number, :score_home, :score_away]

  def encode(game, now) do
    scalars = Map.new(@numbers, &{Atom.to_string(&1), Map.fetch!(game, &1)})

    clocks =
      Map.new(@clocks, fn name ->
        timer = Map.fetch!(game, name)

        {Atom.to_string(name),
         %{
           "duration" => timer.duration,
           "elapsed" => Timer.elapsed(timer, now),
           "running" => timer.running or name in game.recovery_clocks
         }}
      end)

    Map.merge(scalars, %{"phase" => Atom.to_string(game.phase), "clocks" => clocks})
  end

  def decode(id, %{"phase" => phase, "clocks" => clocks} = data) when is_map(clocks) do
    phase_atom = Enum.find(@phases, &(Atom.to_string(&1) == phase))

    with true <- phase_atom != nil,
         true <- Enum.all?(@numbers, &is_integer(data[Atom.to_string(&1)])),
         true <- data["period"] in 0..2 and data["jam_number"] >= 0,
         {:ok, timers, running} <- decode_clocks(clocks) do
      fields = Map.new(@numbers, &{&1, data[Atom.to_string(&1)]})

      {:ok,
       struct(Game, Map.merge(fields, timers))
       |> Map.merge(%{
         id: id,
         phase: phase_atom,
         recovery_clocks: running
       })}
    else
      _ -> {:error, :invalid_checkpoint}
    end
  end

  def decode(_, _), do: {:error, :invalid_checkpoint}

  def resume(%Game{recovery_clocks: []}, _now), do: {:error, :not_awaiting_recovery}

  def resume(game, now) do
    game =
      Enum.reduce(game.recovery_clocks, game, fn name, game ->
        Map.update!(game, name, &Timer.start(&1, now))
      end)

    game = %{game | recovery_clocks: []}
    {game, Game.snapshot(game, now)}
  end

  defp decode_clocks(clocks) do
    Enum.reduce_while(@clocks, {:ok, %{}, []}, fn name, {:ok, timers, running} ->
      case clocks[Atom.to_string(name)] do
        %{"duration" => duration, "elapsed" => elapsed, "running" => active}
        when is_integer(duration) and duration >= 0 and is_integer(elapsed) and elapsed >= 0 and
               is_boolean(active) ->
          timer = %Timer{duration: duration, accumulated: elapsed, running: false}

          {:cont,
           {:ok, Map.put(timers, name, timer), if(active, do: [name | running], else: running)}}

        _ ->
          {:halt, {:error, :invalid_checkpoint}}
      end
    end)
  end
end
