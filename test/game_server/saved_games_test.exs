defmodule GameServer.SavedGamesTest do
  use Scoreboard.DataCase, async: false
  alias GameServer.{EventStore, Impl.Game}
  alias Scoreboard.Derby.GameEvent

  test "one summary per match uses the latest sequence, without starting a server" do
    game = Game.new("summary")
    EventStore.append(game, 1, "create", %{}, 0)

    EventStore.append(
      %{game | score_home: 12, score_away: 8, period: 2, phase: :final},
      2,
      "end_game",
      %{},
      0
    )

    assert {:ok, [summary], nil} = EventStore.list_saved_games()
    assert summary.id == "summary"
    assert summary.score_home == 12
    assert summary.score_away == 8
    assert summary.phase == :final
    assert [] == Registry.lookup(GameRegistry, "summary")
  end

  test "cursor pagination is deterministic even when save timestamps are identical" do
    for id <- ["a", "b", "c"] do
      EventStore.append(Game.new(id), 1, "create", %{}, 0)
    end

    Repo.update_all(GameEvent, set: [inserted_at: ~U[2026-09-12 10:00:00.000000Z]])
    assert {:ok, page, cursor} = EventStore.list_saved_games(nil, 2)
    assert Enum.map(page, & &1.id) == ["c", "b"]
    assert {:ok, [last], nil} = EventStore.list_saved_games(cursor, 2)
    assert last.id == "a"
  end

  test "unsupported saved state remains visible as unavailable" do
    EventStore.append(Game.new("bad"), 1, "create", %{}, 0)
    Repo.update_all(GameEvent, set: [version: 99])
    assert {:ok, [summary], nil} = EventStore.list_saved_games()
    refute summary.valid?
    assert summary.id == "bad"
  end

  test "read failure returns a storage error rather than an empty library" do
    Ecto.Adapters.SQL.query!(Repo, "ALTER TABLE game_events RENAME TO unavailable_events")

    try do
      assert {:error, :storage_unavailable} = EventStore.list_saved_games()
    after
      Ecto.Adapters.SQL.query!(Repo, "ALTER TABLE unavailable_events RENAME TO game_events")
    end
  end
end
