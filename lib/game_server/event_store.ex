defmodule GameServer.EventStore do
  @moduledoc "Append-only action journal with portable checkpoints, committed before acknowledgement."
  require Ash.Query
  alias GameServer.Impl.Checkpoint
  alias Scoreboard.Derby
  alias Scoreboard.Derby.GameEvent

  @actions ~w(create start_period start_jam end_jam call_timeout end_timeout end_period end_game score resume_recovered)

  def load(id) do
    with {:ok, events} <-
           GameEvent
           |> Ash.Query.filter(game_id == ^id)
           |> Ash.Query.sort(sequence: :asc)
           |> Ash.read() do
      replay(id, events)
    end
  end

  def append(game, sequence, action, payload, now) do
    Derby.append_game_event(%{
      game_id: game.id,
      sequence: sequence,
      action: action,
      payload: payload,
      state: Checkpoint.encode(game, now),
      version: 1
    })
  end

  def replay(_id, []), do: {:ok, nil, 0}

  def replay(id, events) do
    Enum.reduce_while(events, {:ok, nil, 0}, fn event, {:ok, _game, previous} ->
      with true <- event.game_id == id and event.sequence == previous + 1,
           true <- event.version == 1,
           true <- event.action in @actions,
           true <- previous != 0 or event.action == "create",
           {:ok, game} <- Checkpoint.decode(id, event.state) do
        {:cont, {:ok, game, event.sequence}}
      else
        _ -> {:halt, {:error, :invalid_journal}}
      end
    end)
  end
end
