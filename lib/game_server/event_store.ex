defmodule GameServer.EventStore do
  @moduledoc "Append-only action journal with portable checkpoints, committed before acknowledgement."
  require Ash.Query
  require Ecto.Query
  alias GameServer.Impl.Checkpoint
  alias Scoreboard.Derby
  alias Scoreboard.Derby.GameEvent

  @actions ~w(create start_period start_jam end_jam call_timeout end_timeout end_period end_game score resume_recovered expire_clocks)

  # Select one row per match in SQLite rather than loading every match journal.
  # The journal is still validated in full when an operator restores a match.
  def list_saved_games(cursor \\ nil, limit \\ 20) do
    latest =
      Ecto.Query.from(e in GameEvent,
        group_by: e.game_id,
        select: %{game_id: e.game_id, sequence: max(e.sequence)}
      )

    query =
      Ecto.Query.from(e in GameEvent,
        join: latest in subquery(latest),
        on: e.game_id == latest.game_id and e.sequence == latest.sequence,
        order_by: [desc: e.inserted_at, desc: e.game_id],
        limit: ^(limit + 1)
      )

    query =
      case cursor do
        nil ->
          query

        {saved_at, id} ->
          Ecto.Query.from(e in query,
            where: e.inserted_at < ^saved_at or (e.inserted_at == ^saved_at and e.game_id < ^id)
          )
      end

    events = Scoreboard.Repo.all(query)
    page = Enum.take(events, limit)
    last = List.last(page)
    cursor = if length(events) > limit, do: {last.inserted_at, last.game_id}, else: nil
    {:ok, Enum.map(page, &summary/1), cursor}
  rescue
    _error in [Exqlite.Error, DBConnection.ConnectionError] -> {:error, :storage_unavailable}
  end

  defp summary(event) do
    base = %GameServer.SavedGame{id: event.game_id, saved_at: event.inserted_at}

    case {event.version, event.action in @actions, Checkpoint.decode(event.game_id, event.state)} do
      {1, true, {:ok, game}} ->
        %{
          base
          | valid?: true,
            phase: game.phase,
            period: game.period,
            jam_number: game.jam_number,
            score_home: game.score_home,
            score_away: game.score_away
        }

      _ ->
        base
    end
  end

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
