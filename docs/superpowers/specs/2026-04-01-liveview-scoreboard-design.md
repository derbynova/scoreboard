# LiveView Scoreboard UI Design

## Overview

Connect the existing gameserver to a Phoenix LiveView scoreboard with two views: an operator control panel and an audience-facing display. Both subscribe to the same PubSub topic and receive real-time game state updates.

## Routes

| Route | LiveView | Purpose |
|-------|----------|---------|
| `/` | `ScoreboardWeb.GameLive.Index` | Create a new game or join an existing one |
| `/games/:id/operator` | `ScoreboardWeb.GameLive.Operator` | Operator control panel |
| `/games/:id/scoreboard` | `ScoreboardWeb.GameLive.Audience` | Audience-facing display |

## Landing Page — `GameLive.Index`

Simple page with:
- App title/branding
- "New Game" button — generates a UUID, calls `GameServer.start_game(id)`, redirects to `/games/:id/operator`
- "Join Game" — text input for a game ID, redirects to `/games/:id/scoreboard`

No game listing. No persistence. Just create and join.

## Operator LiveView — `GameLive.Operator`

Two zones: **scoreboard preview** (top) and **controls** (bottom).

### Scoreboard Preview

A compact version of the audience display so the operator can see what the audience sees. Same data, smaller scale.

### Controls

Organized by game phase. Only actions valid for the current phase are shown — no disabled buttons.

- **Pre-game** (`:initial`): `Start Period 1`
- **Lineup** (`:lineup`): `Start Jam`
- **Jam running** (`:jam_running`): `End Jam` + score increment buttons for each team (-1, +1, +2, +3, +4)
- **Timeout** (`:timeout`): `End Timeout`
- **Halftime** (`:halftime`): `Start Period 2`
- **Final period ending**: `End Game`

### Keyboard Shortcuts

Each button shows its shortcut key. Bound via `phx-hook` capturing keyboard events.

| Key | Action |
|-----|--------|
| `Space` | Start Jam / End Jam (context-dependent) |
| `T` | Call Timeout |
| `E` | End Timeout / End Period / End Game |
| `1`–`4` | Add points to home team |
| `Shift+1`–`Shift+4` | Add points to away team |

## Audience LiveView — `GameLive.Audience`

Full-screen dark display optimized for projected screens.

### Visual Hierarchy

```
┌──────────────────────────────────────────────┐
│         PERIOD 1  |  JAM 14                  │  ← header bar (small, faded)
│                                              │
│     HOME              ⏱              AWAY    │
│                                      │
│     87          PERIOD 23:45          72     │  ← scores largest (80px)
│                   ▲                          │
│               JAM 1:42            ◄ hero     │  ← period clock (36px)
│                                      clock   │  ← active phase clock (56px, color-coded)
│                                              │
│          LINEUP    TIMEOUT                    │  ← inactive clocks (faded)
└──────────────────────────────────────────────┘
```

- **Scores**: 80px, largest element. Home in red (#e94560), Away in blue (#4ea8de)
- **Period clock**: 36px, centered above the hero clock
- **Hero clock** (active phase): 56px, between scores. Color-coded per phase:
  - Jam → gold (#ffd700)
  - Lineup → cyan (#22d3ee)
  - Timeout → red
- **Inactive clocks**: faded at bottom, small. Show values without visual noise
- **Background**: dark (#0f0f1a) to minimize glare on projected displays

Only one phase clock occupies the hero position at a time. Jam, Lineup, and Timeout never run simultaneously. The `phase` field in the snapshot determines which is prominent.

### Fullscreen Hint

Show a small "Press F11 for fullscreen" note on the audience page.

## Data Flow

Both Operator and Audience LiveViews follow the same pattern:

```
mount/3
  → GameServer.subscribe(game_id)
  → GameServer.snapshot(game_id) → initial assigns

handle_info({:game_update, snapshot}, socket)
  → update assigns from snapshot

handle_event("start_jam", _, socket)
  → GameServer.start_jam(game_id)
  → {:noreply, socket}   (PubSub handles the state update)
```

Operator events call `GameServer.*` functions. The GenServer broadcasts the new snapshot via PubSub on topic `"game:<game_id>"`. Both LiveViews receive it in `handle_info`. No local state in LiveViews — everything comes from the gameserver.

## Gameserver Changes

### Timer running state

`GameServer.Impl.Timer` — add `running?: boolean` field, exposed in struct.

### Snapshot expansion

`GameServer.Impl.Game.snapshot/1` — add boolean fields for each clock's running state:

```elixir
%{
  # existing fields
  phase: atom,
  period: integer,
  jam_number: integer,
  score_home: integer,
  score_away: integer,
  period_clock_s: integer,
  lineup_clock_s: integer,
  jam_clock_s: integer,
  timeout_clock_s: integer,
  # new fields
  period_clock_running: boolean,
  jam_clock_running: boolean,
  lineup_clock_running: boolean,
  timeout_clock_running: boolean
}
```

The `phase` field already implies which clock is running, but explicit booleans are clearer for the UI and more robust if the phase/clock relationship changes.

## Out of Scope

- Team names/colors configuration (hardcoded HOME/AWAY for now)
- Jam history log
- Skater/penalty tracking
- Persistent storage / database sync
- Game listing on landing page
