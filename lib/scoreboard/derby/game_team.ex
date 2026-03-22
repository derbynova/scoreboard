defmodule Scoreboard.Derby.GameTeam do
  use Ash.Resource,
    otp_app: :scoreboard,
    domain: Scoreboard.Derby,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "game_teams"
    repo Scoreboard.Repo
  end

  actions do
    defaults [:read, :destroy, create: :*]

    update :update do
      accept [:designation, :score, :timeouts_remaining, :official_reviews_remaining]
      primary? true
    end

    update :add_points do
      argument :points, :integer, allow_nil?: false
      change atomic_update(:score, expr(score + ^arg(:points)))
    end

    update :use_timeout do
      change atomic_update(:timeouts_remaining, expr(timeouts_remaining - 1))
    end

    update :use_official_review do
      change atomic_update(:official_reviews_remaining, expr(official_reviews_remaining - 1))
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :designation, :atom do
      constraints one_of: [:home, :away]
      allow_nil? false
      public? true
    end

    attribute :score, :integer, default: 0, public?: true
    attribute :timeouts_remaining, :integer, default: 3, public?: true
    attribute :official_reviews_remaining, :integer, default: 1, public?: true

    timestamps()
  end

  relationships do
    belongs_to :game, Scoreboard.Derby.Game, allow_nil?: false, public?: true
    belongs_to :team, Scoreboard.Derby.Team, allow_nil?: false, public?: true
  end
end
