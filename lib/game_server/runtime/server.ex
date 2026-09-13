defmodule GameServer.Runtime.Server do
  use GenServer, restart: :transient
  require Logger

  alias GameServer.EventStore
  alias GameServer.Impl.{Checkpoint, Game}

  @tick_ms 100
  @actions [
    :start_period,
    :start_jam,
    :end_jam,
    :call_timeout,
    :end_timeout,
    :end_period,
    :end_game
  ]
  defstruct [:game, :last_broadcasted_snapshot, sequence: 0, ticking: false]

  def start_link(game_id), do: GenServer.start_link(__MODULE__, game_id, name: via(game_id))
  def topic(game_id), do: "game:#{game_id}"

  @impl true
  def init(game_id) do
    case EventStore.load(game_id) do
      {:ok, nil, 0} ->
        game = Game.new(game_id)

        case EventStore.append(game, 1, "create", %{}, now()) do
          {:ok, _} -> {:ok, %__MODULE__{game: game, sequence: 1}}
          {:error, reason} -> {:stop, {:storage_unavailable, reason}}
        end

      {:ok, game, sequence} ->
        {:ok, %__MODULE__{game: game, sequence: sequence}, {:continue, :restored}}

      {:error, reason} ->
        {:stop, {:recovery_failed, reason}}
    end
  end

  @impl true
  def handle_continue(:restored, state) do
    {:noreply, broadcast(state, Game.snapshot(state.game, now()))}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, {:ok, Game.snapshot(state.game, now())}, state}
  end

  def handle_call(:resume_recovered, _from, state) do
    timestamp = now()
    commit(Checkpoint.resume(state.game, timestamp), state, "resume_recovered", %{}, timestamp)
  end

  def handle_call({:correct_clock, clock, remaining_ms, context}, _from, state) do
    timestamp = now()
    {current, _snapshot} = Game.expire_clocks(state.game, timestamp)
    result = Game.correct_clock(current, clock, remaining_ms, timestamp, context)

    payload =
      case result do
        {:error, _} ->
          %{}

        {_game, _snapshot} ->
          before = Map.fetch!(Game.clock_details(current, timestamp), clock)

          %{
            "clock" => Atom.to_string(clock),
            "before_ms" => before.remaining_ms,
            "after_ms" => remaining_ms,
            "running" => before.running,
            "resume_on_confirmation" => before.resume_on_confirmation,
            "phase" => Atom.to_string(state.game.phase),
            "period" => state.game.period,
            "jam_number" => state.game.jam_number
          }
      end

    commit(result, state, "correct_clock", payload, timestamp)
  end

  def handle_call(_command, _from, %{game: %{recovery_clocks: [_ | _]}} = state) do
    {:reply, {:error, :recovery_required}, state}
  end

  def handle_call({:score, team, points}, _from, state)
      when team in [:home, :away] and is_integer(points) do
    timestamp = now()

    commit(
      Game.score(state.game, team, points, timestamp),
      state,
      "score",
      %{"team" => Atom.to_string(team), "points" => points},
      timestamp
    )
  end

  def handle_call({:call_timeout, caller}, _from, state)
      when caller in [nil, :home, :away, :officials] do
    timestamp = now()

    commit(
      Game.call_timeout(state.game, timestamp),
      state,
      "call_timeout",
      %{"caller" => if(caller, do: Atom.to_string(caller), else: nil)},
      timestamp
    )
  end

  def handle_call(action, _from, state) when action in @actions do
    timestamp = now()

    commit(
      apply(Game, action, [state.game, timestamp]),
      state,
      Atom.to_string(action),
      %{},
      timestamp
    )
  end

  def handle_call(_, _from, state), do: {:reply, {:error, :invalid_command}, state}

  defp commit({:error, _, _, _} = error, state, _, _, _), do: {:reply, error, state}
  defp commit({:error, _} = error, state, _, _, _), do: {:reply, error, state}

  defp commit({game, snapshot}, state, action, payload, timestamp) do
    case EventStore.append(game, state.sequence + 1, action, payload, timestamp) do
      {:ok, event} ->
        state =
          %{state | game: game, sequence: state.sequence + 1}
          |> ensure_ticking()
          |> broadcast(snapshot)

        if action == "correct_clock" do
          Phoenix.PubSub.broadcast(
            Scoreboard.PubSub,
            topic(game.id),
            {:clock_corrected, event}
          )
        end

        {:reply, {:ok, snapshot}, state}

      {:error, reason} ->
        Logger.error("Game action was not saved: #{inspect(reason)}")
        {:reply, {:error, :storage_unavailable}, state}
    end
  end

  @impl true
  def handle_info(:tick, state) do
    timestamp = now()
    {game, snapshot} = Game.expire_clocks(state.game, timestamp)

    state =
      cond do
        game != state.game ->
          {:reply, _result, updated} =
            commit({game, snapshot}, state, "expire_clocks", %{}, timestamp)

          updated

        snapshot != state.last_broadcasted_snapshot ->
          broadcast(state, snapshot)

        true ->
          state
      end

    {:noreply, ensure_ticking(%{state | ticking: false})}
  end

  defp ensure_ticking(%{ticking: true} = state), do: state

  defp ensure_ticking(state) do
    if Game.ticking?(state.game) do
      Process.send_after(self(), :tick, @tick_ms)
      %{state | ticking: true}
    else
      state
    end
  end

  defp broadcast(state, snapshot) do
    Phoenix.PubSub.broadcast(Scoreboard.PubSub, topic(state.game.id), {:game_update, snapshot})
    %{state | last_broadcasted_snapshot: snapshot}
  end

  defp now, do: System.monotonic_time(:millisecond)
  defp via(game_id), do: {:via, Registry, {GameRegistry, game_id}}
end
