#!/usr/bin/env bash
# Drives the real bin/fm-crew-state.sh (from the tree at $1) over a disposable
# ship task whose status log carries each note below, while its no-mistakes run
# is still monitoring CI. Prints the crew state the supervisor would read.
set -u
TREE=$1
WT=/home/cmckay/.no-mistakes/worktrees/80aee654c94f/01M3S91J04KSZD9VRQK78GHGMB
# Reuse the fixture helpers (fake no-mistakes/tmux, repo builder) from the test file only.
eval "$(sed -n '1,800p' "$WT/tests/fm-crew-state.test.sh" | sed 's#$(dirname "${BASH_SOURCE\[0\]}")/lib.sh#'"$WT"'/tests/lib.sh#')"
CREW_STATE="$TREE/bin/fm-crew-state.sh"
i=0
while IFS= read -r note; do
  i=$((i+1))
  reset_fakes
  d=$(new_case "c$i")
  make_repo_on_branch "$d/wt" "fm/feat-$i"
  make_fakebin "$d" >/dev/null
  fm_write_meta "$d/state/feat-$i.meta" "window=fm:fm-feat-$i" "worktree=$d/wt" "kind=ship" "mode=no-mistakes"
  printf 'done: %s\n' "$note" > "$d/state/feat-$i.status"
  FM_FAKE_CI_LOGS='waiting for checks'
  FM_FAKE_AXI_STATUS="$(run_ci_monitoring "fm/feat-$i")"
  out=$(run_crew_state "$d" "feat-$i")
  printf '=== done: %s\n' "$note"
  printf '%s\n' "$out" | grep -E '^(state|source|detail):' | sed 's/^/    /'
done <<'EOF'
PROD deploy watch, checks green on TEST
PROPERTIES table migration, checks green
checks green on staging, SPRINT PR pending
PR https://github.com/o/r/pull/2 checks green
PR https://gitlab.example.test/g/s/p/-/merge_requests/7 checks green
PR #12 checks green
EOF
