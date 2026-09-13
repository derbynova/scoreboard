# Match clocks

The period is **prepared** with “Prepare Period 1/2”. Its clock starts on
“Start Jam”, at the first jam-starting whistle. It continues between subsequent
jams. Calling a timeout stops it; “End Timeout” resets the lineup countdown but
leaves the period clock stopped until the next “Start Jam”.

## At zero

Countdown displays round remaining milliseconds up: `00:00` means no time remains.
Expired clocks stop and stay visible. The operator follows the officials' signals:

- Lineup zero does not automatically start a jam.
- Jam zero does not issue an end-jam command. Confirm “End Jam” on the officials'
  signal; this also lets the operator enter the final points before closing the jam.
- Period zero during a jam leaves the current jam available until its end is
  confirmed. No normal next jam can start at or beyond period zero, even if a
  server tick has not yet processed expiration.
- Period zero between jams stops the lineup countdown and replaces “Start Jam”
  with “Confirm Period End” (period one) or “Confirm Game End” (period two).
  The underlying phase awaits that confirmation; time does not continue.
- The generic timeout reaching zero does not end the interruption automatically.
- Intermission runs and is shown on the operator, full audience and clock-only
  screens. At zero it awaits “Prepare Period 2”; preparing does not start play.
  The score-only audience layout intentionally contains no clocks.

The timing reference is [WFTDA Rules 20250101, sections 1.1 and 1.3](https://rules.wftda.com/01_params.html),
verified 2026-09-13. Overtime, additional jams and end-period reviews require the
separate DBN-18/DBN-17 work. The current final-state confirmation does not implement
those situations or certify the result. See [manual time corrections](clock-corrections.md) for DBN-79.

## Persistence and recovery

Expiration is saved as an `expire_clocks` journal entry before broadcasting the
stopped clock state. Ordinary display ticks do not write to SQLite. A failed
expiration write leaves the runtime's clock state unchanged and is retried on the
next tick; no successful stop is broadcast until it is saved. Existing command
writes also settle expired clocks before saving their resulting state.

The version-one checkpoint shape is unchanged: intermission already existed in
saved clocks. Old journals remain readable; their saved times and running intentions
are preserved, without trying to infer corrections for the previous timing bugs.
Recovered clocks stay paused until confirmation. An expired clock from an old
checkpoint is stopped when recovery is confirmed. Newly saved expired clocks do not
require restarting at zero.

Older application versions do not recognize `expire_clocks`. After this version
has written such entries, use this version or later to reopen the database. A
rollback requires restoring the corresponding pre-upgrade database backup.

Recovery still restores the last saved action, without accounting for elapsed time
since that action. See [match recovery](match-recovery.md).
