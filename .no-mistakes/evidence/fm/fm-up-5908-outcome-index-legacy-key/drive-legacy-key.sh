#!/usr/bin/env bash
# Drive the real fm-wake-drain.sh against disposable lab homes seeded with a
# legacy endpoint-shaped branch-outcome key. Usage: drive-legacy-key.sh <bin-dir> <label>
set -u
BIN=$1; LABEL=$2; WT=$(pwd)
run() { env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$LAB" "$@"; }
newlab() { LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); "$WT/bin/fm-lab-home.sh" create "$LAB" >/dev/null; S="$LAB/state"; }
echo "===== [$LABEL] bin=$BIN ====="

echo "--- S1: legacy key default:w0:p2 in history + uncovered fresh done status"
newlab
printf 'done: uncovered completion with no index\n' > "$S/fresh.status"
printf '%s\n' '{"seq":1,"epoch":1,"task":"default:w0:p2","wake":"","verdict":"captain","summary":"legacy endpoint-keyed outcome"}' > "$S/branch-outcomes.jsonl"
before=$(sha256sum < "$S/branch-outcomes.jsonl")
run "$BIN/fm-wake-drain.sh"; echo "drain rc=$?"
after=$(sha256sum < "$S/branch-outcomes.jsonl")
[ "$before" = "$after" ] && echo "history unchanged: yes" || echo "history unchanged: NO"
echo "ready marker: $(cat "$S/.branch-outcome-index-ready" 2>/dev/null || echo MISSING)"
echo "index files: $(cd "$S" && ls -A | grep branch-outcome-index | grep -v ready | tr '\n' ' ')"
rm -rf "$LAB"

echo "--- S2: legacy + traversal-ish keys mixed with valid keys; covered task stays silent, uncovered surfaces"
newlab
old=$(( $(date +%s) - 30 ))
printf 'done: covered completion already delivered\n' > "$S/covered.status"
perl -e 'utime($ARGV[0],$ARGV[0],$ARGV[1])' "$old" "$S/covered.status"
printf 'failed: uncovered failure\n' > "$S/other.status"
perl -e 'utime($ARGV[0],$ARGV[0],$ARGV[1])' "$old" "$S/other.status"
now=$(date +%s)
{
printf '{"seq":1,"epoch":1,"task":"default:w0:p2","wake":"","verdict":"captain","summary":"legacy 1"}\n'
printf '{"seq":2,"epoch":%s,"task":"covered","wake":"","verdict":"captain","summary":"covered reached main"}\n' "$now"
printf '{"seq":3,"epoch":2,"task":"../escape","wake":"","verdict":"captain","summary":"traversal-shaped key"}\n'
printf '{"seq":4,"epoch":3,"task":"fm-lab:w3:p9","wake":"","verdict":"captain","summary":"legacy 2"}\n'
} > "$S/branch-outcomes.jsonl"
before=$(sha256sum < "$S/branch-outcomes.jsonl")
run "$BIN/fm-wake-drain.sh"; echo "drain rc=$?"
after=$(sha256sum < "$S/branch-outcomes.jsonl")
[ "$before" = "$after" ] && echo "history unchanged: yes" || echo "history unchanged: NO"
echo "ready marker: $(cat "$S/.branch-outcome-index-ready" 2>/dev/null || echo MISSING)"
echo "index files: $(cd "$S" && ls -A | grep branch-outcome-index | grep -v ready | tr '\n' ' ')"
echo "files escaped into $LAB: $(ls -A "$LAB" | grep -c escape)"
rm -rf "$LAB"

echo "--- S3: genuine store fault (malformed JSON row) still fails closed"
newlab
printf 'done: uncovered completion\n' > "$S/fresh.status"
printf '%s\n' '{"seq":1,"epoch":1,"task":"default:w0:p2"}' 'not json {' > "$S/branch-outcomes.jsonl"
run "$BIN/fm-wake-drain.sh"; echo "drain rc=$?"
rm -rf "$LAB"

echo "--- S4: recording new outcomes is unchanged (valid key accepted, endpoint key refused)"
newlab
run "$BIN/fm-branch-outcome.sh" append --task fresh --verdict captain --summary 'new valid outcome'; echo "append valid rc=$?"
run "$BIN/fm-branch-outcome.sh" append --task 'default:w0:p2' --verdict captain --summary 'new endpoint outcome' 2>&1; echo "append endpoint rc=$?"
echo "store rows: $(wc -l < "$S/branch-outcomes.jsonl")"; jq -c '{seq,task,summary}' "$S/branch-outcomes.jsonl"
rm -rf "$LAB"
