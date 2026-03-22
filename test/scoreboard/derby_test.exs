defmodule Scoreboard.DerbyTest do
  use Scoreboard.DataCase, async: true
  alias Scoreboard.Derby

  describe "end-to-end workflow" do
    test "creates a complete game structure with teams, skaters, and jams" do
      # Create a game
      game = Derby.create_game!()
      assert game.state == :setup

      # Create home and away teams
      home_team = Derby.create_team!(%{name: "Home Team", short_name: "HT"})
      away_team = Derby.create_team!(%{name: "Away Team", short_name: "AT"})

      # Create game_teams
      home_game_team =
        Derby.create_game_team!(%{
          designation: :home,
          game_id: game.id,
          team_id: home_team.id
        })

      away_game_team =
        Derby.create_game_team!(%{
          designation: :away,
          game_id: game.id,
          team_id: away_team.id
        })

      assert home_game_team.designation == :home
      assert away_game_team.designation == :away

      # Add skaters to teams
      home_skater1 =
        Derby.create_skater!(%{
          number: "123",
          name: "Home Skater 1",
          team_id: home_team.id
        })

      home_skater2 =
        Derby.create_skater!(%{
          number: "456",
          name: "Home Skater 2",
          team_id: home_team.id
        })

      away_skater1 =
        Derby.create_skater!(%{
          number: "789",
          name: "Away Skater 1",
          team_id: away_team.id
        })

      assert home_skater1.team_id == home_team.id
      assert home_skater2.team_id == home_team.id
      assert away_skater1.team_id == away_team.id

      # Create jams for the game
      jam1 =
        Derby.create_jam!(%{
          jam_number: 1,
          period: 1,
          home_points: 5,
          away_points: 3,
          home_lead: true,
          game_id: game.id
        })

      jam2 =
        Derby.create_jam!(%{
          jam_number: 2,
          period: 1,
          home_points: 2,
          away_points: 4,
          away_lead: true,
          game_id: game.id
        })

      assert jam1.game_id == game.id
      assert jam2.game_id == game.id
      assert jam1.home_points == 5
      assert jam2.away_points == 4

      # Verify all resources can be listed
      assert length(Derby.list_games!()) == 1
      assert length(Derby.list_teams!()) == 2
      assert length(Derby.list_game_teams!()) == 2
      assert length(Derby.list_skaters!()) == 3
      assert length(Derby.list_jams!()) == 2

      # Verify game actions work
      updated_game_team = Derby.add_points!(home_game_team, %{points: 5})
      assert updated_game_team.score == 5

      updated_game_team = Derby.add_points!(updated_game_team, %{points: 3})
      assert updated_game_team.score == 8

      # Verify timeout and official review actions
      game_team_with_timeout = Derby.use_timeout!(home_game_team)
      assert game_team_with_timeout.timeouts_remaining == 2

      game_team_with_review = Derby.use_official_review!(home_game_team)
      assert game_team_with_review.official_reviews_remaining == 0
    end
  end
end
