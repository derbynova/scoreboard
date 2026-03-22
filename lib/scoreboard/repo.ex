defmodule Scoreboard.Repo do
  use AshSqlite.Repo,
    otp_app: :scoreboard
end
