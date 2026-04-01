defmodule ScoreboardWeb.GameLive.Index do
  use ScoreboardWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, game_id: nil)}
  end

  @impl true
  def handle_event("create_game", _params, socket) do
    game_id = generate_game_id()

    case GameServer.start_game(game_id) do
      {:ok, _pid} ->
        {:noreply, push_navigate(socket, to: ~p"/games/#{game_id}/operator")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create game: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("join_game", %{"game_id" => game_id}, socket) do
    case GameServer.snapshot(game_id) do
      {:ok, _snapshot} ->
        {:noreply, push_navigate(socket, to: ~p"/games/#{game_id}/scoreboard")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Game not found")}
    end
  end

  defp generate_game_id do
    :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false) |> String.downcase()
  end
end
