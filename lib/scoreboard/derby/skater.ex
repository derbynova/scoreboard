defmodule Scoreboard.Derby.Skater do
  use Ash.Resource,
    otp_app: :scoreboard,
    domain: Scoreboard.Derby,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "skaters"
    repo Scoreboard.Repo
  end

  actions do
    defaults [:read, :destroy, create: :*]

    update :update do
      accept [:number, :name, :legal_name, :is_active]
      primary? true
    end
  end

  attributes do
    uuid_v7_primary_key :id

    # Jersey number (can be alphanumeric)
    attribute :number, :string, allow_nil?: false, public?: true
    # Derby name
    attribute :name, :string, allow_nil?: false, public?: true
    # For official records
    attribute :legal_name, :string, public?: true
    attribute :is_active, :boolean, default: true, public?: true

    timestamps()
  end

  relationships do
    belongs_to :team, Scoreboard.Derby.Team, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_number_per_team, [:team_id, :number]
  end
end
