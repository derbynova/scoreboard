# DerbyNova Scoreboard — Multi-Operator Data Flow

## Operator Roles & LiveViews

```mermaid
graph TB
    subgraph "Game Day — Local Network"
        LAP[Operator Laptop<br/>WiFi Hotspot / Router]

        subgraph "Tablet 1"
            PT[Penalty Tracker<br/>tablet browser]
        end

        subgraph "Tablet 2"
            PBT[Penalty Box Timer<br/>tablet browser]
        end

        subgraph "Tablet 3"
            LT[Lineup Tracker<br/>tablet browser]
        end

        PROJ[Projector<br/>audience display]

        LAP ---|WiFi| PT
        LAP ---|WiFi| PBT
        LAP ---|WiFi| LT
        LAP ---|HDMI/WiFi| PROJ
    end

    subgraph "Scoreboard Server — running on Operator Laptop"
        SERVER[Bandit/Phoenix<br/>localhost:4000]
        GS[GameServer GenServer]
        PS[PubSub<br/>game:abc123]
        DB[(SQLite)]
    end

    PT -->|WebSocket| SERVER
    PBT -->|WebSocket| SERVER
    LT -->|WebSocket| SERVER
    PROJ -->|WebSocket| SERVER

    SERVER --> GS
    GS --> PS
    PS -->|snapshot broadcast| SERVER
    DB -.->|M3+| GS
```

## Request/Response Flow

```mermaid
sequenceDiagram
    participant OP as Operator LiveView
    participant GS as GameServer (GenServer)
    participant ENG as GameEngine (pure)
    participant PS as PubSub
    participant LV as All LiveViews
    participant DB as SQLite (M3+)

    OP->>GS: GenServer.call(:start_jam)
    GS->>ENG: Game.start_jam(game, now)
    ENG-->>GS: {new_game_state, snapshot}
    GS->>PS: broadcast({:game_update, snapshot})
    PS-->>LV: {:game_update, snapshot}
    LV-->>LV: handle_info → update assigns

    Note over GS,DB: M3+: async persistence
    GS-.->>DB: Task.start(fn -> Ash.create!(event) end)
```

## URL Scheme

| Route | LiveView | Role | Device |
|-------|----------|------|--------|
| `/` | Index | Landing page — create/join game | Laptop |
| `/games/:id/operator` | Operator | Score + phase control | Laptop |
| `/games/:id/scoreboard` | Audience | Public display | Projector |
| `/games/:id/penalty-tracker` | PenaltyTracker | Penalty encoding | Tablet |
| `/games/:id/penalty-box` | PenaltyBoxTimer | Box countdown + release | Tablet |
| `/games/:id/lineup-tracker` | LineupTracker | Lineup + jammer calls | Tablet |

## Connection Resilience

- All LiveViews reconnect automatically on WiFi drop (Phoenix LiveView built-in)
- On reconnect, `mount/3` fetches current snapshot from GameServer
- If GameServer crashes (M3+): state is recovered from SQLite events, PubSub reconnects
- If server process dies: audience display freezes on last snapshot (no white screen)
