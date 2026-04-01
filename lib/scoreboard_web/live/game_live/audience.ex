defmodule ScoreboardWeb.GameLive.Audience do
  use ScoreboardWeb, :live_view

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    case GameServer.snapshot(game_id) do
      {:ok, snapshot} ->
        GameServer.subscribe(game_id)
        {:ok, assign(socket, game_id: game_id, snapshot: snapshot)}

      {:error, _reason} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_info({:game_update, snapshot}, socket) do
    {:noreply, assign(socket, snapshot: snapshot)}
  end

  @impl true
  def terminate(_reason, socket) do
    GameServer.unsubscribe(socket.assigns.game_id)
    :ok
  end

  def format_clock(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    :io_lib.format("~2..0B:~2..0B", [minutes, secs]) |> IO.iodata_to_binary()
  end
end
