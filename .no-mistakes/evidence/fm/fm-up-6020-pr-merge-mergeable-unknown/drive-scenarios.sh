#!/usr/bin/env bash
# Drives the real bin/fm-pr-merge.sh against a disposable fake GitHub forge
# (the repo's own gh/gh-axi fakes, extracted to harness.sh) in a throwaway
# FM_HOME/state per case. Prints a transcript per scenario.
EV=$(cd "$(dirname "$0")" && pwd)
. "$EV/harness.sh"
set +e
URL=https://github.com/example/repo/pull/6020

reads() { grep -c '^pr view .*statusCheckRollup' "$1/gh.log"; }
merges() { grep -c '^pr merge ' "$1/gh.log"; }

# Swap the forge's live view JSON to a red-check variant from the Nth read on.
red_from_read() {
  local case_dir=$1 n=$2
  mv "$case_dir/fakebin/gh" "$case_dir/fakebin/gh.real"
  cp "$case_dir/github-view.json" "$case_dir/view-green.json"
  jq -c '.statusCheckRollup[0].conclusion="FAILURE"' "$case_dir/view-green.json" > "$case_dir/view-red.json"
  cat > "$case_dir/fakebin/gh" <<SH
#!/usr/bin/env bash
case " \$* " in *statusCheckRollup*)
  c=\$(( \$(cat "$case_dir/wrap-count" 2>/dev/null || echo 0) + 1 )); echo \$c > "$case_dir/wrap-count"
  [ "\$c" -ge $n ] && cp "$case_dir/view-red.json" "$case_dir/github-view.json" ;;
esac
exec "$case_dir/fakebin/gh.real" "\$@"
SH
  chmod +x "$case_dir/fakebin/gh"
}

scenario() {  # name seq(space-separated or '') [setup-fn] [delay-env]
  local name=$1 seq=$2 setup=${3:-} delay=${4-0} case_dir t0 t1 rc
  case_dir=$(make_case "$name"); mkdir -p "$case_dir/wt"
  add_gh_mocks "$case_dir" 6020602060206020602060206020602060206020
  : > "$case_dir/gh-axi.log"; : > "$case_dir/gh.log"
  [ -n "$setup" ] && $setup "$case_dir"
  local envs=()
  if [ -n "$seq" ]; then printf '%s\n' $seq > "$case_dir/seq"; envs+=(FM_TEST_GH_MERGEABLE_SEQUENCE="$case_dir/seq"); fi
  [ "$delay" = default ] || envs+=(FM_PR_GITHUB_MERGEABLE_RETRY_DELAY="$delay")
  t0=$(date +%s.%N)
  env "${envs[@]}" bash -c "$(declare -f run_pr_merge); ROOT='$ROOT' PR_MERGE='$PR_MERGE' REAL_MV='$REAL_MV'; run_pr_merge '$case_dir' task-x1 '$URL'" > "$case_dir/stdout" 2> "$case_dir/stderr"
  rc=$?
  t1=$(date +%s.%N)
  echo "=== $name"
  echo "mergeable sequence: ${seq:-<static view>}  retry delay: $delay"
  printf 'exit=%s  mergeable reads=%s  merge calls=%s  elapsed=%.1fs\n' "$rc" "$(reads "$case_dir")" "$(merges "$case_dir")" "$(echo "$t1 - $t0" | bc)"
  echo '--- stderr:'; sed 's/^/  /' "$case_dir/stderr"
  echo
}

set_draft()      { jq -c '.isDraft=true' "$1/github-view.json" > "$1/v" && mv "$1/v" "$1/github-view.json"; }
set_red()        { jq -c '.statusCheckRollup[0].conclusion="FAILURE"' "$1/github-view.json" > "$1/v" && mv "$1/v" "$1/github-view.json"; }
set_closed()     { jq -c '.state="CLOSED"' "$1/github-view.json" > "$1/v" && mv "$1/v" "$1/github-view.json"; }
set_dirty()      { jq -c '.mergeStateStatus="DIRTY"' "$1/github-view.json" > "$1/v" && mv "$1/v" "$1/github-view.json"; }
set_unreadable() { jq -c 'del(.mergeable)' "$1/github-view.json" > "$1/v" && mv "$1/v" "$1/github-view.json"; }
red_on_2nd()     { red_from_read "$1" 2; }
away_unreadable(){ printf 'not-a-contract\n' > "$1/state/.afk-contract"; }
away_queue()     { printf 'merge_method=MERGE\n' > "$1/github-rules"; write_away_record "$1" --words 'merge task-x1 when green'; }

case "${1:-all}" in
  timing)
    scenario unknown-once-default-delay "UNKNOWN MERGEABLE" "" default
    scenario unknown-forever-default-delay "UNKNOWN" "" default ;;
  *)
    scenario baseline-mergeable "MERGEABLE"
    scenario unknown-twice-then-mergeable "UNKNOWN UNKNOWN MERGEABLE"
    scenario unknown-four-then-mergeable-on-5th "UNKNOWN UNKNOWN UNKNOWN UNKNOWN MERGEABLE"
    scenario unknown-forever "UNKNOWN"
    scenario unknown-then-check-turns-red "UNKNOWN MERGEABLE" red_on_2nd
    scenario unknown-then-stays-unknown-check-turns-red "UNKNOWN UNKNOWN" red_on_2nd
    scenario unknown-plus-draft "UNKNOWN" set_draft
    scenario unknown-plus-red-check "UNKNOWN" set_red
    scenario unknown-plus-closed "UNKNOWN" set_closed
    scenario unknown-plus-dirty "UNKNOWN" set_dirty
    scenario conflicting "CONFLICTING"
    scenario mergeable-unreadable "" set_unreadable
    scenario unknown-then-mergeable-away-record-unreadable "UNKNOWN MERGEABLE" away_unreadable
    scenario unknown-then-mergeable-away-queue-protection "UNKNOWN MERGEABLE" away_queue ;;
esac
