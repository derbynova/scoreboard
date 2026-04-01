# LiveView Scoreboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect the gameserver to Phoenix LiveViews for operator control and audience display.

**Architecture:** Two separate LiveViews (Operator + Audience) subscribe to the same PubSub topic. A landing page LiveView handles game creation/joining. The gameserver's snapshot is expanded with timer running states so the UI knows which clock is active.

**Tech Stack:** Elixir, Phoenix LiveView, Tailwind CSS, daisyUI, Phoenix PubSub

---

## File Structure

### New files
- `lib/scoreboard_web/live/game_live/index.ex` — Landing page (create/join game)
- `lib/scoreboard_web/live/game_live/index.html.heex` — Landing page template
- `lib/scoreboard_web/live/game_live/operator.ex` — Operator control panel LiveView
- `lib/scoreboard_web/live/game_live/operator.html.heex` — Operator template
- `lib/scoreboard_web/live/game_live/audience.ex` — Audience display LiveView
- `lib/scoreboard_web/live/game_live/audience.html.heex` — Audience template
- `test/scoreboard_web/live/game_live_test.exs` — Integration tests for all three LiveViews

### Modified files
- `lib/game_server/impl/game.ex` — Add running booleans to `snapshot/2`
- `lib/game_server/runtime/server.ex` — Update `snapshot_changed?/2` for new fields
- `lib/scoreboard_web/router.ex` — Add LiveView routes
- `test/game_server/impl/game_test.exs` — Update snapshot test for new fields
- `assets/css/app.css` — Add scoreboard-specific styles

---

### Task 1: Expand snapshot with timer running states

**Files:**
- Modify: `lib/game_server/impl/game.ex:147-159`
- Test: `test/game_server/impl/game_test.exs:235-251`

- [ ] **Step 1: Write the failing test**

Update the snapshot test in `test/game_server/impl/game_test.exs`. Replace the existing `"returns map with all expected keys"` test:

```elixir
describe "snapshot/2" do
  test "returns map with all expected keys including running states" do
    game = Game.new("g1")
    snap = Game.snapshot(game, 0)

    assert Map.keys(snap) |> Enum.sort() ==
             ~w[jam_clock_running jam_number lineup_clock_running period period_clock_running
                phase score_away score_home timeout_clock_running
                period_clock_s lineup_clock_s jam_clock_s timeout_clock_s]a |> Enum.sort()
  end

  test "clocks are not running in initial state" do
    snap = Game.new("g1") |> Game.snapshot(0)

    refute snap.period_clock_running
    refute snap.jam_clock_running
    refute snap.lineup_clock_running
    refute snap.timeout_clock_running
  end

  test "period and lineup clocks running after start_period" do
    {_game, snap} = Game.new("g1") |> Game.start_period(0)

    assert snap.period_clock_running
    assert snap.lineup_clock_running
    refute snap.jam_clock_running
    refute snap.timeout_clock_running
  end

  test "period and jam clocks running after start_jam" do
    {_game, snap} =
      Game.new("g1") |> Game.start_period(0) |> then(fn {g, _} -> Game.start_jam(g, 1000) end)

    assert snap.period_clock_running
    assert snap.jam_clock_running
    refute snap.lineup_clock_running
    refute snap.timeout_clock_running
  end

  test "only timeout clock running during timeout" do
    {_game, snap} =
      Game.new("g1")
      |> Game.start_period(0)
      |> then(fn {g, _} -> Game.start_jam(g, 1000) end)
      |> then(fn {g, _} -> Game.call_timeout(g, 5000) end)

    refute snap.period_clock_running
    refute snap.jam_clock_running
    refute snap.lineup_clock_running
    assert snap.timeout_clock_running
  end

  test "no clocks running in final state" do
    {_game, snap} =
      Game.new("g1")
      |> Game.start_period(0)
      |> then(fn {g, _} -> Game.start_jam(g, 1000) end)
      |> then(fn {g, _} -> Game.end_game(g, 5_000_000) end)

    refute snap.period_clock_running
    refute snap.jam_clock_running
    refute snap.lineup_clock_running
    refute snap.timeout_clock_running
  end

  test "clocks count down in seconds" do
    game = Game.new("g1") |> then(fn g -> {g, _} = Game.start_period(g, 0); g end)

    snap = Game.snapshot(game, 10_000)
    assert snap.period_clock_s == 1790
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/game_server/impl/game_test.exs --only snapshot`
Expected: FAIL — `snapshot/2` does not return `*_clock_running` keys

- [ ] **Step 3: Write minimal implementation**

Update `snapshot/2` in `lib/game_server/impl/game.ex`:

```elixir
def snapshot(game, now) do
  %{
    phase: game.phase,
    period: game.period,
    jam_number: game.jam_number,
    score_home: game.score_home,
    score_away: game.score_away,
    period_clock_s: Timer.remaining(game.period_clock, now) |> div(1000),
    lineup_clock_s: Timer.remaining(game.lineup_clock, now) |> div(1000),
    jam_clock_s: Timer.remaining(game.jam_clock, now) |> div(1000),
    timeout_clock_s: Timer.remaining(game.timeout_clock, now) |> div(1000),
    period_clock_running: game.period_clock.running,
    jam_clock_running: game.jam_clock.running,
    lineup_clock_running: game.lineup_clock.running,
    timeout_clock_running: game.timeout_clock.running
  }
end
```

- [ ] **Step 4: Update snapshot_changed? in server.ex**

In `lib/game_server/runtime/server.ex`, update `snapshot_changed?/2` to include the new fields:

```elixir
defp snapshot_changed?(nil, _new), do: true

defp snapshot_changed?(old, new) do
  old.period_clock_s != new.period_clock_s or
    old.lineup_clock_s != new.lineup_clock_s or
    old.jam_clock_s != new.jam_clock_s or
    old.timeout_clock_s != new.timeout_clock_s or
    old.phase != new.phase or
    old.score_home != new.score_home or
    old.score_away != new.score_away or
    old.period_clock_running != new.period_clock_running or
    old.jam_clock_running != new.jam_clock_running or
    old.lineup_clock_running != new.lineup_clock_running or
    old.timeout_clock_running != new.timeout_clock_running
end
```

- [ ] **Step 5: Run all game tests to verify**

Run: `mix test test/game_server/`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add lib/game_server/impl/game.ex lib/game_server/runtime/server.ex test/game_server/impl/game_test.exs
git commit -m "feat: add timer running states to game snapshot"
```

---

### Task 2: Add LiveView routes

**Files:**
- Modify: `lib/scoreboard_web/router.ex`

- [ ] **Step 1: Add routes**

Replace the existing scope block in `lib/scoreboard_web/router.ex`:

```elixir
scope "/", ScoreboardWeb do
  pipe_through :browser

  get "/", PageController, :home
  live "/games/new", GameLive.Index, :new
  live "/games/:id/operator", GameLive.Operator
  live "/games/:id/scoreboard", GameLive.Audience
end
```

- [ ] **Step 2: Verify router compiles**

Run: `mix compile`
Expected: Compiles without errors (the LiveView modules don't exist yet, so it will fail at route resolution — that's expected and will be resolved in subsequent tasks)

- [ ] **Step 3: Commit**

```bash
git add lib/scoreboard_web/router.ex
git commit -m "feat: add LiveView routes for game operator and audience"
```

---

### Task 3: Landing page LiveView (Index)

**Files:**
- Create: `lib/scoreboard_web/live/game_live/index.ex`
- Create: `lib/scoreboard_web/live/game_live/index.html.heex`

- [ ] **Step 1: Create the LiveView module**

Create `lib/scoreboard_web/live/game_live/index.ex`:

```elixir
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
```

- [ ] **Step 2: Create the template**

Create `lib/scoreboard_web/live/game_live/index.html.heex`:

```heex
<div class="min-h-screen flex items-center justify-center">
  <div class="text-center space-y-8">
    <h1 class="text-4xl font-bold">DerbyNova Scoreboard</h1>
    <p class="text-base-content/70">Create a new game or join an existing one.</p>

    <div class="space-y-4">
      <.button phx-click="create_game" class="btn-primary btn-lg w-full">
        New Game
      </.button>

      <div class="divider">OR</div>

      <.form for={%{}} phx-submit="join_game" class="flex gap-2">
        <input
          type="text"
          name="game_id"
          placeholder="Enter game ID"
          class="input input-bordered flex-1"
          required
        />
        <.button type="submit">Join Game</.button>
      </.form>
    </div>
  </div>
</div>
```

- [ ] **Step 3: Verify it compiles**

Run: `mix compile`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add lib/scoreboard_web/live/
git commit -m "feat: add game index LiveView (create/join game)"
```

---

### Task 4: Audience LiveView

**Files:**
- Create: `lib/scoreboard_web/live/game_live/audience.ex`
- Create: `lib/scoreboard_web/live/game_live/audience.html.heex`
- Modify: `assets/css/app.css`

- [ ] **Step 1: Create the LiveView module**

Create `lib/scoreboard_web/live/game_live/audience.ex`:

```elixir
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
```

- [ ] **Step 2: Create the template**

Create `lib/scoreboard_web/live/game_live/audience.html.heex`:

```heex
<div class="scoreboard-audience min-h-screen flex flex-col items-center justify-center select-none" style="background:#0f0f1a;color:#fff;font-family:'Courier New',monospace">
  <div class="text-center text-sm tracking-widest opacity-60 mb-5">
    PERIOD <span class="text-lg text-white/100"><%= @snapshot.period %></span>
    <span class="mx-2">|</span>
    JAM <span class="text-lg text-white/100"><%= @snapshot.jam_number %></span>
  </div>

  <div class="flex items-center justify-center gap-14">
    <!-- Home -->
    <div class="text-center flex-1 max-w-[260px]">
      <div class="text-sm tracking-[3px] opacity-60 mb-1.5">HOME</div>
      <div class="text-[80px] font-black leading-none" style="color:#e94560"><%= @snapshot.score_home %></div>
    </div>

    <!-- Clocks -->
    <div class="text-center min-w-[200px]">
      <!-- Period clock -->
      <div class="mb-5">
        <div class="text-[10px] tracking-[2px] opacity-40 mb-0.5">PERIOD</div>
        <div class="text-[36px] font-bold leading-none"><%= format_clock(@snapshot.period_clock_s) %></div>
      </div>

      <!-- Active phase clock -->
      <div :if={@snapshot.jam_clock_running}>
        <div class="text-[10px] tracking-[2px] opacity-40 mb-0.5">JAM CLOCK</div>
        <div class="text-[56px] font-bold leading-none" style="color:#ffd700"><%= format_clock(@snapshot.jam_clock_s) %></div>
      </div>

      <div :if={@snapshot.lineup_clock_running}>
        <div class="text-[10px] tracking-[2px] opacity-40 mb-0.5">LINEUP</div>
        <div class="text-[56px] font-bold leading-none" style="color:#22d3ee"><%= format_clock(@snapshot.lineup_clock_s) %></div>
      </div>

      <div :if={@snapshot.timeout_clock_running}>
        <div class="text-[10px] tracking-[2px] opacity-40 mb-0.5">TIMEOUT</div>
        <div class="text-[56px] font-bold leading-none" style="color:#f87171"><%= format_clock(@snapshot.timeout_clock_s) %></div>
      </div>

      <div :if={!@snapshot.jam_clock_running and !@snapshot.lineup_clock_running and !@snapshot.timeout_clock_running}>
        <div class="text-[56px] font-bold leading-none opacity-20">--:--</div>
      </div>
    </div>

    <!-- Away -->
    <div class="text-center flex-1 max-w-[260px]">
      <div class="text-sm tracking-[3px] opacity-60 mb-1.5">AWAY</div>
      <div class="text-[80px] font-black leading-none" style="color:#4ea8de"><%= @snapshot.score_away %></div>
    </div>
  </div>

  <!-- Inactive clocks -->
  <div class="text-center text-xs opacity-30 mt-5 flex gap-4">
    <span :if={!@snapshot.jam_clock_running}>JAM <%= format_clock(@snapshot.jam_clock_s) %></span>
    <span :if={!@snapshot.lineup_clock_running}>LINEUP</span>
    <span :if={!@snapshot.timeout_clock_running}>TIMEOUT</span>
  </div>

  <div class="text-xs opacity-20 mt-8">Press F11 for fullscreen</div>
</div>
```

- [ ] **Step 3: Verify it compiles**

Run: `mix compile`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add lib/scoreboard_web/live/game_live/audience.ex lib/scoreboard_web/live/game_live/audience.html.heex
git commit -m "feat: add audience LiveView with real-time scoreboard display"
```

---

### Task 5: Operator LiveView

**Files:**
- Create: `lib/scoreboard_web/live/game_live/operator.ex`
- Create: `lib/scoreboard_web/live/game_live/operator.html.heex`

- [ ] **Step 1: Create the LiveView module**

Create `lib/scoreboard_web/live/game_live/operator.ex`:

```elixir
defmodule ScoreboardWeb.GameLive.Operator do
  use ScoreboardWeb, :live_view

  @impl true
  def mount(%{"id" => game_id}, _session, socket) do
    case GameServer.snapshot(game_id) do
      {:ok, snapshot} ->
        GameServer.subscribe(game_id)
        {:ok,
         assign(socket,
           game_id: game_id,
           snapshot: snapshot
         )}

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

  defp handle_key(socket, "t", false), do: tap(GameServer.call_timeout(socket.assigns.game_id)); socket
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
```

- [ ] **Step 2: Create the template**

Create `lib/scoreboard_web/live/game_live/operator.html.heex`:

```heex
<div class="min-h-screen" id="operator-view" phx-window-keydown="keydown">
  <!-- Scoreboard preview -->
  <div class="bg-base-300 rounded-xl p-4 mb-6">
    <div class="flex items-center justify-center gap-6 text-center">
      <div class="flex-1">
        <div class="text-xs tracking-widest opacity-60">HOME</div>
        <div class="text-4xl font-bold" style="color:#e94560"><%= @snapshot.score_home %></div>
      </div>
      <div class="min-w-[120px]">
        <div class="text-xs opacity-50">P<%= @snapshot.period %> | J<%= @snapshot.jam_number %></div>
        <div class="text-2xl font-bold"><%= format_clock(@snapshot.period_clock_s) %></div>
        <div :if={@snapshot.jam_clock_running} class="text-xl font-bold text-warning"><%= format_clock(@snapshot.jam_clock_s) %></div>
        <div :if={@snapshot.lineup_clock_running} class="text-xl font-bold text-info"><%= format_clock(@snapshot.lineup_clock_s) %></div>
        <div :if={@snapshot.timeout_clock_running} class="text-xl font-bold text-error"><%= format_clock(@snapshot.timeout_clock_s) %></div>
      </div>
      <div class="flex-1">
        <div class="text-xs tracking-widest opacity-60">AWAY</div>
        <div class="text-4xl font-bold" style="color:#4ea8de"><%= @snapshot.score_away %></div>
      </div>
    </div>
  </div>

  <!-- Audience display link -->
  <div class="text-center mb-6">
    <.link href={~p"/games/#{@game_id}/scoreboard"} target="_blank" class="link link-primary text-sm">
      Open Audience Display
    </.link>
  </div>

  <!-- Controls -->
  <div class="space-y-4">
    <!-- Phase controls -->
    <div :if={@snapshot.phase == :initial} class="flex justify-center">
      <.button phx-click="start_period" class="btn-lg btn-primary">Start Period 1</.button>
    </div>

    <div :if={@snapshot.phase == :lineup} class="flex justify-center gap-3">
      <.button phx-click="start_jam" class="btn-lg btn-primary">Start Jam <kbd class="kbd kbd-sm ml-1">Space</kbd></.button>
      <.button phx-click="call_timeout" class="btn-lg btn-warning">Timeout <kbd class="kbd kbd-sm ml-1">T</kbd></.button>
      <.button :if={@snapshot.period == 1}" phx-click="end_period" class="btn-lg btn-error">End Period <kbd class="kbd kbd-sm ml-1">E</kbd></.button>
      <.button :if={@snapshot.period == 2}" phx-click="end_game" class="btn-lg btn-error">End Game <kbd class="kbd kbd-sm ml-1">E</kbd></.button>
    </div>

    <div :if={@snapshot.phase == :jam_running} class="space-y-4">
      <div class="flex justify-center gap-3">
        <.button phx-click="end_jam" class="btn-lg btn-error">End Jam <kbd class="kbd kbd-sm ml-1">Space</kbd></.button>
        <.button phx-click="call_timeout" class="btn-lg btn-warning">Timeout <kbd class="kbd kbd-sm ml-1">T</kbd></.button>
      </div>

      <!-- Score buttons -->
      <div class="flex justify-center gap-8">
        <div class="text-center">
          <div class="text-xs tracking-widest opacity-60 mb-2">HOME SCORE</div>
          <div class="flex gap-1">
            <.button phx-click="score" phx-value-team="home" phx-value-points="-1" class="btn-sm">-1</.button>
            <.button phx-click="score" phx-value-team="home" phx-value-points="1" class="btn-sm">+1 <kbd class="kbd kbd-xs">1</kbd></.button>
            <.button phx-click="score" phx-value-team="home" phx-value-points="2" class="btn-sm">+2 <kbd class="kbd kbd-xs">2</kbd></.button>
            <.button phx-click="score" phx-value-team="home" phx-value-points="3" class="btn-sm">+3 <kbd class="kbd kbd-xs">3</kbd></.button>
            <.button phx-click="score" phx-value-team="home" phx-value-points="4" class="btn-sm">+4 <kbd class="kbd kbd-xs">4</kbd></.button>
          </div>
        </div>
        <div class="text-center">
          <div class="text-xs tracking-widest opacity-60 mb-2">AWAY SCORE</div>
          <div class="flex gap-1">
            <.button phx-click="score" phx-value-team="away" phx-value-points="-1" class="btn-sm">-1</.button>
            <.button phx-click="score" phx-value-team="away" phx-value-points="1" class="btn-sm">+1 <kbd class="kbd kbd-xs">⇧1</kbd></.button>
            <.button phx-click="score" phx-value-team="away" phx-value-points="2" class="btn-sm">+2 <kbd class="kbd kbd-xs">⇧2</kbd></.button>
            <.button phx-click="score" phx-value-team="away" phx-value-points="3" class="btn-sm">+3 <kbd class="kbd kbd-xs">⇧3</kbd></.button>
            <.button phx-click="score" phx-value-team="away" phx-value-points="4" class="btn-sm">+4 <kbd class="kbd kbd-xs">⇧4</kbd></.button>
          </div>
        </div>
      </div>
    </div>

    <div :if={@snapshot.phase == :timeout} class="flex justify-center gap-3">
      <.button phx-click="end_timeout" class="btn-lg btn-primary">End Timeout <kbd class="kbd kbd-sm ml-1">E</kbd></.button>
    </div>

    <div :if={@snapshot.phase == :halftime} class="flex justify-center">
      <.button phx-click="start_period" class="btn-lg btn-primary">Start Period 2</.button>
    </div>

    <div :if={@snapshot.phase == :final} class="text-center text-lg opacity-60">
      Game Over
    </div>
  </div>
</div>
```

- [ ] **Step 3: Verify it compiles**

Run: `mix compile`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/scoreboard_web/live/game_live/operator.ex lib/scoreboard_web/live/game_live/operator.html.heex
git commit -m "feat: add operator LiveView with controls and keyboard shortcuts"
```

---

### Task 6: Integration tests

**Files:**
- Create: `test/scoreboard_web/live/game_live_test.exs`

- [ ] **Step 1: Write integration tests**

Create `test/scoreboard_web/live/game_live_test.exs`:

```elixir
defmodule ScoreboardWeb.GameLiveTest do
  use ScoreboardWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    on_exit(fn ->
      for {pid, _} <- DynamicSupervisor.which_children(GameServer.Runtime.Supervisor) do
        DynamicSupervisor.terminate_child(GameServer.Runtime.Supervisor, pid)
      end
    end)

    :ok
  end

  describe "Index" do
    test "renders landing page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/games/new")
      assert html =~ "DerbyNova Scoreboard"
      assert html =~ "New Game"
    end

    test "create game redirects to operator", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/games/new")

      {:ok, view, _html} =
        view
        |> element("button", "New Game")
        |> render_click()
        |> follow_redirect(conn)

      assert assert path(view) =~ "/operator"
    end
  end

  describe "Operator" do
    setup %{conn: conn} do
      {:ok, _} = GameServer.start_game("test-game")
      {:ok, conn: conn}
    end

    test "renders operator with initial state", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/games/test-game/operator")
      assert html =~ "Start Period 1"
    end

    test "start period shows lineup controls", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/games/test-game/operator")

      view
      |> element("button", "Start Period 1")
      |> render_click()

      assert render(view) =~ "Start Jam"
    end

    test "full game lifecycle via buttons", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/games/test-game/operator")

      # Start period 1
      view |> element("button", "Start Period 1") |> render_click()
      assert render(view) =~ "Start Jam"

      # Start jam
      view |> element("button", ~r/Start Jam/) |> render_click()
      assert render(view) =~ "End Jam"

      # Add score
      view |> element("button", "+3") |> render_click()
      assert render(view) =~ "3"

      # End jam
      view |> element("button", "End Jam") |> render_click()
      assert render(view) =~ "Start Jam"
    end

    test "shows game over in final state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/games/test-game/operator")

      # Advance to final
      GameServer.start_period("test-game")
      GameServer.start_jam("test-game")
      GameServer.end_jam("test-game")
      GameServer.end_period("test-game")
      GameServer.start_period("test-game")
      GameServer.start_jam("test-game")
      GameServer.end_jam("test-game")
      GameServer.end_game("test-game")

      # The view should update via PubSub
      :timer.sleep(50)
      assert render(view) =~ "Game Over"
    end
  end

  describe "Audience" do
    setup %{conn: conn} do
      {:ok, _} = GameServer.start_game("test-game")
      {:ok, conn: conn}
    end

    test "renders audience view", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/games/test-game/scoreboard")
      assert html =~ "HOME"
      assert html =~ "AWAY"
      assert html =~ "F11"
    end

    test "redirects to index for unknown game", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/games/nonexistent/scoreboard")
      # Mount redirects — the LiveView push_navigates to /
      # LiveViewTest will follow the redirect
      assert html =~ "DerbyNova Scoreboard"
    end

    test "updates when game state changes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/games/test-game/scoreboard")

      GameServer.start_period("test-game")
      GameServer.start_jam("test-game")
      GameServer.add_score("test-game", :home, 3)

      :timer.sleep(150)

      html = render(view)
      assert html =~ "3"
    end
  end
end
```

- [ ] **Step 2: Run integration tests**

Run: `mix test test/scoreboard_web/live/game_live_test.exs`
Expected: All tests PASS (some may need adjustment for render timing)

- [ ] **Step 3: Run full test suite**

Run: `mix test`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add test/scoreboard_web/live/game_live_test.exs
git commit -m "test: add integration tests for LiveView scoreboard"
```

---

### Task 7: Smoke test and cleanup

**Files:**
- None new

- [ ] **Step 1: Start the server and manually verify**

Run: `mix phx.server`

1. Open `http://localhost:4000/games/new` — should see landing page
2. Click "New Game" — should redirect to operator view
3. Click "Start Period 1" — should show lineup controls
4. Click "Start Jam" — should show jam controls + score buttons
5. Open audience URL in new tab — should see real-time scoreboard
6. Add scores via operator — should appear on audience display
7. Press keyboard shortcuts (Space, T, 1-4, Shift+1-4) — should work

- [ ] **Step 2: Final commit if any fixes needed**

```bash
git add -A
git commit -m "fix: polish LiveView scoreboard integration"
```
