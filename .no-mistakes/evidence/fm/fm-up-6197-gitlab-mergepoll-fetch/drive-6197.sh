#!/usr/bin/env bash
# Live driver for issue 6197: registers merge polls through the real
# bin/fm-pr-check.sh in a disposable lab FM_HOME, for a GitLab MR whose head
# a separate gate pushed to origin without the project clone fetching it.
# Usage: drive-6197.sh <fm-root-to-test> <label>
set -u
ROOT=$1; LABEL=$2
WT_ROOT=/home/cmckay/.no-mistakes/worktrees/80aee654c94f/01M3S8JHN0ZMC3PVB5FB63S3KP
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$WT_ROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null
W=$(mktemp -d "${TMPDIR:-/tmp}/fm-6197-work.XXXXXX")
trap 'rm -rf "$LAB" "$W"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test
git init -q --bare -b main "$W/gitlab-origin.git"
git init -q -b main "$W/seed"; git -C "$W/seed" commit -q --allow-empty -m init
git -C "$W/seed" push -q "$W/gitlab-origin.git" main
git clone -q "$W/gitlab-origin.git" "$LAB/projects/app"       # the home's project clone
PROJECT=$LAB/projects/app

run_case() {  # <id> <branch> <mr-number> <setup-fn>
  local id=$1 branch=$2 mr=$3 setup=$4 wt url rc out t0 t1 sha
  wt=$W/wt-$id
  git -C "$PROJECT" worktree add -q -b "$branch" "$wt"
  git -C "$wt" commit -q --allow-empty -m "work for $id"
  "$setup" "$wt" "$branch" "$mr"
  sha=$(git -C "$wt" rev-parse HEAD)
  printf '%s\n' "window=firstmate:fm-$id" "endpoint_task_id=$id" "worktree=$wt" \
    "project=$PROJECT" kind=ship mode=no-mistakes > "$LAB/state/$id.meta"
  url="https://gitlab.example.test/grp/app/-/merge_requests/$mr"
  echo "=== [$LABEL] case $id (branch $branch, MR !$mr, head ${sha:0:12})"
  echo "--- origin holds: $(git -C "$W/gitlab-origin.git" for-each-ref --format='%(refname)=%(objectname:short=12)' "refs/heads/$branch" "refs/merge-requests/$mr/head" | tr '\n' ' ')"
  echo "--- project clone tracking refs containing head before: [$(git -C "$PROJECT" for-each-ref --contains="$sha" --format='%(refname)' refs/remotes | tr '\n' ' ')]"
  echo "\$ bin/fm-pr-check.sh $id $url"
  t0=$(date +%s.%N)
  out=$(cd "$wt" && env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE \
    -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE FM_HOME="$LAB" \
    "$ROOT/bin/fm-pr-check.sh" "$id" "$url" 2>&1); rc=$?
  t1=$(date +%s.%N)
  printf '%s\n' "$out" | sed 's/^/    /'
  echo "--- exit=$rc elapsed=$(printf '%.1f' "$(echo "$t1 - $t0" | bc)")s"
  echo "--- meta pr= line: [$(grep '^pr=' "$LAB/state/$id.meta" || true)]  check script: $( [ -f "$LAB/state/$id.check.sh" ] && echo present || echo absent)"
  echo "--- project clone tracking refs containing head after: [$(git -C "$PROJECT" for-each-ref --contains="$sha" --format='%(refname)' refs/remotes | tr '\n' ' ')]"
  echo
}

gate_push() {  # a separate gate clone publishes the head: branch + MR head ref
  local wt=$1 branch=$2 mr=$3
  [ -d "$W/gate.git" ] || git clone -q --bare "$W/gitlab-origin.git" "$W/gate.git"
  git -C "$wt" push -q "$W/gate.git" "HEAD:refs/heads/$branch"
  git -C "$W/gate.git" push -q "$W/gitlab-origin.git" "refs/heads/$branch:refs/heads/$branch" "refs/heads/$branch:refs/merge-requests/$mr/head"
}
pushed_then_local_commit() { gate_push "$@"; git -C "$1" commit -q --allow-empty -m 'never pushed'; }
never_pushed() { :; }
hung_origin() {
  gate_push "$@"
  git -C "$PROJECT" config protocol.ext.allow always
  git -C "$PROJECT" remote set-url origin 'ext::sh -c sleep% 60'
}

run_case green-pushed fm/green-pushed 11 gate_push
run_case unpushed-tip fm/unpushed-tip 12 pushed_then_local_commit
run_case never-pushed fm/never-pushed 13 never_pushed
run_case hung-origin fm/hung-origin 14 hung_origin
