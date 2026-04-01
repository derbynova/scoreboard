defmodule ScoreboardWeb.Helpers.ClockTest do
  use ExUnit.Case, async: true

  alias ScoreboardWeb.Helpers.Clock

  describe "format_clock/1" do
    test "formats zero seconds" do
      assert Clock.format_clock(0) == "00:00"
    end

    test "formats seconds under a minute" do
      assert Clock.format_clock(45) == "00:45"
    end

    test "formats exactly one minute" do
      assert Clock.format_clock(60) == "01:00"
    end

    test "formats minutes and seconds" do
      assert Clock.format_clock(125) == "02:05"
    end

    test "formats a full game period (30 min)" do
      assert Clock.format_clock(1800) == "30:00"
    end

    test "pads single digit seconds" do
      assert Clock.format_clock(9) == "00:09"
    end

    test "pads single digit minutes" do
      assert Clock.format_clock(65) == "01:05"
    end
  end
end
