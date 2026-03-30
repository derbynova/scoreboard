defmodule GameServer.Runtime.ServerTest do
  use ExUnit.Case, async: false

  alias GameServer.Runtime.Server

  setup do
    on_exit(fn ->
      for {pid, _} <- DynamicSupervisor.which_children(GameServer.Runtime.Supervisor) do
        DynamicSupervisor.terminate_child(GameServer.Runtime.Supervisor, pid)
      end
    end)

    :ok
  end

  describe "start_link/1" do
    test "starts a game process registered in Registry" do
      assert {:ok, pid} = Server.start_link("test-game-1")
      assert [{^pid, _}] = Registry.lookup(GameRegistry, "test-game-1")
    end
  end

  describe "transitions" do
    test "start_period returns ok with snapshot" do
      {:ok, _pid} = Server.start_link("g1")

      assert {:ok, snap} = GenServer.call(via("g1"), :start_period)
      assert snap.phase == :lineup
      assert snap.period == 1
    end

    test "start_jam → end_jam cycle" do
      {:ok, _pid} = Server.start_link("g2")
      GenServer.call(via("g2"), :start_period)

      assert {:ok, snap} = GenServer.call(via("g2"), :start_jam)
      assert snap.phase == :jam_running
      assert snap.jam_number == 1

      assert {:ok, snap} = GenServer.call(via("g2"), :end_jam)
      assert snap.phase == :lineup
    end

    test "call_timeout → end_timeout cycle" do
      {:ok, _pid} = Server.start_link("g3")
      GenServer.call(via("g3"), :start_period)
      GenServer.call(via("g3"), :start_jam)

      assert {:ok, snap} = GenServer.call(via("g3"), {:call_timeout, nil})
      assert snap.phase == :timeout

      assert {:ok, snap} = GenServer.call(via("g3"), :end_timeout)
      assert snap.phase == :lineup
    end

    test "end_period transitions to halftime" do
      {:ok, _pid} = Server.start_link("g4")
      GenServer.call(via("g4"), :start_period)
      GenServer.call(via("g4"), :start_jam)

      assert {:ok, snap} = GenServer.call(via("g4"), :end_period)
      assert snap.phase == :halftime
    end

    test "full game: period 1 → halftime → period 2 → final" do
      {:ok, _pid} = Server.start_link("g5")

      {:ok, _} = GenServer.call(via("g5"), :start_period)
      {:ok, _} = GenServer.call(via("g5"), :start_jam)
      {:ok, _} = GenServer.call(via("g5"), :end_jam)
      {:ok, snap} = GenServer.call(via("g5"), :end_period)
      assert snap.phase == :halftime

      {:ok, _} = GenServer.call(via("g5"), :start_period)
      {:ok, _} = GenServer.call(via("g5"), :start_jam)
      {:ok, snap} = GenServer.call(via("g5"), :end_game)
      assert snap.phase == :final
    end
  end

  describe "score" do
    test "adds points to home and away" do
      {:ok, _pid} = Server.start_link("g-score")
      GenServer.call(via("g-score"), :start_period)
      GenServer.call(via("g-score"), :start_jam)

      assert {:ok, snap} = GenServer.call(via("g-score"), {:score, :home, 3})
      assert snap.score_home == 3

      assert {:ok, snap} = GenServer.call(via("g-score"), {:score, :away, 2})
      assert snap.score_away == 2
    end
  end

  describe "snapshot" do
    test "returns current game state" do
      {:ok, _pid} = Server.start_link("g-snap")

      assert {:ok, snap} = GenServer.call(via("g-snap"), :snapshot)
      assert snap.phase == :initial
      assert snap.period == 0
    end
  end

  describe "error handling" do
    test "invalid transition returns error without crashing" do
      {:ok, pid} = Server.start_link("g-err")

      assert {:error, :invalid_transition, :start_jam, :initial} =
               GenServer.call(via("g-err"), :start_jam)

      assert Process.alive?(pid)
    end

    test "score in initial phase returns error" do
      {:ok, pid} = Server.start_link("g-err2")

      assert {:error, :invalid_transition, :score, :initial} =
               GenServer.call(via("g-err2"), {:score, :home, 1})

      assert Process.alive?(pid)
    end
  end

  describe "broadcasting" do
    test "transition broadcasts snapshot via PubSub" do
      {:ok, _pid} = Server.start_link("g-bcast")
      Phoenix.PubSub.subscribe(Scoreboard.PubSub, Server.topic("g-bcast"))

      {:ok, _} = GenServer.call(via("g-bcast"), :start_period)

      assert_received {:game_update, snap}
      assert snap.phase == :lineup
    end

    test "score broadcasts snapshot" do
      {:ok, _pid} = Server.start_link("g-bcast-score")
      GenServer.call(via("g-bcast-score"), :start_period)
      GenServer.call(via("g-bcast-score"), :start_jam)
      Phoenix.PubSub.subscribe(Scoreboard.PubSub, Server.topic("g-bcast-score"))

      {:ok, _} = GenServer.call(via("g-bcast-score"), {:score, :home, 5})

      assert_received {:game_update, snap}
      assert snap.score_home == 5
    end
  end

  describe "tick" do
    test "tick broadcasts when seconds change" do
      {:ok, _pid} = Server.start_link("g-tick")
      Phoenix.PubSub.subscribe(Scoreboard.PubSub, Server.topic("g-tick"))

      {:ok, _} = GenServer.call(via("g-tick"), :start_period)

      assert_received {:game_update, _}

      Process.sleep(150)
      assert_received {:game_update, snap}
      assert snap.period_clock_s < 1800
    end

    test "tick stops after end_game" do
      {:ok, pid} = Server.start_link("g-tick-stop")
      Phoenix.PubSub.subscribe(Scoreboard.PubSub, Server.topic("g-tick-stop"))

      GenServer.call(via("g-tick-stop"), :start_period)
      GenServer.call(via("g-tick-stop"), :start_jam)

      flush_pubsub()

      GenServer.call(via("g-tick-stop"), :end_game)

      Process.sleep(200)
      flush_pubsub()

      Process.sleep(200)
      refute_received {:game_update, _}
      assert Process.alive?(pid)
    end
  end

  defp via(game_id), do: {:via, Registry, {GameRegistry, game_id}}

  defp flush_pubsub do
    receive do
      {:game_update, _} -> flush_pubsub()
    after
      0 -> :ok
    end
  end
end
