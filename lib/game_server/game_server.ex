defmodule GameServer do
  alias GameServer.Runtime.Server

  def start_game(game_id) do
    case GameServer.Runtime.Supervisor.start_game(game_id) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  def stop_game(game_id) do
    GameServer.Runtime.Supervisor.stop_game(game_id)
  end

  def subscribe(game_id) do
    Phoenix.PubSub.subscribe(Scoreboard.PubSub, topic(game_id))
  end

  def unsubscribe(game_id) do
    Phoenix.PubSub.unsubscribe(Scoreboard.PubSub, topic(game_id))
  end

  defdelegate topic(game_id), to: Server

  def start_period(game_id), do: GenServer.call(via(game_id), :start_period)
  def start_jam(game_id), do: GenServer.call(via(game_id), :start_jam)
  def end_jam(game_id), do: GenServer.call(via(game_id), :end_jam)

  def call_timeout(game_id, caller \\ nil),
    do: GenServer.call(via(game_id), {:call_timeout, caller})

  def end_timeout(game_id), do: GenServer.call(via(game_id), :end_timeout)
  def end_period(game_id), do: GenServer.call(via(game_id), :end_period)
  def end_game(game_id), do: GenServer.call(via(game_id), :end_game)
  def add_score(game_id, team, points), do: GenServer.call(via(game_id), {:score, team, points})
  def snapshot(game_id), do: GenServer.call(via(game_id), :snapshot)

  defp via(game_id), do: {:via, Registry, {GameRegistry, game_id}}
end
