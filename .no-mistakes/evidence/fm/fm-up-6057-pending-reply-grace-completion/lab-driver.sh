#!/usr/bin/env bash
# Live lab driver for #6057: real fm-send.sh, real tmux pane (lab socket),
# real fm-secondmate-report.sh, and the watcher's fm_pending_reply_tick on
# wall-clock time. Usage: lab-driver.sh <bin-dir> <scenario> <log>
set -u
BIN=$1 SCEN=$2 LOG=$3
REPO=/home/cmckay/.no-mistakes/worktrees/80aee654c94f/01M3PK6GRDWDXHDJ85DFDB3TMP
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); rmdir "$LAB"
"$REPO/bin/fm-lab-home.sh" create "$LAB" >/dev/null
TD=$("$REPO/bin/fm-lab-home.sh" tmux-dir "$LAB")
export TMUX_TMPDIR=$TD
export FM_HOME=$LAB FM_PENDING_REPLY_GRACE_SECS=${GRACE:-8} FM_SEND_SETTLE=0
MATE="$LAB/mate"; mkdir -p "$MATE/state"
printf 'mate\n' > "$MATE/.fm-secondmate-home"
printf 'schema=fm-secondmate-parent.v1\nroute=local\nparent_home=%s\n' "$LAB" > "$MATE/.fm-secondmate-parent"
PANE="$LAB/pane.txt"
idle() { printf '╭──────────────╮\n│ ❯            │\n╰──────────────╯\n' > "$PANE"; }
busy() { printf '✻ Working… (12s · esc to interrupt)\n╭──────────────╮\n│ ❯            │\n╰──────────────╯\n' > "$PANE"; }
idle
cat > "$LAB/pane.sh" <<'PS'
#!/usr/bin/env bash
# Flicker-free redraw of the fake mate screen: overwrite in place, clear each
# line's tail and everything below, never blank the whole screen.
clear
while :; do
  printf '\033[H'
  while IFS= read -r l; do printf '%s\033[K\n' "$l"; done < "$1"
  printf '\033[J'; sleep 0.3
done
PS
tmux -L fm-lab new-session -d -s labsess -n fm-mate "bash '$LAB/pane.sh' '$PANE'"
SOCK=$(tmux -L fm-lab display-message -p '#{socket_path}')
export TMUX="$SOCK,$(tmux -L fm-lab display-message -p '#{pid}'),0"
. "$REPO/bin/fm-lib.sh" 2>/dev/null || true
cat > "$LAB/state/mate.meta" <<M
window=labsess:fm-mate
endpoint_task_id=mate
worktree=$MATE
project=$MATE
harness=claude
kind=secondmate
mode=secondmate
yolo=off
home=$MATE
projects=alpha
M
trap 'tmux -L fm-lab kill-server 2>/dev/null; "$REPO/bin/fm-lab-home.sh" teardown "$LAB" >/dev/null 2>&1; rm -rf "$LAB"' EXIT
T0=$(date +%s)
ts() { printf '[t+%03ds] ' $(( $(date +%s) - T0 )); }
log() { ts; printf '%s\n' "$*"; }
exec >>"$LOG" 2>&1
log "=== scenario=$SCEN bin=$BIN grace=${FM_PENDING_REPLY_GRACE_SECS}s lab=$LAB"
tick() { bash -c '. "$1/fm-pending-reply-lib.sh"; fm_pending_reply_tick "$2"' _ "$BIN" "$LAB/state"; }
rec() { ls "$LAB/state/pending-replies/"* 2>/dev/null | head -1; }
field() { grep "^$1=" "$(rec)" | tail -1 | cut -d= -f2-; }
snap() { log "phase=$(field phase) delivered=$(field delivered_epoch) req_done=$(field request_turn_completed_epoch) recov_sent=$(field recovery_sent_epoch) recov_done=$(field recovery_turn_completed_epoch) reposts=$(reposts) escal=$(grep -c 'pending-reply-missed' "$LAB/state/mate.status" 2>/dev/null)"; }
reposts() { local n=0 f; for f in "$LAB"/state/mate.inbox/*.msg; do [ -f "$f" ] && grep -q 'REPOST REQUIRED' "$f" && n=$((n+1)); done; echo $n; }
ticks() { local i; for ((i=0;i<$1;i++)); do tick; snap; sleep 1; done; }

log "captain -> fm-send.sh mate 'audit the ledger' (marked request)"
"$BIN/fm-send.sh" mate "audit the ledger" ; log "fm-send rc=$?"
CORR=$(field corr_id); log "corr=$CORR"
busy; log "mate pane: BUSY (long request turn begins)"
case "$SCEN" in
  reply-after-long-turn)
    ticks 14                      # turn runs 14s, > 8s grace from delivery
    idle; log "mate pane: IDLE (request turn complete)"
    ticks 3
    log "mate -> fm-secondmate-report.sh done $CORR (reply lands 3s after turn end)"
    FM_HOME=$MATE "$BIN/fm-secondmate-report.sh" done "$CORR" "ledger clean"
    ticks 3 ;;
  no-reply)
    ticks 14; idle; log "mate pane: IDLE (request turn complete, mate never replies)"
    ticks 12
    busy; log "mate pane: BUSY (recovery turn)"; ticks 12
    idle; log "mate pane: IDLE (recovery turn complete, still no reply)"
    ticks 12
    log "waiting further to confirm one-repost limit"; ticks 6 ;;
  no-reply-busy-recovery)
    ticks 14; idle; log "mate pane: IDLE (request turn complete, mate never replies)"
    while [ "$(field phase)" = awaiting_report ]; do tick; snap; sleep 1; done
    busy; log "mate pane: BUSY (long recovery turn begins as the repost lands)"; ticks 12
    idle; log "mate pane: IDLE (recovery turn complete, still no reply)"
    ticks 12
    log "waiting further to confirm one-repost limit"; ticks 6 ;;
  working-verb)
    ticks 14; idle; log "mate pane: IDLE (request turn complete)"
    ticks 5
    log "mate -> plain echo 'working [corr=$CORR]: still wrapping up' into parent status"
    printf 'working [corr=%s]: still wrapping up\n' "$CORR" >> "$LAB/state/mate.status"
    ticks 5 ;;
  transport-fail)
    ticks 14; idle; log "mate pane: IDLE (request turn complete)"
    ticks 2
    log "mate torn down: its meta is removed, so the recovery fm-send cannot reach it"
    rm -f "$LAB/state/mate.meta"
    ticks 10 ;;
esac
log "--- parent status (state/mate.status):"; cat "$LAB/state/mate.status" 2>/dev/null | sed 's/^/    /'
log "--- mate inbox messages:"; for f in "$LAB"/state/mate.inbox/*.msg; do [ -f "$f" ] && { printf '    %s: ' "${f##*/}"; tr '\n' ' ' < "$f" | cut -c1-220; echo; }; done
log "--- final record:"; sed 's/^/    /' "$(rec)"
tmux -L fm-lab kill-server 2>/dev/null
"$REPO/bin/fm-lab-home.sh" teardown "$LAB" >/dev/null 2>&1
rm -rf "$LAB"
log "=== teardown done"
