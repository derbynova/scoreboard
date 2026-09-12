defmodule GameServer.SavedGame do
  @moduledoc "A saved match summary. Reading it never starts match clocks or processes."
  defstruct [
    :id,
    :saved_at,
    :phase,
    :period,
    :jam_number,
    :score_home,
    :score_away,
    valid?: false
  ]
end
