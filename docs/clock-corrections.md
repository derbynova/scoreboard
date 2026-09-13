# Correcting remaining clock time

In the operator view, use **Correct remaining time**, select a clock, and enter
minutes and seconds. Check the preview, then **Save correction**. Use the time
agreed with the officials. Cancel leaves the clock unchanged.

- All five clocks can be corrected in any phase, including recovery and final.
- The allowed range is zero through that clock's current duration, inclusive.
  Seconds are whole numbers from 0 through 59. This changes remaining time, never
  the configured duration. A later phase that normally resets a clock still resets
  it to that duration; correcting a future clock is not configuring that phase.
- Opening the editor does not pause play. A running clock continues counting down
  while editing and starts from the entered remaining time at server acceptance.
  The preview identifies the time when selected; history records the exact time
  immediately before acceptance, in milliseconds.
- Stopped clocks stay stopped. Correcting an expired clock to a positive value
  does not restart it. Normal game transitions still govern its next start.
- Zero stops an active clock without changing phase. Setting the period to zero
  between jams also stops lineup and blocks another normal jam. During a jam,
  the current jam remains available until the official's end signal.
- Game keyboard shortcuts are suspended while the editor is open. If a phase,
  recovery state, selected clock's running state or value changes through another
  command or expiration, the old preview is refused. Cancel and select the clock
  again. Ordinary countdown progression does not invalidate the editor.

## Before recovery confirmation

Correct saved times before selecting **Resume saved clocks**. Corrections remain
paused and preserve which clocks were intended to run. Resume is disabled while
an editor is open. Saving a correction never confirms recovery implicitly.

Another crash after saving but before confirmation restores the corrected values
and the same resume intentions. A recovered clock corrected to zero stays stopped
when confirmation is finally given. Other recovered clocks resume normally.

The interval between the last saved action and a crash is still not inferred.
See [match recovery](match-recovery.md).

## History and failure handling

**Clock correction history** lists corrections newest first, with the clock,
exact before/after values, period, jam, phase, UTC timestamp and action sequence.
**Older corrections** loads earlier entries in pages of 20. History comes from
SQLite and remains available after reopening the operator view. Connected
operators receive new corrections; public screens receive the saved clock state.

Corrections use the same append-before-acknowledgement path as other match actions.
If SQLite refuses a write, no correction is applied or broadcast. The form remains
open with an error so it can be retried after storage is fixed. If another operator
has meanwhile changed the clock, reopen the editor before retrying.

## Compatibility

The version-one checkpoint shape and existing journals remain readable. The new
`correct_clock` action records clock name, before/after milliseconds, running and
recovery intentions, phase, period and jam in its payload. No schema migration is
needed for this feature. Versions predating DBN-79 reject journals containing this
action; rolling back requires a pre-upgrade database backup.

## Operator validation scenarios

Use a disposable practice match and record application version, browser, viewport,
operator's CRG experience, assistance needed, errors and hesitations. No operator
study results are implied by this checklist.

1. During a running jam, adjust its remaining time. Explain whether it will run or
   stop before saving. Confirm that the audience shows the saved value and that
   the period was not reset.
2. During a timeout, correct the stopped period time; confirm it remains stopped.
3. Recover a saved running jam, correct both period and jam, reopen the runtime
   before resuming, then confirm recovery. Verify values and resume intentions.
4. Correct a recovered jam to zero. Confirm recovery without starting that clock
   or ending the jam automatically.
5. Try an out-of-range value, then cancel. Verify there is no saved correction.
6. Open the same match in two operator tabs. Correct the selected clock in one;
   verify the other refuses its stale preview and displays the saved history.
7. Find an earlier correction and explain its time, match context and effect.

Automated coverage is in the engine, durable runtime and LiveView clock-correction
test files. Run the complete checks with `mix precommit`. Real operator comparisons
belong to DBN-83 and still require observed sessions.
