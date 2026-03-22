defmodule Scoreboard.Derby do
  use Ash.Domain, otp_app: :scoreboard, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Scoreboard.Derby.Team do
      define :create_team, action: :create
      define :get_team, action: :read, get_by: :id
      define :update_team, action: :update
      define :destroy_team, action: :destroy

      define :list_teams, action: :read
    end

    resource Scoreboard.Derby.Game do
      define :create_game, action: :create
      define :get_game, action: :read, get_by: :id
      define :update_game, action: :update
      define :list_games, action: :read
      define :destroy_game, action: :destroy

      define :start_period, action: :start_period
      define :start_jam, action: :start_jam
      define :end_jam, action: :end_jam
      define :call_timeout, action: :call_timeout
      define :end_timeout, action: :end_timeout
      define :end_period, action: :end_period
      define :end_game, action: :end_game
    end

    resource Scoreboard.Derby.GameTeam do
      define :create_game_team, action: :create
      define :get_game_team, action: :read, get_by: :id
      define :update_game_team, action: :update
      define :destroy_game_team, action: :destroy
      define :list_game_teams, action: :read

      define :add_points, action: :add_points
      define :use_timeout, action: :use_timeout
      define :use_official_review, action: :use_official_review
    end

    resource Scoreboard.Derby.Skater do
      define :create_skater, action: :create
      define :get_skater, action: :read, get_by: :id
      define :update_skater, action: :update
      define :destroy_skater, action: :destroy
      define :list_skaters, action: :read
    end

    resource Scoreboard.Derby.Jam do
      define :create_jam, action: :create
      define :get_jam, action: :read, get_by: :id
      define :update_jam, action: :update
      define :destroy_jam, action: :destroy
      define :list_jams, action: :read
    end
  end
end
