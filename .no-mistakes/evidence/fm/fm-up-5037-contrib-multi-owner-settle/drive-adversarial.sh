#!/usr/bin/env bash
# Adversarial variants in a disposable lab home, driving bin/fm-contributions.sh poll.
# A: owner beta is open WITH a stale error, owner gamma is already terminal (closed, own checked_at);
#    alpha is merged. Retry with the forge down: beta converges, gamma is untouched, no forge read.
# B: no owner is terminal: poll still performs a fresh forge read (fresh-read path unchanged).
set -u
ROOT=$1
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX"); trap 'rm -rf "$LAB"' EXIT
"$ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null || exit 1
mkdir -p "$LAB/fakebin" "$LAB/forge"
URL=https://github.com/o/r/pull/8
seed() { # task state checked_at error
  mkdir -p "$LAB/data/$1"
  jq -n --arg task "$1" --arg url "$URL" --arg s "$2" --arg at "$3" --arg e "$4" '{schema:"fm-contributions.v1",task:$task,records:[{url:$url,kind:"pr",
    checked_at:$at,error:(if $e == "" then null else $e end),pending:[],seen:[],verdict:null,
    observation:{head:"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",state:$s,draft:false,mergeable:"mergeable",
      review_decision:"APPROVED",can_merge:false,checks:[],reviews:[],events:[]}}]}' > "$LAB/data/$1/contributions.json"
}
printf '#!/bin/sh\nexit 1\n' > "$LAB/fakebin/tmux"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$FORGE/calls"\necho "gh: forge down" >&2\nexit 1\n' > "$LAB/fakebin/gh"
chmod +x "$LAB/fakebin/"*
run() { env -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u NO_MISTAKES_GATE \
  PATH="$LAB/fakebin:$PATH" FORGE="$LAB/forge" FM_HOME="$LAB" FM_CONTRIBUTIONS_NOW=2026-09-16T09:10:00Z "$@"; }
show() { jq -c --arg t "$1" '{task:$t,state:.records[0].observation.state,checked_at:.records[0].checked_at,error:.records[0].error}' "$LAB/data/$1/contributions.json"; }
printf '# Backlog\n\n## Queued\n' > "$LAB/data/backlog.md"
for t in alpha beta gamma; do printf -- '- [ ] %s - Upstream fix %s (repo: sample) (kind: ship)\n' $t "$URL" >> "$LAB/data/backlog.md"; done
seed alpha merged 2026-09-16T09:05:00Z ""
seed beta open 2026-09-16T08:00:00Z "forge observation unavailable or changed during read"
seed gamma closed 2026-09-16T07:00:00Z ""
echo "== A. before retry"; show alpha; show beta; show gamma
cp "$LAB/data/gamma/contributions.json" "$LAB/gamma.before"
: > "$LAB/forge/calls"; out=$(run "$ROOT/bin/fm-contributions.sh" poll); echo "exit=$? stdout=[$out] forge-calls=$(wc -l < "$LAB/forge/calls")"
echo "== A. after retry"; show alpha; show beta; show gamma
cmp -s "$LAB/gamma.before" "$LAB/data/gamma/contributions.json" && echo "gamma (already terminal) left untouched" || echo "gamma CHANGED"
echo "== B. no terminal owner: fresh read still attempted"
seed alpha open 2026-09-16T08:00:00Z ""; seed beta open 2026-09-16T08:00:00Z ""; rm -rf "$LAB/data/gamma"
sed -i '/ gamma /d' "$LAB/data/backlog.md"
: > "$LAB/forge/calls"; out=$(run "$ROOT/bin/fm-contributions.sh" poll); echo "exit=$? stdout=[$out] forge-calls=$(wc -l < "$LAB/forge/calls")"
show alpha; show beta
