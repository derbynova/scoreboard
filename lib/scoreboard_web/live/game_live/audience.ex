defmodule ScoreboardWeb.GameLive.Audience do
  use ScoreboardWeb, :live_view

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    try do
      case GameServer.snapshot(game_id) do
        {:ok, snapshot} ->
          GameServer.subscribe(game_id)
          {:ok, assign(socket, game_id: game_id, snapshot: snapshot)}

        {:error, _reason} ->
          {:ok, push_navigate(socket, to: ~p"/")}
      end
    catch
      :exit, _ -> {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_info({:game_update, snapshot}, socket) do
    {:noreply, assign(socket, snapshot: snapshot)}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def terminate(_reason, socket) do
    if game_id = socket.assigns[:game_id] do
      GameServer.unsubscribe(game_id)
    end

    :ok
  end
end
