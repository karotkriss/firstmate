# tmux runtime backend (reference)

tmux is firstmate's verified reference runtime backend: the session provider every other backend is compared against, and the fully verified baseline for secondmate support.
This is the setup guide; for the shared runtime-backend abstraction and selection order, see [`docs/architecture.md`](architecture.md) ("Runtime session backends") and [`docs/configuration.md`](configuration.md) ("Runtime backend").

## What it is and when to pick it

tmux is a terminal multiplexer.
Firstmate gives each crewmate its own tmux window inside a session, so you can attach and watch a task work, or type into its window to intervene directly.
Pick tmux unless you have a specific reason to try an experimental backend (herdr, zellij, Orca, or cmux) - it is the fully verified reference path for secondmate homes, while Orca and cmux are the backends that do not support secondmate spawns.

## Prerequisites

- tmux itself: `brew install tmux` (or your platform's package manager).
- The universal firstmate prerequisites: a verified crew harness plus the required toolchain, detected at session start and installed only after you approve; [`docs/configuration.md`](configuration.md) owns both lists ("Harness support", "Toolchain").

## Selecting it

tmux is the hard default: it needs no explicit selection.
It is also what firstmate falls back to when nothing else is set - no local `config/backend` file, no `FM_BACKEND`, no explicit `--backend` flag firstmate passes internally when it spawns a task - and runtime auto-detection (see below) does not pick anything either.
You can still select it explicitly by putting `tmux` in a local `config/backend` file - the durable way to pick it - or by exporting `FM_BACKEND=tmux` when you launch your harness for a one-off session; telling the first mate in chat to use tmux also works.
This mainly matters as an opt-out of herdr or cmux runtime auto-detection (see [`docs/herdr-backend.md`](herdr-backend.md) and [`docs/cmux-backend.md`](cmux-backend.md)).

## First run

Nothing to provision up front.
The first crewmate spawn creates whatever tmux session and window it needs.

## Run inside tmux for the best experience

Launch your harness from inside a tmux session (`tmux new -s firstmate` or similar, then start your agent).
Every crewmate window then lands in that same session, where you can watch the crew work in real time or type into any window to intervene.
When following the commands below, use that session's actual name.
Inside tmux, `tmux display-message -p '#S'` prints it.

## Outside tmux: the detached `firstmate` session

If you launch your harness outside of tmux, crewmate windows land in a detached session named `firstmate`, created on first use.
Attach to it any time with:

```sh
tmux attach -t firstmate
```

## Watching and typing into crew windows

Once attached, each crewmate is its own window named `fm-<id>`:

```sh
tmux list-windows -t <session-name>          # see every crew window
tmux select-window -t <session-name>:fm-<id> # jump to one, or use ctrl-b <n>
```

Use the current tmux session name when firstmate was launched inside tmux; use `firstmate` only for the detached outside-tmux path.
Typing directly into an attached window is authoritative direct intervention - the first mate treats it the same as any other captain instruction and reconciles at the next heartbeat.
You do not need to attach at all for routine supervision: from an active firstmate session, the first mate reads crew windows itself with `bin/fm-peek.sh fm-<id>` (a bounded, read-only capture) and steers a crew with `FM_HOME=<this-firstmate-home> bin/fm-send.sh fm-<id> "<text>"` unless `FM_HOME` is already set to the active firstmate home.

## Verifying it works

Ask the first mate for any small piece of work, or spawn a trivial scout task, and confirm a new window shows up:

```sh
tmux list-windows -t <session-name>
```

Use the current tmux session name for the run-inside-tmux path, or `firstmate` for the detached outside-tmux path.
You should see a `fm-<id>` window for the task, live and updating as the crewmate works.

## Submit confirmation: what a swallowed Enter actually looks like

`fm-send` reports a swallowed Enter by reading the composer row back after submitting.
Recorded here because the read is entirely empirical and the harnesses redraw differently.

Verified 2026-07-19 on Linux (WSL2), tmux 3.4, against live agents in throwaway panes, harness versions claude 2.1.215, codex-cli 0.144.6, opencode 1.18.3.
`pi` and `grok` were not installed on the verifying machine, so their composer rows are unverified; the fix is at the shared classifier and is harness-generic.

The composer row of an EMPTY composer, captured with `tmux capture-pane -e -p -t <pane> -S <cursor_y> -E <cursor_y>` and passed through `fm_composer_strip_ghost`:

| harness | bytes | reads as |
| --- | --- | --- |
| claude 2.1.215 | `e2 9d af  c2 a0` (`❯` + U+00A0 NO-BREAK SPACE) | empty, but only since the U+00A0 normalization |
| codex 0.144.6 | `e2 80 ba  20` (`›` + ASCII space) | empty |
| opencode 1.18.3 | `┃  Ask anything... "Fix broken tests"` | its placeholder is NOT dimmed, so it survives ghost stripping and reads as content |

Two consequences, both fixed in `bin/fm-composer-lib.sh` (task fm-send-false-negative-n8):

1. claude pads its empty composer with U+00A0, which bash's `[[:space:]]` does not trim.
   Before the fix every claude pane classified `pending` even fully idle, so `fm-send` reported a swallowed Enter on every steer and the away-mode injector saw every idle claude pane as busy with human input.
2. A steer sent MID-TURN is queued, not swallowed: claude replaces the composer row with `❯ Press up to edit queued messages` and processes the message with the next tool result (confirmed by the agent itself in the pane).
   opencode's undimmed placeholder is the same shape of residue (upstream issue #583).
   Inferring failure from a merely non-empty composer therefore fired on steers that had landed.

The submit paths now pass the text they typed down to the classifier, so a swallow is only called when THAT TEXT is still on the row.
Measured on live panes holding our own unsubmitted text (`fm_tmux_composer_state <pane> <text>`):

| pane state | claude | codex | opencode |
| --- | --- | --- | --- |
| our text sitting unsubmitted | `pending` | `pending` | `pending` |
| a wrapped TAIL of our text | `pending` | - | - |
| unrelated text in the composer | `empty` | `empty` | `empty` |
| mid-turn, steer queued | `empty` | `empty` | `empty` |

Redraw timing matters too.
Sampling the composer row every 0.35s immediately after Enter on claude 2.1.215, the row still showed the just-submitted text at t=0 and was clear by the next sample, so it clears somewhere between 0.4s and 0.75s while `FM_SEND_SLEEP` defaults to 0.4s.
Reading that one stale frame was enough to spend a spurious extra Enter on an idle pane and, once in about five runs, to report a swallow on a steer that had landed.
`fm_tmux_submit_enter_core` therefore confirms a `pending` read with a second read before spending another Enter.
After that change, live `bin/fm-send.sh` runs against a claude pane: 6/6 clean at idle, 3/3 clean mid-turn.

### End-to-end re-verification, 2026-07-20

Re-run after the mid-turn false negative was reported again from a live claude scout on the herdr backend (pane `default:w5:p2E`), against throwaway panes on Linux (WSL2), tmux 3.6, harness versions claude 2.1.215 / codex-cli 0.144.6 / opencode 1.18.3 / pi 0.80.10.
That report turned out to be the unfixed code path: the fix had never been pushed, so the home that reproduced it was running a build without it.
Comparing real `bin/fm-send.sh` exit codes at the same live pane state, pre-fix tree (`6721812`) against this branch:

| harness | pane state | pre-fix exit | fixed exit |
| --- | --- | --- | --- |
| claude 2.1.215 | idle | 1 (`Enter swallowed`) | 0 |
| claude 2.1.215 | mid-turn, steer queued | 1 (`Enter swallowed`) | 0 |
| opencode 1.18.3 | mid-turn, steer queued | 1 (`Enter swallowed`) | 0 |
| codex-cli 0.144.6 | idle and mid-turn | 0 | 0 |
| pi 0.80.10 | idle | 0 | 0 |

The queued steer was confirmed to have genuinely landed, not merely to have stopped erroring: the pane showed `❯ Press up to edit queued messages` at submit time, and claude consumed the exact steer text when its turn ended.
codex was never affected because its post-submit row returns to a DIMMED ghost placeholder that ghost stripping already removed, and pi draws a genuinely blank composer row, so the padding never existed there.
A genuine swallow still reads `pending` and still exits non-zero: verified by typing text into an idle claude composer and never pressing Enter.
pi could not be exercised mid-turn because no model was configured on the verifying machine, and grok was not installed; both remain unverified for the queued case, and the fix is at the shared classifier rather than per harness.

The strict no-submit-in-flight path is a separate caller and is NOT repaired for opencode: `fm_tmux_composer_state <pane>` with no submitted text still reads `pending` on an idle opencode pane, because its `Ask anything...` placeholder is undimmed (upstream issue #583).
That affects the away-mode injector's pending-input guard, not `fm-send`, and the existing `FM_COMPOSER_IDLE_RE` override is the operator-facing knob for it.

## Agent liveness probe

`fm_backend_target_exists` (`bin/fm-backend.sh`) only checks that a window's pane still exists.
A secondmate agent that exits leaves its pane alive as a bare idle shell, which passes that check as "alive" - the gap `bin/fm-bootstrap.sh`'s session-start secondmate-liveness sweep exists to close (evidence 2026-07-07: every secondmate in one fleet was found sitting at a dead `zsh` shell, invisible to that check).

`fm_backend_tmux_agent_alive` (`bin/backends/tmux.sh`) answers a deeper question: is a real harness-agent *process* running in the pane right now, not just whether the pane exists?
It reads tmux's own `#{pane_current_command}`, which reports the pane's live foreground process name - already resolved by tmux from the pty's controlling process group, not something this adapter derives itself.

Agent liveness and composer safety are separate checks.
During away-mode escalation delivery, `fm_tmux_composer_state` sends a bare shell glyph on an unbordered row to the shared composer classifier as `unknown`, and the daemon injects only into an affirmatively `empty` composer; see [Composer-emptiness safety](herdr-backend.md#composer-emptiness-safety-2026-07-10-fleet-wide-across-all-four-backends).

Verified empirically with real tmux 3.6a on macOS (Darwin 25.5.0), 2026-07-07:

```sh
$ tmux new-session -d -s fmtest -n testwin
$ tmux display-message -p -t fmtest:testwin '#{pane_current_command}'
zsh
$ tmux send-keys -t fmtest:testwin 'sleep 30' Enter
$ tmux display-message -p -t fmtest:testwin '#{pane_current_command}'
sleep
$ tmux send-keys -t fmtest:testwin C-c
$ tmux display-message -p -t fmtest:testwin '#{pane_current_command}'
zsh
```

An idle pane reports the shell's own name; a live foreground process reports its own name; the pane reverts to the shell's name the moment that process exits - exactly the alive/dead signal the probe needs.

A second case matters for a harness that shells out to subcommands while it runs (git, npm, no-mistakes, ...): does `pane_current_command` report the harness or the subcommand?
Verified the same session: a persisting parent process running a child command (`bash -c 'echo start; sleep 30; echo end'`, where the parent bash stays alive waiting on its own child) reports the PARENT's own name (`bash`) throughout, not the child's (`sleep`) - so a harness that survives while it shells out stays correctly classified as alive.
(A single-simple-command `bash -c "sleep 30"` is a different, unrelated case: bash execs directly into `sleep`, replacing itself, so the reported name changes because the process itself became `sleep` - not because tmux "saw through" to a child.)

The classifier (`fm_backend_tmux_agent_alive`) maps the observed name to `alive`, `dead`, or `unknown`:

- `alive` - the name contains `claude`, `codex`, `opencode`, or `grok`. All four were confirmed to run as their own literal process name (`ps -ef`, 2026-07-07): `claude` and `codex` and `opencode` are each a native compiled binary (`file` reports Mach-O), so their `comm` is their own binary name with no interpreter wrapper to hide behind.
- `dead` - the name is a bare shell (`zsh`, `bash`, `sh`, `dash`, `ash`, `ksh`, `mksh`, `tcsh`, `csh`, `fish`).
- `unknown` - anything else, including an unreadable pane.

### Known gap: `pi` cannot be confidently classified

`pi` is a `#!/usr/bin/env node` script (confirmed via its shebang and installed path, 2026-07-07), so a live `pi` agent's pane reports `node` as its `pane_current_command`, not `pi` - verified by running a long-lived `node -e` script in a pane and confirming its foreground process is a genuine child reachable via `pgrep -P <pane_pid>` with an inspectable `ps -o args=` (the same technique `bin/fm-harness.sh`'s own self-detection uses when walking UP its ancestry), while `pi --version` itself was observed to exit too quickly under the same pane to reliably capture its live foreground state - real `pi` invocations were not available to test.
Since `node` is also the generic name for a plain interpreter session, any future JS-based harness, or someone's unrelated node script, there is no way to attribute a bare `node` foreground process back to `pi` specifically from outside the pane without deeper (and fragile) argument introspection.
The classifier deliberately reports `unknown` for `node`/`python`/`python3` rather than guess - per the secondmate-liveness sweep's correctness bar, a wrong `alive` is harmless but a wrong `dead` spins up a duplicate agent, so an unresolvable case must never be treated as confidently dead.
Practical effect: a dead `pi` secondmate is not auto-healed by the liveness sweep today; it is reported as `skipped: liveness probe inconclusive` instead, which still surfaces it for a human to act on.
Resolving this would need either a `pi`-specific env marker inspectable from outside the process (mirroring `PI_CODING_AGENT=true`, which `bin/fm-harness.sh` already uses for self-detection but which is not readable from a different process without deeper introspection) or accepting the argument-inspection fragility - not attempted here.

## Limitations

None specific to tmux for the reference path itself - it is the fully verified reference backend, while Orca and cmux are the backends without secondmate support.
The agent-liveness probe above has one known gap (`pi`'s generic `node` process name, see above).
