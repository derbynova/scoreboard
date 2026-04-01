# DerbyNova Scoreboard — Game State Machine

## Phase Transitions

```mermaid
stateDiagram-v2
    [*] --> initial

    initial --> lineup : start_period (P1)\nstarts period_clock + lineup_clock

    lineup --> jam_running : start_jam\nincrement jam_number, starts jam_clock
    lineup --> timeout : call_timeout (TT/OR/OT)\nstops period + lineup clocks
    lineup --> halftime : end_period (P1 only)\nstops all clocks, starts intermission
    lineup --> final : end_game (P2 only)\nstops all clocks

    jam_running --> lineup : end_jam\nstops jam_clock, starts lineup_clock
    jam_running --> timeout : call_timeout\nstops period + jam clocks

    timeout --> lineup : end_timeout\nrestarts period + lineup clocks

    halftime --> lineup : start_period (P2)\nstarts period_clock + lineup_clock

    final --> [*]
```

## Timer States per Phase

```mermaid
graph LR
    subgraph "lineup"
        PC1[period_clock ▶ running]
        LC1[lineup_clock ▶ running]
        JC1[jam_clock ⏸ stopped]
        TC1[timeout_clock ⏸ stopped]
    end

    subgraph "jam_running"
        PC2[period_clock ▶ running]
        LC2[lineup_clock ⏸ stopped]
        JC2[jam_clock ▶ running]
        TC2[timeout_clock ⏸ stopped]
    end

    subgraph "timeout"
        PC3[period_clock ⏸ stopped]
        LC3[lineup_clock ⏸ stopped]
        JC3[jam_clock ⏸ stopped]
        TC3[timeout_clock ▶ running]
    end

    subgraph "halftime"
        IC[intermission_clock ▶ running]
        ALL3[all others ⏸ stopped]
    end
```

## WFTDA Timing Constants

| Timer | Duration | Notes |
|-------|----------|-------|
| Period | 30 min (1,800,000 ms) | 2 periods per game |
| Jam | 2 min (120,000 ms) | max duration |
| Lineup | 30 sec (30,000 ms) | between jams |
| Timeout | 60 sec (60,000 ms) | TT/OR |
| Intermission | 10 min (600,000 ms) | between periods |

## Snapshot Structure (current)

```elixir
%{
  phase: :initial | :lineup | :jam_running | :timeout | :halftime | :final,
  period: 0 | 1 | 2,
  jam_number: integer,
  score_home: integer,
  score_away: integer,
  period_clock_s: integer,      # remaining seconds
  lineup_clock_s: integer,
  jam_clock_s: integer,
  timeout_clock_s: integer,
  period_clock_running: boolean,
  lineup_clock_running: boolean,
  jam_clock_running: boolean,
  timeout_clock_running: boolean
}
```

Snapshot is extended in M2 with: rosters, penalties, jam details, timeout types.
Snapshot is extended in M4 with: override flags, custom timer values.
