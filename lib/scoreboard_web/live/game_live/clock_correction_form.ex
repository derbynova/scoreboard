defmodule ScoreboardWeb.GameLive.ClockCorrectionForm do
  import Ecto.Changeset

  def changeset(params, duration_ms) do
    {%{}, %{minutes: :integer, seconds: :integer}}
    |> cast(params, [:minutes, :seconds])
    |> validate_required([:minutes, :seconds])
    |> validate_number(:minutes,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: div(duration_ms, 60_000)
    )
    |> validate_number(:seconds, greater_than_or_equal_to: 0, less_than: 60)
    |> validate_total(duration_ms)
  end

  def remaining_ms(changeset),
    do: (get_field(changeset, :minutes) * 60 + get_field(changeset, :seconds)) * 1000

  defp validate_total(%{valid?: true} = changeset, duration_ms) do
    if remaining_ms(changeset) > duration_ms,
      do: add_error(changeset, :seconds, "must fit within the clock duration"),
      else: changeset
  end

  defp validate_total(changeset, _duration_ms), do: changeset
end
