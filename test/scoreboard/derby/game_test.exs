defmodule Scoreboard.Derby.GameTest do
  use Scoreboard.DataCase, async: true
  alias Scoreboard.Derby

  describe "basic CRUD" do
    test "creates a game" do
      game = Derby.create_game!()
      assert game.current_period == 1
      assert game.current_jam_number == 0
      assert game.state == :setup
    end

    test "gets a game by id" do
      game = Derby.create_game!()
      got = Derby.get_game!(game.id)
      assert got.id == game.id
      assert got.current_period == game.current_period
    end

    test "lists games" do
      game1 = Derby.create_game!()
      game2 = Derby.create_game!()

      games = Derby.list_games!()
      assert length(games) == 2
      assert Enum.any?(games, fn g -> g.id == game1.id end)
      assert Enum.any?(games, fn g -> g.id == game2.id end)
    end

    test "destroys a game" do
      game = Derby.create_game!()
      assert length(Derby.list_games!()) == 1
      assert :ok = Derby.destroy_game!(game)
      assert Derby.list_games!() == []
    end

    test "updates a game" do
      game = Derby.create_game!()
      updated = Derby.update_game!(game, %{current_period: 2})
      assert updated.current_period == 2
    end
  end

  describe "relationship tests" do
    test "game has_many jams" do
      game = Derby.create_game!()
      _jam1 = Derby.create_jam!(%{jam_number: 1, period: 1, game_id: game.id})
      _jam2 = Derby.create_jam!(%{jam_number: 2, period: 1, game_id: game.id})

      game_with_jams = Derby.get_game!(game.id, load: [:jams])
      assert length(game_with_jams.jams) == 2
    end

    test "game has_one home_team (through game_teams)" do
      game = Derby.create_game!()
      team = Derby.create_team!(%{name: "Home Team", short_name: "HT"})
      Derby.create_game_team!(%{designation: :home, game_id: game.id, team_id: team.id})

      game_with_home = Derby.get_game!(game.id, load: [:home_team])
      assert game_with_home.home_team.designation == :home
    end

    test "game has_one away_team (through game_teams)" do
      game = Derby.create_game!()
      team = Derby.create_team!(%{name: "Away Team", short_name: "AT"})
      Derby.create_game_team!(%{designation: :away, game_id: game.id, team_id: team.id})

      game_with_away = Derby.get_game!(game.id, load: [:away_team])
      assert game_with_away.away_team.designation == :away
    end
  end
end
