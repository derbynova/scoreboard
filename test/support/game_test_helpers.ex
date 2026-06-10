defmodule Scoreboard.GameTestHelpers do
  def cleanup_game_processes do
    for {pid, _} <- DynamicSupervisor.which_children(GameServer.Runtime.Supervisor) do
      ref = Process.monitor(pid)
      DynamicSupervisor.terminate_child(GameServer.Runtime.Supervisor, pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _} -> :ok
      after
        1000 -> Process.exit(pid, :kill)
      end
    end
  end
end
