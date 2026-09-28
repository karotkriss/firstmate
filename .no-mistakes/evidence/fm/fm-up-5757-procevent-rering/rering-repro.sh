#!/usr/bin/env bash
# End-to-end reproduction for issue #5757: a worker-owned (lavish board) result
# that stays pending across reconcile cycles must ring the worker's doorbell
# exactly ONCE (when the inbox record is first created), and once the worker has
# acknowledged the record (moved it into handled/) a later publish must neither
# resurrect it out of handled/ nor ring again.
#
# Drives the REAL bin/fm-procevent.sh reconcile path against a hand-placed
# stranded owner-task lavish result, with a fake tmux that logs every literal
# send-keys so a doorbell ring is observable in FM_SEND_LOG.
#
# Usage: rering-repro.sh <bin-dir-containing-fm-procevent.sh> <label>
set -u

BIN=$1
LABEL=$2
PE="$BIN/fm-procevent.sh"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/rering.$LABEL.XXXXXX")
FM_HOME="$WORK/home"
STATE="$FM_HOME/state"
INBOX="$STATE/procevent-inbox"
mkdir -p "$INBOX" "$WORK/fakebin"
chmod 700 "$FM_HOME" "$STATE"

# --- fake tmux: reports window fm-t1 live under a claude agent, non-pending
#     composer, and logs every literal send-keys to FM_SEND_LOG. -------------
cat > "$WORK/fakebin/tmux" <<'SH'
#!/usr/bin/env bash
set -u
case "${1:-}" in
  send-keys)
    shift; literal=0
    while [ $# -gt 0 ]; do
      case "$1" in
        -t) shift 2 ;;
        -l) literal=1; shift ;;
        *) break ;;
      esac
    done
    [ "$literal" = 1 ] && printf '%s\n' "${1:-}" >> "${FM_SEND_LOG:-/dev/null}"
    exit 0 ;;
  display-message)
    for a in "$@"; do
      case "$a" in
        *pane_current_command*) printf 'claude\n'; exit 0 ;;
        *cursor_y*) printf '1\n'; exit 0 ;;
        *pane_tty*) printf '\n'; exit 0 ;;
        *pane_id*) printf '%%1\n'; exit 0 ;;
        *pane_current_path*) printf '\n'; exit 0 ;;
      esac
    done
    printf 'fakepane\n'; exit 0 ;;
  capture-pane) printf '> \n'; exit 0 ;;
  list-windows) printf 'fm-t1\n'; exit 0 ;;
  has-session) exit 0 ;;
esac
exit 0
SH
chmod +x "$WORK/fakebin/tmux"

# --- worker endpoint meta: backend tmux, window fmtest:fm-t1 ----------------
printf 'window=fmtest:fm-t1\nworktree=%s/wt\nproject=fmtest\n' "$FM_HOME" > "$STATE/t1.meta"

# --- stranded owner-task lavish result, non-terminal, non-silent feedback ---
ID="board-src"
printf 'session:\n  status: feedback\nprompts[1]{uid,prompt,selector,tag,text}:\n  "","review round","","message","please continue"\n' \
  > "$INBOX/$ID.1.result"
printf 'lavish\n' > "$INBOX/$ID.1.adapter"
printf 't1\n'      > "$INBOX/$ID.1.owner-task"
chmod 0600 "$INBOX/$ID.1.result" "$INBOX/$ID.1.adapter" "$INBOX/$ID.1.owner-task"

SEND_LOG="$WORK/send.log"; : > "$SEND_LOG"
run_reconcile() {
  PATH="$WORK/fakebin:$PATH" FM_HOME="$FM_HOME" FM_SEND_LOG="$SEND_LOG" \
    "$PE" reconcile >/dev/null 2>&1 || true
}

echo "=== [$LABEL] driving 5 reconcile cycles on one unchanging pending board result ==="
for i in 1 2 3 4 5; do run_reconcile; done

rings_before_ack=$(grep -cF 'Firstmate instruction waiting' "$SEND_LOG" 2>/dev/null || true); rings_before_ack=${rings_before_ack:-0}
active_msgs=$(ls "$STATE/t1.inbox"/*.msg 2>/dev/null | wc -l | tr -d ' ')
echo "rings across 5 cycles (pre-ack): $rings_before_ack"
echo "active inbox records: $active_msgs"

# --- worker acknowledges: atomic mv of the record into handled/ ------------
mkdir -p "$STATE/t1.inbox/handled"
rec=$(ls "$STATE/t1.inbox"/*.msg 2>/dev/null | head -1)
if [ -n "$rec" ]; then
  mv "$rec" "$STATE/t1.inbox/handled/${rec##*/}"
  echo "acknowledged record ${rec##*/} -> handled/"
fi

: > "$SEND_LOG"
echo "=== [$LABEL] driving 3 more reconcile cycles AFTER acknowledgement ==="
for i in 1 2 3; do run_reconcile; done

rings_after_ack=$(grep -cF 'Firstmate instruction waiting' "$SEND_LOG" 2>/dev/null || true); rings_after_ack=${rings_after_ack:-0}
resurrected=$(ls "$STATE/t1.inbox"/*.msg 2>/dev/null | wc -l | tr -d ' ')
still_handled=$(ls "$STATE/t1.inbox/handled"/*.msg 2>/dev/null | wc -l | tr -d ' ')
echo "rings across 3 post-ack cycles: $rings_after_ack"
echo "records resurrected back into active inbox: $resurrected"
echo "records remaining in handled/: $still_handled"

echo "---SUMMARY[$LABEL] pre_ack_rings=$rings_before_ack post_ack_rings=$rings_after_ack resurrected=$resurrected handled=$still_handled active=$active_msgs---"
rm -rf "$WORK"
