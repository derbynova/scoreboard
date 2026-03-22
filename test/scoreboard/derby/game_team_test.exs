defmodule Scoreboard.Derby.GameTeamTest do
  use Scoreboard.DataCase, async: true
  alias Scoreboard.Derby

  describe "with a valid game_team" do
    setup do
      game = Derby.create_game!()
      team = Derby.create_team!(%{name: "Blackland Rockin' K-Rollers", short_name: "BRKR"})

      game_team =
        %{designation: :home, game_id: game.id, team_id: team.id}
        |> Derby.create_game_team!()

      %{game_team: game_team, game: game, team: team}
    end

    test "gets a game_team by id", %{game_team: game_team} do
      got = Derby.get_game_team!(game_team.id)
      assert got.id == game_team.id
      assert got.designation == game_team.designation
    end

    test "creates a game_team with valid attributes", %{game_team: game_team} do
      assert game_team.designation == :home
      assert game_team.score == 0
      assert game_team.timeouts_remaining == 3
      assert game_team.official_reviews_remaining == 1
    end

    test "updates a game_team", %{game_team: game_team} do
      updated = Derby.update_game_team!(game_team, %{score: 10})
      assert updated.score == 10
    end

    test "destroys a game_team", %{game_team: game_team} do
      assert length(Derby.list_game_teams!()) == 1
      assert :ok = Derby.destroy_game_team!(game_team)
      assert Derby.list_game_teams!() == []
    end

    test "lists game_teams", %{game_team: game_team} do
      game_teams = Derby.list_game_teams!()
      assert length(game_teams) == 1
      assert hd(game_teams).id == game_team.id
    end
  end

  describe "action tests" do
    setup do
      game = Derby.create_game!()
      team = Derby.create_team!(%{name: "Blackland Rockin' K-Rollers", short_name: "BRKR"})

      game_team =
        %{designation: :home, game_id: game.id, team_id: team.id}
        |> Derby.create_game_team!()

      %{game_team: game_team}
    end

    test "add_points increments score", %{game_team: game_team} do
      updated = Derby.add_points!(game_team, %{points: 5})
      assert updated.score == 5

      updated = Derby.add_points!(updated, %{points: 3})
      assert updated.score == 8
    end

    test "use_timeout decrements timeouts_remaining", %{game_team: game_team} do
      assert game_team.timeouts_remaining == 3
      updated = Derby.use_timeout!(game_team)
      assert updated.timeouts_remaining == 2
    end

    test "use_official_review decrements official_reviews_remaining", %{game_team: game_team} do
      assert game_team.official_reviews_remaining == 1
      updated = Derby.use_official_review!(game_team)
      assert updated.official_reviews_remaining == 0
    end
  end

  describe "validation tests" do
    test "designation must be :home or :away" do
      game = Derby.create_game!()
      team = Derby.create_team!(%{name: "Blackland Rockin' K-Rollers", short_name: "BRKR"})

      assert_raise Ash.Error.Invalid, ~r/designation/, fn ->
        Derby.create_game_team!(%{designation: :invalid, game_id: game.id, team_id: team.id})
      end
    end

    test "succeeds with :home designation" do
      game = Derby.create_game!()
      team = Derby.create_team!(%{name: "Blackland Rockin' K-Rollers", short_name: "BRKR"})

      game_team =
        Derby.create_game_team!(%{designation: :home, game_id: game.id, team_id: team.id})

      assert game_team.designation == :home
    end

    test "succeeds with :away designation" do
      game = Derby.create_game!()
      team = Derby.create_team!(%{name: "Another Team", short_name: "AT"})

      game_team =
        Derby.create_game_team!(%{designation: :away, game_id: game.id, team_id: team.id})

      assert game_team.designation == :away
    end
  end
end
