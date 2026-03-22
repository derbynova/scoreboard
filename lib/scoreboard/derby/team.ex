defmodule Scoreboard.Derby.Team do
  use Ash.Resource,
    otp_app: :scoreboard,
    domain: Scoreboard.Derby,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "teams"
    repo Scoreboard.Repo
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :short_name, :string, allow_nil?: false, public?: true
    attribute :name, :string, public?: true
    timestamps()
  end

  relationships do
    has_many :skaters, Scoreboard.Derby.Skater
  end
end
