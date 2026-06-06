# Audience Display Layout Variants — Design Spec

**Issue:** DBN-9
**Date:** 2026-06-06

## Summary

Allow the audience display URL (`/games/:id/scoreboard`) to accept a `?layout=` query param for layout customization. Three layouts: full (default), score-only, and clock-only. The layout is persisted in localStorage so refreshes keep the selection. The operator view shows links for each variant.

## Layouts

### `?layout=full` (default)

The current scoreboard display — scores, clocks, timeout dots, lead indicators, period/jam info, header, footer. No changes from existing behavior.

### `?layout=score`

Minimal score-only display on opaque dark background (`#0a0a1a`). Shows:
- Team names and scores side by side (large font)
- Lead star indicator (yellow, blinking)
- Subtle period/jam indicator (`P2 · J14`)

Does NOT show: clocks, timeout dots, period clock, footer details.

Use case: streaming overlay. Streaming software (OBS Studio) can handle chroma/transparency externally.

### `?layout=clock`

Clock-only large display on opaque dark background (`#0a0a1a`). Shows:
- Active phase clock (jam/lineup/timeout) in very large font, color-coded (yellow/cyan/red)
- Period clock as secondary display below
- Subtle period/jam indicator

Does NOT show: scores, timeout dots, lead indicators.

Use case: dedicated clock screen or projector.

## Architecture

### File structure

```
lib/scoreboard_web/live/game_live/
  audience.ex                # LiveView module
  audience.html.heex         # Dispatcher — renders the correct partial based on @layout
  audience/
    _full.html.heex          # Full scoreboard (current template, refactored)
    _score.html.heex         # Score-only layout
    _clock.html.heex         # Clock-only layout
```

### LiveView changes (`audience.ex`)

- `mount/3` parses `uri_query` for `"layout"` param, defaults to `"full"`
- Assigns `layout` to socket
- No route changes needed — query params are available without modifying the router

```elixir
def mount(%{"id" => game_id}, uri_query, socket) do
  layout = Map.get(uri_query, "layout", "full")
  # ... existing mount logic (snapshot, subscribe)
  {:ok, assign(socket, :layout, layout)}
end
```

### Template dispatcher (`audience.html.heex`)

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

Each partial is self-contained: own root `<div>` with `fixed inset-0`, dark theme styles, and inline styles. No shared wrapper.

### localStorage persistence

A colocated JS hook on the audience page handles persistence client-side. The hook is attached to the root audience div via `phx-hook=".LayoutPersistence"`:

- `mounted()`: check if URL has `?layout=` param. If yes, save to `localStorage` key `"audience-layout"`. If no param but `localStorage` has a saved value, use `this.pushPatch` to redirect to the URL with the saved layout param.
- The LiveView reads the query param and assigns `layout`. When the hook patches the URL, the LiveView re-mounts with the correct layout from the query param.

This keeps persistence logic entirely client-side. The LiveView only reads the query param — it has no awareness of localStorage.

### Operator view changes

In `game_components.ex`, the existing top bar link "Audience View" is updated to show three links:

```
Audience: Full | Score | Clock
```

Each link uses `<.link navigate={"/games/#{@game_id}/scoreboard?layout=full|score|clock"}>`.

Bug fix: the existing link navigates to `/game/:id` (missing `s` and `/scoreboard`). This is corrected to `/games/:id/scoreboard`.

## Scope

- 3 layouts only — no extensibility mechanism needed
- No new routes, no new dependencies
- Existing snapshot data structure is sufficient for all three layouts
- No changes to GameServer or operator logic

## Out of scope

- Additional layouts beyond the three defined
- Layout preview in operator view
- Layout persistence server-side (localStorage only)
