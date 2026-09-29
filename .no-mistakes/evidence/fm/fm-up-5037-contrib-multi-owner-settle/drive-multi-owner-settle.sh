#!/usr/bin/env bash
# Drive bin/fm-contributions.sh poll/snapshot in a disposable lab home:
# two tasks own one PR; the forge reports it merged; the first poll is
# interrupted after owner alpha is saved; the retry runs with the forge down.
# Usage: drive-multi-owner-settle.sh <firstmate-checkout>
set -u
ROOT=$1
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
trap 'rm -rf "$LAB"' EXIT
"$ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null 2>&1 || mkdir -p "$LAB/state" "$LAB/data" "$LAB/config" "$LAB/projects"
mkdir -p "$LAB/fakebin" "$LAB/forge"
URL=https://github.com/o/r/pull/8
printf '# Backlog\n\n## Queued\n- [ ] alpha - Upstream fix %s (repo: sample) (kind: ship)\n- [ ] beta - Same upstream fix %s (repo: sample) (kind: ship)\n' "$URL" "$URL" > "$LAB/data/backlog.md"
for t in alpha beta; do
  mkdir -p "$LAB/data/$t"
  jq -n --arg task "$t" --arg url "$URL" '{schema:"fm-contributions.v1",task:$task,records:[{url:$url,kind:"pr",
    checked_at:"2026-09-16T08:00:00Z",error:null,pending:[],seen:[],verdict:null,
    observation:{head:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",state:"open",draft:false,mergeable:"mergeable",
      review_decision:"APPROVED",can_merge:false,checks:[{name:"test",id:1,status:"completed",conclusion:"success",started_at:"2026-09-16T08:00:00Z"}],reviews:[],events:[]}}]}' \
    > "$LAB/data/$t/contributions.json"
done
# beta carries its own acknowledgement state that must survive settlement.
jq '.records[0].pending=[{token:"comment:77:2026-09-16T07:30:00Z",type:"comment"}] | .records[0].notified=["comment:77:2026-09-16T07:30:00Z"]' \
  "$LAB/data/beta/contributions.json" > "$LAB/x" && mv "$LAB/x" "$LAB/data/beta/contributions.json"
printf '#!/bin/sh\nexit 1\n' > "$LAB/fakebin/tmux"
cat > "$LAB/fakebin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FORGE/calls"
[ ! -e "$FORGE/down" ] || { echo 'gh: forge down' >&2; exit 1; }
H=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
case "$*" in
  'pr view '*headRefOid,reviewDecision*) jq -n --arg h $H '{headRefOid:$h,reviewDecision:"APPROVED"}' ;;
  'pr view '*headRefOid*) echo $H ;;
  'api repos/o/r/pulls/8') jq -n --arg h $H '{state:"closed",user:{login:"author"},head:{sha:$h},draft:false,mergeable:null,merged_at:"2026-09-16T09:00:00Z"}' ;;
  *'/comments?'*|*'/reviews?'*|*'/events?'*|*'/statuses?'*) echo '[[]]' ;;
  *'/check-runs?'*) echo '[{"check_runs":[{"name":"test","id":1,"status":"completed","conclusion":"success","started_at":"2026-09-16T08:00:00Z"}]}]' ;;
  'api repos/o/r') echo '{"permissions":{"push":false}}' ;;
  *) echo "unexpected: $*" >&2; exit 1 ;;
esac
GH
# Interrupt: the staging mktemp for beta's record fails once, after alpha is saved.
REAL_MKTEMP=$(command -v mktemp)
cat > "$LAB/fakebin/mktemp" <<MK
#!/usr/bin/env bash
case "\$*" in *"/beta/.contributions."*) if [ -e "$LAB/forge/interrupt" ]; then rm -f "$LAB/forge/interrupt"; echo 'mktemp: interrupted (simulated crash)' >&2; exit 1; fi ;; esac
exec $REAL_MKTEMP "\$@"
MK
chmod +x "$LAB/fakebin/"*
run() { env -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u NO_MISTAKES_GATE \
  PATH="$LAB/fakebin:$PATH" FORGE="$LAB/forge" FM_HOME="$LAB" "$@"; }
show() { jq -c --arg t "$1" '{task:$t,state:.records[0].observation.state,checked_at:.records[0].checked_at,error:.records[0].error,pending:[.records[0].pending[].token],notified:.records[0].notified}' "$LAB/data/$1/contributions.json"; }

echo "== 1. first poll: forge reports merged; crash before beta is saved"
touch "$LAB/forge/interrupt"
run FM_CONTRIBUTIONS_NOW=2026-09-16T09:05:00Z "$ROOT/bin/fm-contributions.sh" poll; echo "exit=$?"
show alpha; show beta
echo "== 2. retry poll with the forge DOWN (terminal URL must not be re-read)"
: > "$LAB/forge/calls"; touch "$LAB/forge/down"
run FM_CONTRIBUTIONS_NOW=2026-09-16T09:10:00Z "$ROOT/bin/fm-contributions.sh" poll; echo "exit=$?"
echo "forge calls during retry: $(wc -l < "$LAB/forge/calls")"
show alpha; show beta
echo "== 3. a second retry is a no-op (idempotent)"
cp "$LAB/data/beta/contributions.json" "$LAB/beta.before"
run FM_CONTRIBUTIONS_NOW=2026-09-16T09:20:00Z "$ROOT/bin/fm-contributions.sh" poll; echo "exit=$?"
cmp -s "$LAB/beta.before" "$LAB/data/beta/contributions.json" && echo "beta record unchanged by second retry" || echo "beta record CHANGED by second retry"
echo "== 4. projection each owner sees (snapshot --all)"
run "$ROOT/bin/fm-fleet-snapshot.sh" --contribution-input > "$LAB/input.json"
run FM_CONTRIBUTIONS_NOW=2026-09-16T09:20:00Z "$ROOT/bin/fm-contributions.sh" snapshot "$LAB/input.json" --all \
  | jq -c '{known, counts, rows: [.rows[] | {url, tasks, actor, reason, final, checked}]}'
