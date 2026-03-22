defmodule Scoreboard.Derby.JamTest do
  use Scoreboard.DataCase, async: true
  alias Scoreboard.Derby

  describe "with a valid jam" do
    setup do
      game = Derby.create_game!()

      jam =
        %{jam_number: 1, period: 1, game_id: game.id}
        |> Derby.create_jam!()

      %{jam: jam, game: game}
    end

    test "gets a jam by id", %{jam: jam} do
      got = Derby.get_jam!(jam.id)
      assert got.id == jam.id
      assert got.jam_number == jam.jam_number
      assert got.period == jam.period
    end

    test "creates a jam with valid attributes", %{jam: jam} do
      assert jam.jam_number == 1
      assert jam.period == 1
    end

    test "updates a jam", %{jam: jam} do
      updated = Derby.update_jam!(jam, %{home_points: 5, away_points: 3})
      assert updated.home_points == 5
      assert updated.away_points == 3
    end

    test "destroys a jam", %{jam: jam} do
      assert length(Derby.list_jams!()) == 1
      assert :ok = Derby.destroy_jam!(jam)
      assert Derby.list_jams!() == []
    end

    test "lists jams", %{jam: jam} do
      jams = Derby.list_jams!()
      assert length(jams) == 1
      assert hd(jams).id == jam.id
    end
  end

  describe "default values" do
    setup do
      game = Derby.create_game!()
      %{game: game}
    end

    test "home_points defaults to 0", %{game: game} do
      jam = Derby.create_jam!(%{jam_number: 1, period: 1, game_id: game.id})
      assert jam.home_points == 0
    end

    test "away_points defaults to 0", %{game: game} do
      jam = Derby.create_jam!(%{jam_number: 1, period: 1, game_id: game.id})
      assert jam.away_points == 0
    end

    test "home_lead defaults to false", %{game: game} do
      jam = Derby.create_jam!(%{jam_number: 1, period: 1, game_id: game.id})
      assert jam.home_lead == false
    end

    test "away_lead defaults to false", %{game: game} do
      jam = Derby.create_jam!(%{jam_number: 1, period: 1, game_id: game.id})
      assert jam.away_lead == false
    end
  end

  describe "relationship" do
    test "jam belongs to game" do
      game = Derby.create_game!()
      jam = Derby.create_jam!(%{jam_number: 1, period: 1, game_id: game.id})

      assert jam.game_id == game.id
    end
  end
end
