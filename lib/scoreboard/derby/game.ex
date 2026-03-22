defmodule Scoreboard.Derby.Game do
  use Ash.Resource,
    otp_app: :scoreboard,
    domain: Scoreboard.Derby,
    data_layer: AshSqlite.DataLayer,
    extensions: [AshStateMachine]

  sqlite do
    table "games"
    repo Scoreboard.Repo
  end

  state_machine do
    initial_states [:setup]
    default_initial_state :setup

    transitions do
      transition :start_period, from: [:setup, :halftime], to: :lineup
      transition :start_jam, from: :lineup, to: :jam_running
      transition :end_jam, from: :jam_running, to: :lineup
      transition :call_timeout, from: [:jam_running, :lineup], to: :timeout
      transition :end_timeout, from: :timeout, to: :lineup
      transition :end_period, from: [:jam_running, :lineup], to: :halftime
      transition :end_game, from: [:jam_running, :lineup], to: :final
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create, primary?: true, accept: []

    update :update do
      accept [:current_period, :current_jam_number, :timeout_caller]
      primary? true
    end

    update :start_period do
      accept [:current_period]
      change set_attribute(:period_clock_running, true)
      change set_attribute(:lineup_clock_running, true)
      change set_attribute(:current_jam_number, 0)
    end

    update :start_jam do
      accept [:current_jam_number]
      change set_attribute(:jam_clock_running, true)
      change set_attribute(:lineup_clock_running, false)
      change atomic_update(:current_jam_number, expr(:current_jam_number + 1))
    end

    update :end_jam do
      accept []
      change set_attribute(:jam_clock_running, false)
      change set_attribute(:lineup_clock_running, true)
    end

    update :call_timeout do
      accept [:timeout_caller]

      argument :team, :atom do
        constraints one_of: [:team_a, :team_b]
        allow_nil? true
      end

      change set_attribute(:jam_clock_running, false)
      change set_attribute(:lineup_clock_running, false)
      change set_attribute(:timeout_clock_running, true)
    end

    update :end_timeout do
      accept []
      change set_attribute(:lineup_clock_running, true)
      change set_attribute(:timeout_clock_running, false)
    end

    update :end_period do
      accept [:current_period]
      change set_attribute(:period_clock_running, false)
      change set_attribute(:jam_clock_running, false)
      change set_attribute(:lineup_clock_running, false)
    end

    update :end_game do
      accept []
      change set_attribute(:period_clock_running, false)
      change set_attribute(:jam_clock_running, false)
      change set_attribute(:lineup_clock_running, false)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    # Game tracking
    attribute :current_period, :integer, allow_nil?: false, default: 1, public?: true
    attribute :current_jam_number, :integer, allow_nil?: false, default: 0, public?: true

    attribute :timeout_caller, :atom do
      constraints one_of: [:team, :officials]
      default nil
      public? true
    end

    # Clocks
    attribute :period_clock_running, :boolean, default: false, public?: true
    attribute :jam_clock_running, :boolean, default: false, public?: true
    attribute :lineup_clock_running, :boolean, default: false, public?: true
    attribute :timeout_clock_running, :boolean, default: false, public?: true

    timestamps()
  end

  relationships do
    has_one :home_team, Scoreboard.Derby.GameTeam
    has_one :away_team, Scoreboard.Derby.GameTeam
    has_many :jams, Scoreboard.Derby.Jam
  end
end
