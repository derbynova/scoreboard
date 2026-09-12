defmodule Scoreboard.Derby.GameEvent do
  use Ash.Resource,
    otp_app: :scoreboard,
    domain: Scoreboard.Derby,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "game_events"
    repo Scoreboard.Repo
  end

  actions do
    defaults [:read]

    create :append do
      primary? true
      accept [:game_id, :sequence, :action, :payload, :state, :version]
    end
  end

  attributes do
    uuid_v7_primary_key :id
    attribute :game_id, :string, allow_nil?: false, public?: true
    attribute :sequence, :integer, allow_nil?: false, public?: true, constraints: [min: 1]
    attribute :action, :string, allow_nil?: false, public?: true
    attribute :payload, :map, allow_nil?: false, default: %{}, public?: true
    attribute :state, :map, allow_nil?: false, public?: true
    attribute :version, :integer, allow_nil?: false, default: 1, public?: true
    create_timestamp :inserted_at
  end

  identities do
    identity :game_sequence, [:game_id, :sequence]
  end
end
