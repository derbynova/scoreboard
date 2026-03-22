defmodule Scoreboard.Derby.SkaterTest do
  use Scoreboard.DataCase, async: true
  alias Scoreboard.Derby

  test "fails without a number" do
    team = Derby.create_team!(%{name: "Blackland Rockin' K-Rollers", short_name: "BRKR"})

    assert_raise Ash.Error.Invalid, ~r/number/, fn ->
      Derby.create_skater!(%{name: "Skater Name", team_id: team.id})
    end
  end

  test "fails without a name" do
    team = Derby.create_team!(%{name: "Blackland Rockin' K-Rollers", short_name: "BRKR"})

    assert_raise Ash.Error.Invalid, ~r/name/, fn ->
      Derby.create_skater!(%{number: "123", team_id: team.id})
    end
  end

  test "succeeds without legal_name (it's nullable)" do
    team = Derby.create_team!(%{name: "Blackland Rockin' K-Rollers", short_name: "BRKR"})

    skater = Derby.create_skater!(%{number: "123", name: "Skater Name", team_id: team.id})
    assert skater.legal_name == nil
  end

  test "succeeds without is_active (has default)" do
    team = Derby.create_team!(%{name: "Blackland Rockin' K-Rollers", short_name: "BRKR"})

    skater = Derby.create_skater!(%{number: "123", name: "Skater Name", team_id: team.id})
    assert skater.is_active == true
  end

  describe "with a valid skater" do
    setup do
      team = Derby.create_team!(%{name: "Blackland Rockin' K-Rollers", short_name: "BRKR"})

      skater =
        %{number: "123", name: "Skater Name", legal_name: "Jane Doe", team_id: team.id}
        |> Derby.create_skater!()

      %{skater: skater, team: team}
    end

    test "gets a skater by id", %{skater: skater} do
      got = Derby.get_skater!(skater.id)
      assert got.id == skater.id
      assert got.number == skater.number
      assert got.name == skater.name
    end

    test "creates a skater with valid attributes", %{skater: skater} do
      assert skater.number == "123"
      assert skater.name == "Skater Name"
      assert skater.legal_name == "Jane Doe"
      assert skater.is_active == true
    end

    test "updates a skater", %{skater: skater} do
      updated = Derby.update_skater!(skater, %{name: "New Skater Name"})
      assert updated.name == "New Skater Name"
    end

    test "destroys a skater", %{skater: skater} do
      assert length(Derby.list_skaters!()) == 1
      assert :ok = Derby.destroy_skater!(skater)
      assert Derby.list_skaters!() == []
    end

    test "lists skaters", %{skater: skater} do
      skaters = Derby.list_skaters!()
      assert length(skaters) == 1
      assert hd(skaters).id == skater.id
    end
  end

  describe "identity constraint" do
    setup do
      team = Derby.create_team!(%{name: "Blackland Rockin' K-Rollers", short_name: "BRKR"})
      team2 = Derby.create_team!(%{name: "Another Team", short_name: "AT"})
      %{team: team, team2: team2}
    end

    test "fails to create two skaters with same number on same team", %{team: team} do
      Derby.create_skater!(%{number: "123", name: "Skater One", team_id: team.id})

      assert_raise Ash.Error.Invalid, ~r/number/, fn ->
        Derby.create_skater!(%{number: "123", name: "Skater Two", team_id: team.id})
      end
    end

    test "succeeds creating skaters with same number on different teams", %{
      team: team,
      team2: team2
    } do
      skater1 = Derby.create_skater!(%{number: "123", name: "Skater One", team_id: team.id})
      skater2 = Derby.create_skater!(%{number: "123", name: "Skater Two", team_id: team2.id})

      assert skater1.number == skater2.number
      assert skater1.team_id != skater2.team_id
    end
  end
end
