# DerbyNova Scoreboard — Architecture Overview

## Layer Diagram

```mermaid
graph TB
    subgraph "Browser — LiveViews"
        AUD[Audience Display<br/>/games/:id/scoreboard]
        OP[Operator Panel<br/>/games/:id/operator]
        PT[Penalty Tracker<br/>/games/:id/penalty-tracker]
        PBT[Penalty Box Timer<br/>/games/:id/penalty-box]
        LT[Lineup Tracker<br/>/games/:id/lineup-tracker]
    end

    subgraph "Runtime Layer — GenServer"
        GS[GameServer<br/>1 per game — DynamicSupervisor]
        ENG[GameEngine<br/>pure functions, state machine]
        TIM[Timer<br/>monotonic time, running state]
    end

    subgraph "Messaging"
        PS[Phoenix PubSub<br/>topic: game:{id}]
    end

    subgraph "Persistence Layer — Ash Framework (M3+)"
        ASH[Ash Domain: Scoreboard.Derby]
        DB[(SQLite<br/>local file)]
    end

    AUD -->|subscribe| PS
    OP -->|subscribe| PS
    PT -->|subscribe| PS
    PBT -->|subscribe| PS
    LT -->|subscribe| PS

    OP -->|GenServer.call| GS
    PT -->|GenServer.call| GS
    PBT -->|GenServer.call| GS
    LT -->|GenServer.call| GS

    GS -->|broadcast snapshot| PS
    GS -->|uses| ENG
    ENG -->|uses| TIM

    GS -.->|async persist events<br/>M3+: fire-and-forget| ASH
    ASH -->|reads/writes| DB

    style GS fill:#e94560,color:#fff
    style PS fill:#ffd700,color:#000
    style DB fill:#4ea8de,color:#fff
```

## Key Architectural Decisions

1. **GameServer is the runtime truth** — all game state lives in a single GenServer per game. No DB reads during gameplay.
2. **Ash is persistence only** — the `Scoreboard.Derby` domain mirrors events to SQLite asynchronously (M3+). It does not drive game logic.
3. **PubSub is the backbone** — a single PubSub topic per game delivers the snapshot to all connected LiveViews. No direct LiveView-to-LiveView communication.
4. **Snapshot is a flat map** — broadcast on every state change. LiveViews extract what they need.
5. **One GameServer, many views** — each operator role (Score OP, PT, PBT, LT) gets its own LiveView URL. All talk to the same GameServer.
6. **Zero-config deployment** — SQLite file lives alongside the release. No external DB, no Docker, no network setup required. `mix release` → binary → open browser.
