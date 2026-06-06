# Audience Display Layout Variants — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `?layout=full|score|clock` query param support to the audience display with separate template partials and localStorage persistence.

**Architecture:** Three separate HEEx partials (`_full`, `_score`, `_clock`) under `audience/` directory. The main `audience.html.heex` dispatches to the correct partial based on the `@layout` assign. A colocated JS hook handles localStorage persistence. Operator top bar shows links for each variant.

**Tech Stack:** Phoenix LiveView, HEEx templates, Tailwind CSS v4, colocated JS hooks

---

### Task 1: Update Audience LiveView to parse layout query param

**Files:**
- Modify: `lib/scoreboard_web/live/game_live/audience.ex`

- [ ] **Step 1: Update mount/3 to parse `uri_query` and assign layout**

Change the `mount/3` signature to accept `uri_query` as the second argument and parse the `"layout"` key:

```elixir
def mount(%{"id" => game_id}, uri_query, socket) do
  layout = Map.get(uri_query, "layout", "full")

  try do
    case GameServer.snapshot(game_id) do
      {:ok, snapshot} ->
        GameServer.subscribe(game_id)

        {:ok, assign(socket, game_id: game_id, snapshot: snapshot, layout: layout)}

      {:error, _reason} ->
        {:ok, push_navigate(socket, to: ~p"/")}
    end
  catch
    :exit, _ -> {:ok, push_navigate(socket, to: ~p"/")}
  end
end
```

- [ ] **Step 2: Verify existing tests still pass**

Run: `mix test test/scoreboard_web/live/game_live_test.exs`
Expected: All tests PASS. The existing tests don't pass query params, so `layout` defaults to `"full"`.

- [ ] **Step 3: Commit**

```bash
git add lib/scoreboard_web/live/game_live/audience.ex
git commit -m "feat(audience): parse layout query param in mount/3"
```

---

### Task 2: Refactor audience template into partials

**Files:**
- Create: `lib/scoreboard_web/live/game_live/audience/_full.html.heex`
- Create: `lib/scoreboard_web/live/game_live/audience/_score.html.heex`
- Create: `lib/scoreboard_web/live/game_live/audience/_clock.html.heex`
- Modify: `lib/scoreboard_web/live/game_live/audience.html.heex`

- [ ] **Step 1: Create `audience/` directory**

```bash
mkdir -p lib/scoreboard_web/live/game_live/audience
```

- [ ] **Step 2: Move current template content into `_full.html.heex`**

Copy the entire current content of `audience.html.heex` (the `<div class="audience-display ...">...</div>` block, lines 1–185) into `_full.html.heex`. The content stays exactly the same.

- [ ] **Step 3: Create `_score.html.heex` — score-only layout**

```heex
<div
  class="audience-display fixed inset-0 flex flex-col select-none overflow-hidden"
  style="background:#0a0a1a;color:#fff;font-family:'Courier New',monospace"
>
  <main class="flex-1 flex items-center justify-center gap-16">
    <div class="flex flex-col items-center gap-1">
      <div
        class="text-sm tracking-[4px] uppercase opacity-70"
        style="color:var(--team-home-color, #e94560)"
      >
        Home
      </div>
      <div
        id="audience-score-home"
        class="text-[120px] md:text-[160px] font-black leading-none tabular-nums"
        style="color:var(--team-home-color, #e94560)"
      >
        {@snapshot.score_home}
      </div>
      <div class="flex gap-2 items-center mt-1 min-h-[28px]">
        <span
          :if={Map.get(@snapshot, :lead_home, false)}
          class="audience-lead text-2xl text-yellow-400"
          style="filter:drop-shadow(0 0 8px #ffd700)"
        >
          &#9733;
        </span>
      </div>
    </div>

    <div class="text-3xl opacity-15 font-extralight">vs</div>

    <div class="flex flex-col items-center gap-1">
      <div
        class="text-sm tracking-[4px] uppercase opacity-70"
        style="color:var(--team-away-color, #4ea8de)"
      >
        Away
      </div>
      <div
        id="audience-score-away"
        class="text-[120px] md:text-[160px] font-black leading-none tabular-nums"
        style="color:var(--team-away-color, #4ea8de)"
      >
        {@snapshot.score_away}
      </div>
      <div class="flex gap-2 items-center mt-1 min-h-[28px]">
        <span
          :if={Map.get(@snapshot, :lead_away, false)}
          class="audience-lead text-2xl text-yellow-400"
          style="filter:drop-shadow(0 0 8px #ffd700)"
        >
          &#9733;
        </span>
      </div>
    </div>
  </main>

  <div class="text-center pb-4 text-[9px] tracking-[2px] opacity-20">
    P{@snapshot.period} &middot; J{@snapshot.jam_number}
  </div>
</div>
```

- [ ] **Step 4: Create `_clock.html.heex` — clock-only layout**

```heex
<div
  class="audience-display fixed inset-0 flex flex-col select-none overflow-hidden"
  style="background:#0a0a1a;color:#fff;font-family:'Courier New',monospace"
>
  <main class="flex-1 flex flex-col items-center justify-center">
    <div :if={@snapshot.jam_clock_running} class="text-center">
      <div class="text-[10px] tracking-[3px] uppercase opacity-70 text-yellow-400">Jam</div>
      <div class="text-[120px] md:text-[180px] font-black leading-none tabular-nums text-yellow-400">
        {format_clock(@snapshot.jam_clock_s)}
      </div>
    </div>

    <div :if={@snapshot.lineup_clock_running} class="text-center">
      <div class="text-[10px] tracking-[3px] uppercase opacity-70 text-cyan-400">Lineup</div>
      <div class="text-[120px] md:text-[180px] font-black leading-none tabular-nums text-cyan-400">
        {format_clock(@snapshot.lineup_clock_s)}
      </div>
    </div>

    <div :if={@snapshot.timeout_clock_running} class="text-center">
      <div class="text-[10px] tracking-[3px] uppercase opacity-70 text-red-400">Timeout</div>
      <div class="text-[120px] md:text-[180px] font-black leading-none tabular-nums text-red-400">
        {format_clock(@snapshot.timeout_clock_s)}
      </div>
    </div>

    <div
      :if={!@snapshot.jam_clock_running and !@snapshot.lineup_clock_running and !@snapshot.timeout_clock_running}
      class="text-center"
    >
      <div class="text-[120px] md:text-[180px] font-black leading-none tabular-nums opacity-15">
        --:--
      </div>
    </div>

    <div class="text-center mt-6">
      <div class="text-[9px] tracking-[2px] uppercase opacity-25">Period Clock</div>
      <div class="text-3xl font-bold opacity-40 tabular-nums">
        {format_clock(@snapshot.period_clock_s)}
      </div>
    </div>
  </main>

  <div class="text-center pb-4 text-[9px] tracking-[2px] opacity-15">
    PERIOD {@snapshot.period} &middot; JAM {@snapshot.jam_number}
  </div>
</div>
```

- [ ] **Step 5: Replace `audience.html.heex` with dispatcher**

The main template becomes a simple dispatcher that renders the correct partial:

```heex
<%= cond do %>
  <% @layout == "score" -> %>
    {render("_score.html.heex", assigns)}
  <% @layout == "clock" -> %>
    {render("_clock.html.heex", assigns)}
  <% true -> %>
    {render("_full.html.heex", assigns)}
<% end %>
```

- [ ] **Step 6: Run tests to verify no regressions**

Run: `mix test test/scoreboard_web/live/game_live_test.exs`
Expected: All tests PASS. The default layout is `"full"`, so existing tests that don't pass query params see the same output.

- [ ] **Step 7: Commit**

```bash
git add lib/scoreboard_web/live/game_live/audience.html.heex lib/scoreboard_web/live/game_live/audience/
git commit -m "feat(audience): split template into full/score/clock layout partials"
```

---

### Task 3: Add audience layout tests

**Files:**
- Modify: `test/scoreboard_web/live/game_live_test.exs`

- [ ] **Step 1: Add tests for each layout variant**

Add a new describe block inside `test/scoreboard_web/live/game_live_test.exs` after the existing "Audience LiveView" describe. Add these tests:

```elixir
describe "Audience Layout Variants" do
  test "default layout renders full scoreboard", %{conn: conn} do
    {:ok, _pid} = GameServer.start_game("layout-default")

    {:ok, view, _html} = live(conn, ~p"/games/layout-default/scoreboard")

    assert has_element?(view, "#audience-score-home")
    assert has_element?(view, "#audience-score-away")
    assert render(view) =~ "Period Clock"
    assert render(view) =~ "PERIOD"
    assert render(view) =~ "F11 for fullscreen"
  end

  test "?layout=full renders full scoreboard", %{conn: conn} do
    {:ok, _pid} = GameServer.start_game("layout-full")

    {:ok, view, _html} = live(conn, "/games/layout-full/scoreboard?layout=full")

    assert has_element?(view, "#audience-score-home")
    assert has_element?(view, "#audience-score-away")
    assert render(view) =~ "Period Clock"
    assert render(view) =~ "PERIOD"
  end

  test "?layout=score renders score-only view", %{conn: conn} do
    {:ok, _pid} = GameServer.start_game("layout-score")

    {:ok, view, _html} = live(conn, "/games/layout-score/scoreboard?layout=score")

    html = render(view)
    assert has_element?(view, "#audience-score-home")
    assert has_element?(view, "#audience-score-away")
    refute html =~ "Period Clock"
    refute html =~ "F11 for fullscreen"
    assert html =~ "vs"
  end

  test "?layout=clock renders clock-only view", %{conn: conn} do
    {:ok, _pid} = GameServer.start_game("layout-clock")

    {:ok, view, _html} = live(conn, "/games/layout-clock/scoreboard?layout=clock")

    html = render(view)
    refute has_element?(view, "#audience-score-home")
    refute has_element?(view, "#audience-score-away")
    assert html =~ "Period Clock"
    assert html =~ "PERIOD"
    refute html =~ "F11 for fullscreen"
  end

  test "clock layout shows jam clock when running", %{conn: conn} do
    {:ok, _pid} = GameServer.start_game("layout-clock-jam")

    {:ok, view, _html} = live(conn, "/games/layout-clock-jam/scoreboard?layout=clock")

    GameServer.start_period("layout-clock-jam")
    :timer.sleep(150)
    GameServer.start_jam("layout-clock-jam")
    :timer.sleep(150)

    html = render(view)
    assert html =~ "Jam"
  end

  test "score layout updates when game state changes", %{conn: conn} do
    {:ok, _pid} = GameServer.start_game("layout-score-update")

    {:ok, view, _html} = live(conn, "/games/layout-score-update/scoreboard?layout=score")

    assert has_element?(view, "#audience-score-home", "0")

    GameServer.start_period("layout-score-update")
    :timer.sleep(150)
    GameServer.start_jam("layout-score-update")
    GameServer.add_score("layout-score-update", :home, 5)
    :timer.sleep(150)

    assert has_element?(view, "#audience-score-home", "5")
  end
end
```

- [ ] **Step 2: Run the new tests**

Run: `mix test test/scoreboard_web/live/game_live_test.exs`
Expected: All tests PASS.

- [ ] **Step 3: Commit**

```bash
git add test/scoreboard_web/live/game_live_test.exs
git commit -m "test(audience): add tests for layout query param variants"
```

---

### Task 4: Update operator top bar with layout links

**Files:**
- Modify: `lib/scoreboard_web/components/game_components.ex`

- [ ] **Step 1: Update `top_bar/1` to show layout variant links**

Replace the existing `top_bar` function (lines 55–67) with:

```elixir
def top_bar(assigns) do
  ~H"""
  <div class="flex justify-between items-center bg-base-300 rounded-t-lg px-3 py-1.5">
    <span class="text-sm font-mono text-base-content/70">{@game_id}</span>
    <span class="text-sm font-medium">
      P{@snapshot.period} · J{@snapshot.jam_number} · {Clock.format_clock(@snapshot.period_clock_s)}
    </span>
    <div class="flex items-center gap-3">
      <span class="text-xs text-base-content/50">Audience:</span>
      <.link navigate={"/games/#{@game_id}/scoreboard?layout=full"} class="text-sm text-primary hover:underline">
        Full
      </.link>
      <.link navigate={"/games/#{@game_id}/scoreboard?layout=score"} class="text-sm text-primary hover:underline">
        Score
      </.link>
      <.link navigate={"/games/#{@game_id}/scoreboard?layout=clock"} class="text-sm text-primary hover:underline">
        Clock
      </.link>
    </div>
  </div>
  """
end
```

This also fixes the broken link (was `/game/:id`, now `/games/:id/scoreboard`).

- [ ] **Step 2: Run tests to verify operator still works**

Run: `mix test test/scoreboard_web/live/game_live_test.exs`
Expected: All tests PASS. The operator tests don't assert on the top bar content specifically, so they should still pass.

- [ ] **Step 3: Commit**

```bash
git add lib/scoreboard_web/components/game_components.ex
git commit -m "feat(operator): add layout variant links to top bar, fix broken audience URL"
```

---

### Task 5: Add localStorage persistence via colocated JS hook

**Files:**
- Modify: `lib/scoreboard_web/live/game_live/audience.html.heex`

- [ ] **Step 1: Update `audience.html.heex` to add the hook and a wrapper div**

Replace the entire content of `audience.html.heex` with:

```heex
<div id="audience-layout-root" phx-hook=".LayoutPersistence">
  <%= cond do %>
    <% @layout == "score" -> %>
      {render("_score.html.heex", assigns)}
    <% @layout == "clock" -> %>
      {render("_clock.html.heex", assigns)}
    <% true -> %>
      {render("_full.html.heex", assigns)}
  <% end %>
</div>
<script :type={Phoenix.LiveView.ColocatedHook} name=".LayoutPersistence">
  export default {
    mounted() {
      const url = new URL(window.location.href)
      const layoutParam = url.searchParams.get("layout")

      if (layoutParam) {
        localStorage.setItem("audience-layout", layoutParam)
      } else {
        const saved = localStorage.getItem("audience-layout")
        if (saved && saved !== "full") {
          this.pushEvent("apply_layout", { layout: saved })
        }
      }
    }
  }
</script>
```

- [ ] **Step 2: Add `handle_event("apply_layout", ...)` to the Audience LiveView**

Add this handler to `lib/scoreboard_web/live/game_live/audience.ex`:

```elixir
@impl true
def handle_event("apply_layout", %{"layout" => layout}, socket) do
  {:noreply, assign(socket, :layout, layout)}
end
```

- [ ] **Step 3: Run all tests**

Run: `mix test test/scoreboard_web/live/game_live_test.exs`
Expected: All tests PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/scoreboard_web/live/game_live/audience.html.heex lib/scoreboard_web/live/game_live/audience.ex
git commit -m "feat(audience): persist layout selection in localStorage"
```

---

### Task 6: Run precommit checks

**Files:** None

- [ ] **Step 1: Run full precommit suite**

Run: `mix precommit`
Expected: All checks PASS (formatter, compiler, tests).

- [ ] **Step 2: Final commit if any formatting fixes needed**

If `mix precommit` auto-formatted files:
```bash
git add -A
git commit -m "style: formatting fixes from precommit"
```
