defmodule Scoreboard.Derby.Jam do
  use Ash.Resource,
    otp_app: :scoreboard,
    domain: Scoreboard.Derby,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "jams"
    repo Scoreboard.Repo
  end

  actions do
    defaults [:read, :destroy, create: :*]

    update :update do
      accept [:jam_number, :period, :home_points, :away_points, :home_lead, :away_lead]
      primary? true
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :jam_number, :integer, public?: true
    attribute :period, :integer, public?: true
    attribute :home_points, :integer, default: 0, public?: true
    attribute :away_points, :integer, default: 0, public?: true
    attribute :home_lead, :boolean, default: false, public?: true
    attribute :away_lead, :boolean, default: false, public?: true

    timestamps()
  end

  relationships do
    belongs_to :game, Scoreboard.Derby.Game, allow_nil?: false, public?: true
  end
end
