defmodule ScoreboardWeb.GameLive.Operator do
  use ScoreboardWeb, :live_view
  import ScoreboardWeb.GameComponents

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

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("start_period", _, socket) do
    safe_game_call(socket, fn -> GameServer.start_period(socket.assigns.game_id) end)
  end

  def handle_event("start_jam", _, socket) do
    safe_game_call(socket, fn -> GameServer.start_jam(socket.assigns.game_id) end)
  end

  def handle_event("end_jam", _, socket) do
    safe_game_call(socket, fn -> GameServer.end_jam(socket.assigns.game_id) end)
  end

  def handle_event("call_timeout", _, socket) do
    safe_game_call(socket, fn -> GameServer.call_timeout(socket.assigns.game_id) end)
  end

  def handle_event("call_or", _, socket) do
    {:noreply, put_flash(socket, :info, "Official Review not yet implemented")}
  end

  def handle_event("end_timeout", _, socket) do
    safe_game_call(socket, fn -> GameServer.end_timeout(socket.assigns.game_id) end)
  end

  def handle_event("end_period", _, socket) do
    safe_game_call(socket, fn -> GameServer.end_period(socket.assigns.game_id) end)
  end

  def handle_event("end_game", _, socket) do
    safe_game_call(socket, fn -> GameServer.end_game(socket.assigns.game_id) end)
  end

  def handle_event("score", %{"team" => team, "points" => points}, socket) do
    case Integer.parse(points) do
      {points_int, ""} when points_int != 0 ->
        safe_game_call(socket, fn ->
          GameServer.add_score(socket.assigns.game_id, String.to_existing_atom(team), points_int)
        end)

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid points value")}
    end
  end

  def handle_event("keydown", %{"key" => key} = params, socket) do
    # Phoenix doesn't include boolean false values in params, so use Map.get with default
    shift? = Map.get(params, "shiftKey", false)
    code = Map.get(params, "code", key)
    socket = handle_key(socket, key, code, shift?)
    {:noreply, socket}
  end

  # Use 'code' for number keys - it gives the physical key (e.g., "Digit1") regardless of Shift
  defp handle_key(socket, _key, "Digit" <> digit_str, shift?) do
    digit = String.to_integer(digit_str)

    if digit in 1..4 do
      team = if shift?, do: :away, else: :home
      GameServer.add_score(socket.assigns.game_id, team, digit)
    end

    socket
  end

  # Handle key codes for special keys using 'key' property
  defp handle_key(socket, " ", _code, _shift) do
    phase = socket.assigns.snapshot.phase
    if phase == :lineup, do: GameServer.start_jam(socket.assigns.game_id)
    if phase == :jam_running, do: GameServer.end_jam(socket.assigns.game_id)
    socket
  end

  defp handle_key(socket, "t", _code, false) do
    GameServer.call_timeout(socket.assigns.game_id)
    socket
  end

  defp handle_key(socket, "e", _code, false) do
    phase = socket.assigns.snapshot.phase
    if phase == :timeout, do: GameServer.end_timeout(socket.assigns.game_id)
    if phase == :jam_running or phase == :lineup, do: maybe_end(socket)
    socket
  end

  defp handle_key(socket, _key, _code, _shift), do: socket

  defp maybe_end(socket) do
    %{snapshot: %{period: period}} = socket.assigns
    if period == 1, do: GameServer.end_period(socket.assigns.game_id)
    if period == 2, do: GameServer.end_game(socket.assigns.game_id)
    socket
  end

  defp safe_game_call(socket, fun) do
    try do
      case fun.() do
        {:ok, _snapshot} ->
          {:noreply, socket}

        {:error, :invalid_transition, action, phase} ->
          {:noreply, put_flash(socket, :error, "Cannot #{action} in #{phase} phase")}
      end
    catch
      :exit, _reason ->
        {:noreply, push_navigate(socket, to: ~p"/")}
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if game_id = socket.assigns[:game_id] do
      GameServer.unsubscribe(game_id)
    end

    :ok
  end
end
