# Durable match actions and recovery

Every accepted GameServer action is appended to `game_events` through Ash/SQLite
before the server updates its game state, broadcasts the result, or replies with
success. SQLite uses `synchronous: :full` with its default WAL journal. This is a
single-host design: one registered GameServer owns each match.

Each journal row contains a game ID, unique increasing sequence, action, payload,
schema version, UTC recording time and portable checkpoint. Version 1 checkpoints
contain scores, phase, period, jam number and all five timers. Timers store their
duration, elapsed milliseconds and running intent; process-local monotonic
timestamps are never persisted. This is an action journal with checkpoints, not
a second implementation of game transitions in Ash.

## Restarting a match

After restarting the application, open `/` and choose **Resume match** from the
saved match list, or open the same `/games/<id>/operator` URL. The operator view
restores an existing saved match; an unknown ID does not create a new match. A
crashed supervised GameServer restores automatically.

The library lists matches by their most recent saved action, with cursor pagination
and a manual refresh button. Finished matches include a summary and public display
link. Reading the library or a saved public display never starts a match process.
Dates are explicitly shown in UTC. Until team configuration (DBN-7) is delivered,
Home/Away labels match the current operator view; use the date and match ID to
distinguish fixtures. The legacy `/games/new` URL still opens the library.

Recovery validates journal sequence, version and checkpoint shape before using
the latest checkpoint. A gap, unsupported version or invalid checkpoint prevents
startup rather than silently starting a new match. Events are ordered by sequence,
not wall-clock timestamps. Unique sequence constraints reject duplicate writes.

Previously running clocks are paused at the last saved action. The operator and
public display show that the match awaits confirmation. Ordinary game commands
are rejected until the operator selects **Resume saved clocks**. Resuming is itself
saved before the timers restart and the result is broadcast. Repeated restarts
before confirmation keep the same paused values and running intent.

**The time between the last saved action and the crash is not recovered.** Ticks
are display updates and are not journaled. Downtime is never guessed or deducted.
Compare the recovered values with the officials' clocks before resuming. Manual
clock correction is tracked in DBN-30 and is not provided by this change.

## Storage failures

A rejected SQLite write leaves the game state and journal sequence unchanged.
The operator sees an error for both button and keyboard commands. Fix the storage
problem before retrying. A failed initialization does not create a playable match.

An action can have committed even if its network response was lost. This change
does not deduplicate browser retries; reconnect/command delivery semantics remain
tracked in DBN-75. Inspect the displayed state before retrying an ambiguous action.

## Deployment and validation

Run `mix ecto.migrate` before starting the updated application. The new table does
not migrate old in-memory matches: finish those matches before updating.

Use `mix test test/game_server test/scoreboard_web/live/recovery_live_test.exs`
for journal, crash, recovery, portable-clock and SQLite write-failure tests.
The full project checks run with `mix precommit`.

Back up the SQLite database with the server stopped (including any WAL files),
or use SQLite's online backup facilities. Copying only an active database file
can omit committed WAL data. DBN-77 covers the complete installation/backup guide.
