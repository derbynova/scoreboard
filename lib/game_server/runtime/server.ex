defmodule GameServer.Runtime.Server do
  use GenServer, restart: :transient

  alias GameServer.Impl.Game

  @tick_ms 100

  defstruct [:game, :last_broadcasted_snapshot, ticking: false]

  def start_link(game_id) do
    GenServer.start_link(__MODULE__, game_id, name: via(game_id))
  end

  def topic(game_id), do: "game:#{game_id}"

  @impl true
  def init(game_id) do
    {:ok, %__MODULE__{game: Game.new(game_id)}}
  end

  @impl true
  def handle_call(:start_period, _from, state) do
    case Game.start_period(state.game, now()) do
      {updated, snapshot} ->
        state = %{state | game: updated} |> ensure_ticking() |> broadcast(snapshot)
        {:reply, {:ok, snapshot}, state}

      {:error, :invalid_transition, _, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:start_jam, _from, state) do
    case Game.start_jam(state.game, now()) do
      {updated, snapshot} ->
        state = %{state | game: updated} |> ensure_ticking() |> broadcast(snapshot)
        {:reply, {:ok, snapshot}, state}

      {:error, :invalid_transition, _, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:end_jam, _from, state) do
    case Game.end_jam(state.game, now()) do
      {updated, snapshot} ->
        state = %{state | game: updated} |> ensure_ticking() |> broadcast(snapshot)
        {:reply, {:ok, snapshot}, state}

      {:error, :invalid_transition, _, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:call_timeout, _caller}, _from, state) do
    case Game.call_timeout(state.game, now()) do
      {updated, snapshot} ->
        state = %{state | game: updated} |> ensure_ticking() |> broadcast(snapshot)
        {:reply, {:ok, snapshot}, state}

      {:error, :invalid_transition, _, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:end_timeout, _from, state) do
    case Game.end_timeout(state.game, now()) do
      {updated, snapshot} ->
        state = %{state | game: updated} |> ensure_ticking() |> broadcast(snapshot)
        {:reply, {:ok, snapshot}, state}

      {:error, :invalid_transition, _, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:end_period, _from, state) do
    case Game.end_period(state.game, now()) do
      {updated, snapshot} ->
        state = %{state | game: updated} |> maybe_stop_ticking() |> broadcast(snapshot)
        {:reply, {:ok, snapshot}, state}

      {:error, :invalid_transition, _, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:end_game, _from, state) do
    case Game.end_game(state.game, now()) do
      {updated, snapshot} ->
        state = %{state | game: updated} |> maybe_stop_ticking() |> broadcast(snapshot)
        {:reply, {:ok, snapshot}, state}

      {:error, :invalid_transition, _, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:score, team, points}, _from, state) do
    case Game.score(state.game, team, points, now()) do
      {updated, snapshot} ->
        state = %{state | game: updated} |> broadcast(snapshot)
        {:reply, {:ok, snapshot}, state}

      {:error, :invalid_transition, _, _} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, {:ok, Game.snapshot(state.game, now())}, state}
  end

  @impl true
  def handle_info(:tick, state) do
    now = now()
    snapshot = Game.snapshot(state.game, now)

    state =
      if snapshot_changed?(state.last_broadcasted_snapshot, snapshot) do
        Phoenix.PubSub.broadcast(
          Scoreboard.PubSub,
          topic(state.game.id),
          {:game_update, snapshot}
        )

        %{state | last_broadcasted_snapshot: snapshot}
      else
        state
      end

    state =
      if state.game.phase in active_phases() do
        schedule_tick()
        %{state | ticking: true}
      else
        %{state | ticking: false}
      end

    {:noreply, state}
  end

  defp ensure_ticking(%{ticking: true} = state), do: state

  defp ensure_ticking(state) do
    schedule_tick()
    %{state | ticking: true}
  end

  defp maybe_stop_ticking(%{game: %{phase: phase}} = state)
       when phase in [:halftime, :final, :initial] do
    %{state | ticking: false}
  end

  defp maybe_stop_ticking(state), do: state

  defp broadcast(state, snapshot) do
    Phoenix.PubSub.broadcast(
      Scoreboard.PubSub,
      topic(state.game.id),
      {:game_update, snapshot}
    )

    %{state | last_broadcasted_snapshot: snapshot}
  end

  defp snapshot_changed?(nil, _new), do: true

  defp snapshot_changed?(old, new) do
    old.period_clock_s != new.period_clock_s or
      old.lineup_clock_s != new.lineup_clock_s or
      old.jam_clock_s != new.jam_clock_s or
      old.timeout_clock_s != new.timeout_clock_s or
      old.phase != new.phase or
      old.score_home != new.score_home or
      old.score_away != new.score_away
  end

  defp active_phases, do: [:lineup, :jam_running, :timeout]

  defp now, do: System.monotonic_time(:millisecond)
  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_ms)
  defp via(game_id), do: {:via, Registry, {GameRegistry, game_id}}
end
