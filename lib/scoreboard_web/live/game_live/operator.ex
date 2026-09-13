defmodule ScoreboardWeb.GameLive.Operator do
  use ScoreboardWeb, :live_view
  import ScoreboardWeb.GameComponents

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    if connected?(socket), do: GameServer.subscribe(game_id)

    try do
      case current_or_restored_snapshot(game_id) do
        {:ok, snapshot} ->
          {:ok, assign(socket, game_id: game_id, snapshot: snapshot)}

        {:error, _reason} ->
          {:ok,
           socket
           |> put_flash(:error, "Match could not be loaded. Check the game ID and local storage.")
           |> push_navigate(to: ~p"/")}
      end
    catch
      :exit, _ -> {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  defp current_or_restored_snapshot(game_id) do
    case Registry.lookup(GameRegistry, game_id) do
      [] ->
        with {:ok, _pid} <- GameServer.restore_game(game_id) do
          GameServer.snapshot(game_id)
        end

      _ ->
        GameServer.snapshot(game_id)
    end
  end

  @impl true
  def handle_info({:game_update, snapshot}, socket) do
    {:noreply, assign(socket, snapshot: snapshot)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("resume_recovered", _, socket) do
    safe_game_call(socket, fn -> GameServer.resume_recovered(socket.assigns.game_id) end)
  end

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
    case {team, Integer.parse(points)} do
      {team, {points_int, ""}} when team in ["home", "away"] and points_int != 0 ->
        safe_game_call(socket, fn ->
          GameServer.add_score(
            socket.assigns.game_id,
            if(team == "home", do: :home, else: :away),
            points_int
          )
        end)

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid points value")}
    end
  end

  def handle_event("keydown", %{"key" => key} = params, socket) do
    # Phoenix doesn't include boolean false values in params, so use Map.get with default
    shift? = Map.get(params, "shiftKey", false)
    code = Map.get(params, "code", key)

    socket =
      if socket.assigns.snapshot.recovery_required do
        put_flash(socket, :error, "Check the saved clocks and resume the recovered match first.")
      else
        handle_key(socket, key, code, shift?)
      end

    {:noreply, socket}
  end

  # Use 'code' for number keys - it gives the physical key (e.g., "Digit1") regardless of Shift
  defp handle_key(socket, _key, "Digit" <> digit_str, shift?) do
    digit =
      case Integer.parse(digit_str) do
        {value, ""} -> value
        _ -> nil
      end

    if digit in 1..4 do
      team = if shift?, do: :away, else: :home

      {_, socket} =
        safe_game_call(socket, fn -> GameServer.add_score(socket.assigns.game_id, team, digit) end)

      socket
    else
      socket
    end
  end

  defp handle_key(socket, " ", _code, _shift) do
    case socket.assigns.snapshot.phase do
      :lineup -> key_call(socket, &GameServer.start_jam/1)
      :jam_running -> key_call(socket, &GameServer.end_jam/1)
      _ -> socket
    end
  end

  defp handle_key(socket, "t", _code, false), do: key_call(socket, &GameServer.call_timeout/1)

  defp handle_key(socket, "e", _code, false) do
    case socket.assigns.snapshot do
      %{phase: :timeout} ->
        key_call(socket, &GameServer.end_timeout/1)

      %{phase: phase, period: 1} when phase in [:lineup, :jam_running] ->
        key_call(socket, &GameServer.end_period/1)

      %{phase: phase, period: 2} when phase in [:lineup, :jam_running] ->
        key_call(socket, &GameServer.end_game/1)

      _ ->
        socket
    end
  end

  defp handle_key(socket, _key, _code, _shift), do: socket

  defp key_call(socket, fun) do
    {_, socket} = safe_game_call(socket, fn -> fun.(socket.assigns.game_id) end)
    socket
  end

  defp safe_game_call(socket, fun) do
    try do
      case fun.() do
        {:ok, snapshot} ->
          {:noreply, socket |> clear_flash(:error) |> assign(:snapshot, snapshot)}

        {:error, :storage_unavailable} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Action not saved. Check local storage and retry; the action was not applied."
           )}

        {:error, :period_expired} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Period clock expired. Confirm the period end with the officials."
           )}

        {:error, :recovery_required} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Check the saved clocks and resume the recovered match first."
           )}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "This action could not be applied.")}

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
