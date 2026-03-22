defmodule Scoreboard.Derby.TeamTest do
  use Scoreboard.DataCase, async: true
  alias Scoreboard.Derby

  test "fails without a short_name" do
    assert_raise Ash.Error.Invalid, ~r/short_name/, fn ->
      Derby.create_team!(%{name: "Blackland Rockin' K-Rollers"})
    end
  end

  describe "with a valid team" do
    setup do
      team =
        %{name: "Blackland Rockin' K-Rollers", short_name: "BRKR"}
        |> Derby.create_team!()

      %{team: team}
    end

    test "gets a team by id", %{team: team} do
      got = Derby.get_team!(team.id)
      assert got.id == team.id
      assert got.name == team.name
      assert got.short_name == team.short_name
    end

    test "creates a team with valid attributes", %{team: team} do
      assert team.name == "Blackland Rockin' K-Rollers"
      assert team.short_name == "BRKR"
    end

    test "updates a team", %{team: team} do
      updated = Derby.update_team!(team, %{name: "New Name"})
      assert updated.name == "New Name"
    end

    test "destroys a team", %{team: team} do
      assert length(Derby.list_teams!()) == 1
      assert :ok = Derby.destroy_team!(team)
      assert Derby.list_teams!() == []
    end
  end
end
