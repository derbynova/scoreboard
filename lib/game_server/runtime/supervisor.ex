defmodule GameServer.Runtime.Supervisor do
  use DynamicSupervisor

  def start_link(_) do
    DynamicSupervisor.start_link(name: __MODULE__, strategy: :one_for_one)
  end

  def start_game(game_id) do
    DynamicSupervisor.start_child(__MODULE__, {GameServer.Runtime.Server, game_id})
  end

  def stop_game(game_id) do
    case Registry.lookup(GameRegistry, game_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
