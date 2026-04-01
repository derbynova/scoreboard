defmodule ScoreboardWeb.GameLive.Operator do
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
  def handle_event("start_period", _, socket) do
    GameServer.start_period(socket.assigns.game_id)
    {:noreply, socket}
  end

  def handle_event("start_jam", _, socket) do
    GameServer.start_jam(socket.assigns.game_id)
    {:noreply, socket}
  end

  def handle_event("end_jam", _, socket) do
    GameServer.end_jam(socket.assigns.game_id)
    {:noreply, socket}
  end

  def handle_event("call_timeout", _, socket) do
    GameServer.call_timeout(socket.assigns.game_id)
    {:noreply, socket}
  end

  def handle_event("end_timeout", _, socket) do
    GameServer.end_timeout(socket.assigns.game_id)
    {:noreply, socket}
  end

  def handle_event("end_period", _, socket) do
    GameServer.end_period(socket.assigns.game_id)
    {:noreply, socket}
  end

  def handle_event("end_game", _, socket) do
    GameServer.end_game(socket.assigns.game_id)
    {:noreply, socket}
  end

  def handle_event("score", %{"team" => team, "points" => points}, socket) do
    GameServer.add_score(socket.assigns.game_id, String.to_atom(team), points)
    {:noreply, socket}
  end

  def handle_event("keydown", %{"key" => key, "shiftKey" => shift?}, socket) do
    socket = handle_key(socket, key, shift?)
    {:noreply, socket}
  end

  defp handle_key(socket, " ", _shift) do
    phase = socket.assigns.snapshot.phase
    if phase == :lineup, do: GameServer.start_jam(socket.assigns.game_id)
    if phase == :jam_running, do: GameServer.end_jam(socket.assigns.game_id)
    socket
  end

  defp handle_key(socket, "t", false) do
    GameServer.call_timeout(socket.assigns.game_id)
    socket
  end

  defp handle_key(socket, "e", false) do
    phase = socket.assigns.snapshot.phase
    if phase == :timeout, do: GameServer.end_timeout(socket.assigns.game_id)
    if phase == :jam_running or phase == :lineup, do: maybe_end(socket)
    socket
  end

  defp handle_key(socket, <<digit::8>>, false) when digit in ?1..?4 do
    GameServer.add_score(socket.assigns.game_id, :home, digit - ?0)
    socket
  end

  defp handle_key(socket, <<digit::8>>, true) when digit in ?1..?4 do
    GameServer.add_score(socket.assigns.game_id, :away, digit - ?0)
    socket
  end

  defp handle_key(socket, _key, _shift), do: socket

  defp maybe_end(socket) do
    %{snapshot: %{period: period}} = socket.assigns
    if period == 1, do: GameServer.end_period(socket.assigns.game_id)
    if period == 2, do: GameServer.end_game(socket.assigns.game_id)
    socket
  end

  def format_clock(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    :io_lib.format("~2..0B:~2..0B", [minutes, secs]) |> IO.iodata_to_binary()
  end

  @impl true
  def terminate(_reason, socket) do
    GameServer.unsubscribe(socket.assigns.game_id)
    :ok
  end
end
