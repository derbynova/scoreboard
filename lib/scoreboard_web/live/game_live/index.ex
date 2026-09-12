defmodule ScoreboardWeb.GameLive.Index do
  use ScoreboardWeb, :live_view
  alias GameServer.EventStore

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(form: to_form(%{"game_id" => ""}), cursor: nil, storage_error: false)
      |> stream(:games, [])
      |> load_games(true)

    {:ok, socket}
  end

  @impl true
  def handle_event("create_game", _params, socket) do
    game_id =
      :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false) |> String.downcase()

    case GameServer.start_game(game_id) do
      {:ok, _pid} ->
        {:noreply, push_navigate(socket, to: ~p"/games/#{game_id}/operator")}

      {:error, _reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Could not create the match. Check local storage and try again."
         )}
    end
  end

  def handle_event("refresh_games", _, socket), do: {:noreply, load_games(socket, true)}
  def handle_event("load_more", _, %{assigns: %{cursor: nil}} = socket), do: {:noreply, socket}
  def handle_event("load_more", _, socket), do: {:noreply, load_games(socket, false)}

  def handle_event("join_game", %{"game_id" => game_id}, socket) do
    game_id = String.trim(game_id)
    socket = assign(socket, :form, to_form(%{"game_id" => game_id}))

    case GameServer.saved_or_live_snapshot(game_id) do
      {:ok, _} ->
        {:noreply, push_navigate(socket, to: ~p"/games/#{game_id}/scoreboard")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Match not found or could not be loaded.")}
    end
  end

  defp load_games(socket, reset?) do
    cursor = if reset?, do: nil, else: socket.assigns.cursor

    case EventStore.list_saved_games(cursor) do
      {:ok, games, cursor} ->
        socket
        |> assign(cursor: cursor, storage_error: false)
        |> stream(:games, games, reset: reset?)

      {:error, _} ->
        assign(socket, :storage_error, true)
    end
  end

  defp phase_label(:initial), do: "Not started"
  defp phase_label(:final), do: "Finished"
  defp phase_label(:halftime), do: "Halftime"
  defp phase_label(_), do: "In progress"
end
