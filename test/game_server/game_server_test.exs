defmodule GameServerTest do
  use ExUnit.Case, async: false

  setup do
    on_exit(fn ->
      for {pid, _} <- DynamicSupervisor.which_children(GameServer.Runtime.Supervisor) do
        DynamicSupervisor.terminate_child(GameServer.Runtime.Supervisor, pid)
      end
    end)

    :ok
  end

  describe "start_game/1 and stop_game/1" do
    test "starts and stops a game process" do
      assert {:ok, pid} = GameServer.start_game("facade-1")
      assert [{_pid, _}] = Registry.lookup(GameRegistry, "facade-1")

      assert :ok = GameServer.stop_game("facade-1")
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}
      assert [] = Registry.lookup(GameRegistry, "facade-1")
    end

    test "start_game returns existing pid if already started" do
      {:ok, pid1} = GameServer.start_game("facade-2")
      {:ok, pid2} = GameServer.start_game("facade-2")
      assert pid1 == pid2
    end

    test "stop_game returns error for unknown game" do
      assert {:error, :not_found} = GameServer.stop_game("nonexistent")
    end
  end

  describe "subscribe/1 and unsubscribe/1" do
    test "receives broadcasts after subscribe" do
      {:ok, _} = GameServer.start_game("facade-sub")
      GameServer.subscribe("facade-sub")

      {:ok, _} = GameServer.start_period("facade-sub")
      assert_received {:game_update, %{phase: :lineup}}
    end

    test "stops receiving after unsubscribe" do
      {:ok, _} = GameServer.start_game("facade-unsub")
      GameServer.subscribe("facade-unsub")

      {:ok, _} = GameServer.start_period("facade-unsub")
      assert_received {:game_update, _}

      GameServer.unsubscribe("facade-unsub")
      {:ok, _} = GameServer.start_jam("facade-unsub")
      refute_received {:game_update, _}
    end
  end

  describe "topic/1" do
    test "returns the pubsub topic string" do
      assert GameServer.topic("abc") == "game:abc"
    end
  end

  describe "transitions via facade" do
    test "full game lifecycle" do
      {:ok, _} = GameServer.start_game("facade-full")

      assert {:ok, %{phase: :lineup, period: 1}} = GameServer.start_period("facade-full")
      assert {:ok, %{phase: :jam_running, jam_number: 1}} = GameServer.start_jam("facade-full")
      assert {:ok, %{score_home: 3}} = GameServer.add_score("facade-full", :home, 3)
      assert {:ok, %{phase: :lineup}} = GameServer.end_jam("facade-full")
      assert {:ok, %{phase: :halftime}} = GameServer.end_period("facade-full")
      assert {:ok, %{phase: :lineup, period: 2}} = GameServer.start_period("facade-full")
      assert {:ok, %{phase: :jam_running}} = GameServer.start_jam("facade-full")
      assert {:ok, %{phase: :final}} = GameServer.end_game("facade-full")
    end

    test "timeout cycle" do
      {:ok, _} = GameServer.start_game("facade-to")

      GameServer.start_period("facade-to")
      GameServer.start_jam("facade-to")

      assert {:ok, %{phase: :timeout}} = GameServer.call_timeout("facade-to")
      assert {:ok, %{phase: :lineup}} = GameServer.end_timeout("facade-to")
    end
  end

  describe "snapshot/1" do
    test "returns current state" do
      {:ok, _} = GameServer.start_game("facade-snap")

      assert {:ok, %{phase: :initial}} = GameServer.snapshot("facade-snap")
    end
  end

  describe "error handling via facade" do
    test "invalid transition returns error tuple" do
      {:ok, _} = GameServer.start_game("facade-err")

      assert {:error, :invalid_transition, :start_jam, :initial} =
               GameServer.start_jam("facade-err")
    end
  end

  describe "multiple games in parallel" do
    test "independent game states" do
      {:ok, _} = GameServer.start_game("parallel-1")
      {:ok, _} = GameServer.start_game("parallel-2")

      GameServer.start_period("parallel-1")
      GameServer.start_jam("parallel-1")
      GameServer.add_score("parallel-1", :home, 5)

      {:ok, snap1} = GameServer.snapshot("parallel-1")
      {:ok, snap2} = GameServer.snapshot("parallel-2")

      assert snap1.phase == :jam_running
      assert snap1.score_home == 5
      assert snap2.phase == :initial
      assert snap2.score_home == 0
    end

    test "subscribing to one game does not receive other game updates" do
      {:ok, _} = GameServer.start_game("parallel-a")
      {:ok, _} = GameServer.start_game("parallel-b")

      GameServer.subscribe("parallel-a")

      GameServer.start_period("parallel-b")
      refute_received {:game_update, _}

      GameServer.start_period("parallel-a")
      assert_received {:game_update, %{phase: :lineup}}
    end
  end
end
