# Watcher stall-bound eviction - live validation

Change: `fm/fm-watch-cycle-exceeds-beacon` (#4400). A live fleet watcher whose liveness
beacon has stalled past a hard bound (`FM_WATCHER_STALL_BOUND`, default 3x grace) is now
evicted with an identity-verified TERM and replaced, instead of every re-arm being refused
against a live-but-stale holder.

All scenarios driven against the real `bin/fm-watch.sh` with a real fake lock holder process.

## Scenario 1 - beacon past hard bound -> holder evicted, replacement takes lock, message printed
Manual drive of the real script (holder pid 872329, beacon decades stale, FM_WATCHER_STALL_BOUND=3):

    watcher_pid=872391 lock_pid=872391 holder=872329
    holder DEAD
    === OUT ===
    watcher: replaced stalled pid 872329 (beacon 843594349s past hard bound 3s)

## Scenario 2 - beacon past grace but under hard bound -> still refused, holder untouched
Covered by `test_live_stalled_watch_lock_is_replaced_past_hard_bound` (first half): with
FM_WATCHER_STALL_BOUND=9999999999 the arm exits nonzero, stderr carries "heartbeat is stale",
and the holder stays live and unsignalled.

## Scenario 3 (adversarial) - holder survives TERM -> refusal + nonzero exit, holder alive
Holder installed `trap "" TERM`:

    exit=1 (expect nonzero)
    holder ALIVE (expected)
    STDERR: watcher: lock held by live pid 993282 but heartbeat is stale for 843594455s (>1s); inspect or stop that watcher before re-arming.
    STDOUT:

## Scenario 4 (adversarial) - recorded identity mismatch (recycled pid) -> never signalled
Lock's pid-identity deliberately set to a non-matching value:

    exit=1 (expect nonzero)
    holder ALIVE (expected, never signalled)
    STDERR: watcher: lock held by live pid 997200 but heartbeat is stale for 843594461s (>1s); inspect or stop that watcher before re-arming.
    STDOUT:

## Test flake found and fixed
`test_live_stalled_watch_lock_is_replaced_past_hard_bound` synchronized on the lock-pid file
but asserted the `watcher: replaced stalled pid ...` stdout line, which the watcher echoes only
*after* acquiring the lock and writing that pid - so a one-shot grep raced the acquire/echo gap
and read an empty file (failed ~1 in 3 runs). Fixed by polling for the message.

After fix, 8/8 consecutive isolated runs pass:

    run 1 EXIT=0 : ok - live watcher lock with a beacon past the hard bound is replaced, under it is still refused
    run 2 EXIT=0 : ok ...
    run 3 EXIT=0 : ok ...
    run 4 EXIT=0 : ok ...
    run 5 EXIT=0 : ok ...
    run 6 EXIT=0 : ok ...
    run 7 EXIT=0 : ok ...
    run 8 EXIT=0 : ok ...
