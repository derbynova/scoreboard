defmodule GameServer.Impl.TimerTest do
  use ExUnit.Case, async: true

  alias GameServer.Impl.Timer

  describe "new/1" do
    test "creates a timer with the given duration" do
      t = Timer.new(30_000)
      assert t.duration == 30_000
      assert t.started_at == nil
      assert t.accumulated == 0
      assert t.running == false
    end
  end

  describe "start/2" do
    test "starts the timer at the given timestamp" do
      t = Timer.new(10_000) |> Timer.start(1000)
      assert t.running == true
      assert t.started_at == 1000
      assert t.accumulated == 0
    end
  end

  describe "stop/2" do
    test "stops the timer and accumulates elapsed time" do
      t =
        Timer.new(10_000)
        |> Timer.start(1000)
        |> Timer.stop(5000)

      assert t.running == false
      assert t.started_at == nil
      assert t.accumulated == 4000
    end
  end

  describe "reset/1 and reset/2" do
    test "reset/1 resets accumulated time and stops the timer, keeping duration" do
      t =
        Timer.new(10_000)
        |> Timer.start(0)
        |> Timer.stop(5000)
        |> Timer.reset()

      assert t.duration == 10_000
      assert t.accumulated == 0
      assert t.started_at == nil
      assert t.running == false
    end

    test "reset/2 changes the duration" do
      t = Timer.new(10_000) |> Timer.reset(20_000)
      assert t.duration == 20_000
      assert t.accumulated == 0
      assert t.running == false
    end
  end

  describe "elapsed/2" do
    test "returns accumulated when not running" do
      t = %Timer{duration: 10_000, accumulated: 3000, running: false}
      assert Timer.elapsed(t, 9999) == 3000
    end

    test "returns accumulated + (now - started_at) when running" do
      t = Timer.new(10_000) |> Timer.start(1000)
      assert Timer.elapsed(t, 5000) == 4000
    end

    test "accumulates across start/stop cycles" do
      t =
        Timer.new(10_000)
        |> Timer.start(0)
        |> Timer.stop(3000)
        |> Timer.start(10_000)

      assert Timer.elapsed(t, 15_000) == 8000
    end
  end

  describe "remaining/2" do
    test "returns duration - elapsed, floored at 0" do
      t = Timer.new(10_000) |> Timer.start(0)
      assert Timer.remaining(t, 3000) == 7000
    end

    test "returns 0 when timer has exceeded duration" do
      t = Timer.new(10_000) |> Timer.start(0)
      assert Timer.remaining(t, 20_000) == 0
    end

    test "returns 0 when exactly at duration" do
      t = Timer.new(10_000) |> Timer.start(0)
      assert Timer.remaining(t, 10_000) == 0
    end
  end

  describe "finished?/2" do
    test "returns true when remaining is 0" do
      t = Timer.new(10_000) |> Timer.start(0)
      assert Timer.finished?(t, 10_000) == true
      assert Timer.finished?(t, 20_000) == true
    end

    test "returns false when time remains" do
      t = Timer.new(10_000) |> Timer.start(0)
      refute Timer.finished?(t, 5000)
    end
  end

  describe "full lifecycle" do
    test "start → partial elapsed → stop → start → accumulated elapsed" do
      t = Timer.new(60_000)

      t = Timer.start(t, 0)
      assert Timer.remaining(t, 10_000) == 50_000

      t = Timer.stop(t, 10_000)
      assert t.accumulated == 10_000
      assert t.running == false

      t = Timer.start(t, 20_000)
      assert Timer.elapsed(t, 25_000) == 15_000
      assert Timer.remaining(t, 25_000) == 45_000

      assert Timer.finished?(t, 25_000) == false
      assert Timer.finished?(t, 80_000) == true
    end
  end
end
