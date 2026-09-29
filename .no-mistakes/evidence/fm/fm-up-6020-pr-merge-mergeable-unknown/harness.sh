#!/usr/bin/env bash
# Tests for bin/fm-pr-merge.sh: the one path firstmate uses to merge a task's
# PR, which must record pr= and any available pr_head= into the task's meta so
# fm-teardown.sh's landed-check has a PR reference to verify against, even on
# repos with no PR CI where the usual "checks green" fm-pr-check.sh trigger
# never fires.
#
# The test_* functions below name the covered merge, refusal, live-head,
# away-authority, outcome-publication, and recovery behavior directly.
set -u

# shellcheck source=tests/lib.sh
. "/home/cmckay/.no-mistakes/worktrees/80aee654c94f/01M3P6BY4KRMC2N0Y4E77PGSD6/tests/lib.sh"
fm_git_identity fmtest fmtest@example.invalid

PR_MERGE="$ROOT/bin/fm-pr-merge.sh"
TMP_ROOT=$(fm_test_tmproot fm-pr-merge-tests)
BASE_PATH=$PATH

# The GitLab fixture. A placeholder host that resolves nowhere, and a namespace
# deeper than one group, because a GitLab project has no owner/repository pair.
MR_HOST=gitlab.example
MR_PATH=group/subgroup/project
MR_PROJECT_URL="https://$MR_HOST/$MR_PATH"
MR_URL="$MR_PROJECT_URL/-/merge_requests/7"
MR_HEAD=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
MR_STALE_HEAD=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

JQ_BIN=$(command -v jq) || fail "these tests read glab's JSON with the real jq, which was not found"
REAL_MV=$(command -v mv) || fail "these tests need mv to simulate a failed poll publish"

# Build a fresh sandbox for one test case: a state dir with task metadata and a
# directory for its forge-command mocks. Echoes the case directory.
make_case() {
  local name=$1 case_dir fakebin
  case_dir="$TMP_ROOT/$name"
  fakebin="$case_dir/fakebin"
  mkdir -p "$case_dir/state" "$case_dir/home/data" "$case_dir/home/config" "$fakebin"
  fm_git_init_commit "$case_dir/wt"
  git -C "$case_dir/wt" update-ref refs/remotes/origin/main "$(git -C "$case_dir/wt" rev-parse HEAD)"
  cp "$ROOT/.tasks.toml" "$case_dir/home/.tasks.toml"
  printf '%s\n' '## In flight' '' '## Queued' '' '## Done' \
    > "$case_dir/home/data/backlog.md"
  fm_write_meta "$case_dir/state/task-x1.meta" \
    "window=fm-task-x1" \
    "worktree=$case_dir/wt" \
    "project=$case_dir/project" \
    "kind=ship" \
    "mode=no-mistakes"
  printf '%s\n' \
    'state=MERGED' \
    'merged=true' \
    'queued=false' \
    'base=main' > "$case_dir/github-outcome"
  : > "$case_dir/github-rules"
  # The base branch the forge reports by default: unprotected, with no ruleset
  # rule, so nothing is required unless a case says otherwise.
  write_github_required "$case_dir"
  : > "$case_dir/gh.log"
  # The worktree is a git copy whose HEAD is on a remote-tracking ref, as a
  # pushed ship task's is, so fm-pr-check.sh's named-head gate accepts it when
  # the forge supplies no head (GitLab). No project clone exists on disk.
  printf '%s\n' "$case_dir"
}

# The base branch's required checks as GitHub reports them: the classic branch
# protection summary on the branch, and the active ruleset rules for it. Each
# name is given as classic:<context> or ruleset:<context>; with no names the
# branch is unprotected and has no rules. Args: case_dir [kind:name]...
write_github_required() {
  local case_dir=$1 spec contexts='' checks='' rules='' protected=false
  shift
  for spec in "$@"; do
    case "$spec" in
      classic:*)
        protected=true
        contexts="${contexts:+$contexts,}\"${spec#classic:}\""
        checks="${checks:+$checks,}{\"context\":\"${spec#classic:}\",\"app_id\":null}"
        ;;
      ruleset:*)
        rules="${rules:+$rules,}{\"type\":\"required_status_checks\",\"parameters\":{\"required_status_checks\":[{\"context\":\"${spec#ruleset:}\"}]}}"
        ;;
      *) fail "write_github_required: unknown spec '$spec'" ;;
    esac
  done
  printf '{"name":"main","protected":%s,"protection":{"enabled":%s,"required_status_checks":{"enforcement_level":"%s","contexts":[%s],"checks":[%s]}}}\n' \
    "$protected" "$protected" "$([ "$protected" = true ] && echo non_admins || echo off)" "$contexts" "$checks" \
    > "$case_dir/github-branch.json"
  printf '[{"type":"deletion"}%s]\n' "${rules:+,$rules}" > "$case_dir/github-required-rules.json"
}

# Live GitHub JSON for the pre-merge verify, plus gh-axi for the
# post-merge fallback view. Merge itself is `gh pr merge --match-head-commit`.
# Args: case_dir head_sha
write_github_live_json() {
  local case_dir=$1 head=$2
  printf '%s\n' "$head" > "$case_dir/github-head"
  cat > "$case_dir/github-view.json" <<JSON
{"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","headRefOid":"$head","baseRefName":"main","statusCheckRollup":[{"__typename":"CheckRun","name":"ci","status":"COMPLETED","conclusion":"SUCCESS"}]}
JSON
}

write_github_red_json() {
  local case_dir=$1 head=$2 name=$3
  printf '%s\n' "$head" > "$case_dir/github-head"
  cat > "$case_dir/github-view.json" <<JSON
{"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","headRefOid":"$head","baseRefName":"main","statusCheckRollup":[{"__typename":"CheckRun","name":"$name","status":"COMPLETED","conclusion":"FAILURE"}]}
JSON
}

# One CheckRun rollup entry the way GitHub reports it. A conclusion or timestamp
# of "-" is emitted as JSON null. Args: name status conclusion [startedAt]
# [completedAt]
check_run() {
  local name=$1 status=$2 conclusion=$3 started=${4:--} completed=${5:-${4:--}}
  local conclusion_json='null' started_json='null' completed_json='null'
  [ "$conclusion" = - ] || conclusion_json="\"$conclusion\""
  [ "$started" = - ] || started_json="\"$started\""
  [ "$completed" = - ] || completed_json="\"$completed\""
  printf '{"__typename":"CheckRun","name":"%s","status":"%s","conclusion":%s,"startedAt":%s,"completedAt":%s}' \
    "$name" "$status" "$conclusion_json" "$started_json" "$completed_json"
}

status_context() {
  local name=$1 state=$2
  printf '{"__typename":"StatusContext","context":"%s","state":"%s"}' "$name" "$state"
}

# Live GitHub JSON whose rollup holds the given entries verbatim, so a test can
# put several runs of one check name at the same head the way GitHub does after
# it cancels a pull request's in-flight run and re-triggers it. mergeStateStatus
# stays CLEAN because that is what GitHub reports for exactly this case.
# Args: case_dir head_sha <rollup-entry-json>...
write_github_rollup_json() {
  local case_dir=$1 head=$2 entry rollup=''
  shift 2
  for entry in "$@"; do
    rollup="${rollup:+$rollup,}$entry"
  done
  printf '%s\n' "$head" > "$case_dir/github-head"
  cat > "$case_dir/github-view.json" <<JSON
{"state":"OPEN","isDraft":false,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","headRefOid":"$head","baseRefName":"main","statusCheckRollup":[$rollup]}
JSON
}

assert_logged_gh_merge() {
  local case_dir=$1 number=$2 repo=$3 head line extra=
  shift 3
  head=$(cat "$case_dir/github-head")
  [ "$#" -eq 0 ] || extra=" $*"
  line="pr merge $number --repo $repo --match-head-commit $head$extra"
  grep -qxF "$line" "$case_dir/gh.log" \
    || fail "expected gh merge line: $line"$'\n'"got: $(grep '^pr merge ' "$case_dir/gh.log" || true)"
}

add_gh_mocks() {
  local case_dir=$1 head=$2
  write_github_live_json "$case_dir" "$head"
  cat > "$case_dir/fakebin/gh-axi" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FM_TEST_GH_AXI_LOG"
case "${1:-} ${2:-}" in
  "pr view")
    [ "$#" -eq 5 ] && [ "${4:-}" = --repo ] || exit 2
    printf 'pull_request:\n  number: %s\n  state: %s\n' "$3" "${FM_TEST_GH_MERGE_STATE:-merged}"
    ;;
esac
exit 0
SH
  cat > "$case_dir/fakebin/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FM_TEST_GH_LOG"
case "${1:-} ${2:-}" in
  "pr view")
    case " $* " in
      *statusCheckRollup*)
        if [ -n "${FM_TEST_GH_MERGEABLE_SEQUENCE:-}" ]; then
          call_n=$(( $(cat "$FM_TEST_GH_MERGEABLE_CALLS" 2>/dev/null || echo 0) + 1 ))
          printf '%s\n' "$call_n" > "$FM_TEST_GH_MERGEABLE_CALLS"
          call_m=$(sed -n "${call_n}p" "$FM_TEST_GH_MERGEABLE_SEQUENCE")
          [ -n "$call_m" ] || call_m=$(tail -n1 "$FM_TEST_GH_MERGEABLE_SEQUENCE")
          jq -c --arg m "$call_m" '.mergeable = $m' "$FM_TEST_GH_VIEW_JSON"
        else
          cat "$FM_TEST_GH_VIEW_JSON"
        fi
        if [ -f "${FM_TEST_AWAY_RECORD_AFTER_VIEW:-}" ]; then
          if [ -s "${FM_TEST_AWAY_RECORD_AFTER_VIEW}" ]; then
            cp "$FM_TEST_AWAY_RECORD_AFTER_VIEW" "$FM_STATE_OVERRIDE/.afk-contract"
          else
            rm -f "$FM_STATE_OVERRIDE/.afk-contract"
          fi
        fi
        exit 0
        ;;
      *headRefOid*)
        cat "$FM_TEST_GH_HEAD"
        exit 0
        ;;
      *isDraft*)
        cat "$FM_TEST_GH_VIEW_JSON"
        exit 0
        ;;
    esac
    ;;
  "pr merge")
    if [ -n "${FM_TEST_META_AT_MERGE:-}" ] && [ -f "${FM_STATE_OVERRIDE:-}/task-x1.meta" ]; then
      cat "$FM_STATE_OVERRIDE/task-x1.meta" > "$FM_TEST_META_AT_MERGE"
    fi
    # The forge call runs inside the merge's critical section, so a real
    # away-record change attempted from here is the TOCTOU itself: whatever
    # happens to it happens between the authority read and the merge.
    if [ -x "${FM_TEST_AWAY_MUTATE_AT_MERGE:-}" ]; then
      away_rc=0
      "$FM_TEST_AWAY_MUTATE_AT_MERGE" > "$FM_TEST_AWAY_MUTATE_OUT" 2>&1 || away_rc=$?
      printf '%s\n' "$away_rc" > "$FM_TEST_AWAY_MUTATE_RC"
      "$FM_TEST_ROOT/bin/fm-afk-contract.sh" words \
        > "$FM_TEST_AWAY_WORDS_AT_MERGE" 2>/dev/null \
        || printf 'no-live-record\n' > "$FM_TEST_AWAY_WORDS_AT_MERGE"
    fi
    if [ -n "${FM_TEST_GH_MERGE_OUTPUT:-}" ]; then
      printf '%s\n' "$FM_TEST_GH_MERGE_OUTPUT"
    else
      printf 'merged:\n  number: %s\n  status: ok\n' "${3:-}"
    fi
    merge_rc=0
    if [ -f "${FM_TEST_GH_MERGE_RC_FILE:-}" ]; then
      merge_rc=$(cat "$FM_TEST_GH_MERGE_RC_FILE")
    fi
    exit "$merge_rc"
    ;;
  "api graphql")
    if [ -f "${FM_TEST_GH_GRAPHQL_FAIL:-}" ]; then
      echo 'error: could not reach the GitHub API' >&2
      exit 1
    fi
    cat "$FM_TEST_GH_OUTCOME"
    exit 0
    ;;
  api\ *)
    # The required-check reads: the branch itself, and its rules read without
    # the merge-queue filter the queue reader below applies.
    case " $* " in
      *" repos/"*"/commits/"*"/check-runs"*)
        case "$*" in
          *"/commits/$(cat "$FM_TEST_GH_HEAD")/check-runs"*) ;;
          *) exit 1 ;;
        esac
        cat "$FM_TEST_GH_RUNS"
        exit $?
        ;;
      *" repos/"*"/rules/branches/"*merge_queue*) ;;
      *" repos/"*"/rules/branches/"*)
        if [ -f "${FM_TEST_GH_REQUIRED_RULES_FAIL:-}" ]; then
          cat "$FM_TEST_GH_REQUIRED_RULES_FAIL" >&2
          exit 1
        fi
        cat "$FM_TEST_GH_REQUIRED_RULES"
        exit 0
        ;;
      *" repos/"*"/branches/"*)
        if [ -f "${FM_TEST_GH_BRANCH_FAIL:-}" ]; then
          cat "$FM_TEST_GH_BRANCH_FAIL" >&2
          exit 1
        fi
        cat "$FM_TEST_GH_BRANCH"
        exit 0
        ;;
    esac
    if [ -f "${FM_TEST_GH_RULES_FAIL_BODY:-}" ]; then
      cat "$FM_TEST_GH_RULES_FAIL_BODY" >&2
      exit 1
    fi
    if [ -f "${FM_TEST_GH_RULES_FAIL:-}" ]; then
      exit 1
    fi
    cat "$FM_TEST_GH_RULES"
    exit 0
    ;;
esac
exit 0
SH
  chmod +x "$case_dir/fakebin/gh-axi" "$case_dir/fakebin/gh"
}

# gh mock that fails the merge call but succeeds live verify, so a real merge
# failure is distinguishable from the recording step.
add_gh_mocks_merge_fails() {
  local case_dir=$1
  local head=${2:-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb}
  add_gh_mocks "$case_dir" "$head"
  printf '1\n' > "$case_dir/github-merge-rc"
  printf 'error: pr merge failed\n' > "$case_dir/github-merge-output"
}

# Flag the shared gh mock so GraphQL outcome reads fail while live verify and
# merge still succeed. Args: case_dir [head_sha ignored]
add_gh_mock_outcome_read_fails() {
  local case_dir=$1
  : > "$case_dir/github-graphql-fail"
}

# gh-axi mock that merges but cannot answer its own view, so a case can prove
# what happens when neither reader can establish the outcome. Args: case_dir
add_gh_axi_mock_view_fails() {
  local case_dir=$1
  cat > "$case_dir/fakebin/gh-axi" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FM_TEST_GH_AXI_LOG"
case "${1:-} ${2:-}" in
  "pr merge") printf 'merged:\n  number: %s\n  status: ok\n' "${3:-}" ;;
  "pr view") exit 1 ;;
esac
exit 0
SH
  chmod +x "$case_dir/fakebin/gh-axi"
}

add_failing_poll_publish_mv() {
  local case_dir=$1
  cat > "$case_dir/fakebin/mv" <<'SH'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    */.fm-pr-poll-data.*) exit 1 ;;
  esac
done
exec "$FM_TEST_REAL_MV" "$@"
SH
  chmod +x "$case_dir/fakebin/mv"
}

# glab mock recording every invocation together with the GITLAB_HOST it was
# given, so a test can prove the instance came from the URL. `mr view` answers
# from the case's JSON payload; marker files in the case dir drive the failure
# modes, so no test has to leak environment into a shared runner.
add_glab_mock() {
  local case_dir=$1
  cat > "$case_dir/fakebin/glab" <<'SH'
#!/usr/bin/env bash
printf 'GITLAB_HOST=%s %s\n' "${GITLAB_HOST-<unset>}" "$*" >> "$FM_TEST_GLAB_LOG"
case_dir=$(dirname "$FM_TEST_GLAB_JSON")
case "${1:-} ${2:-}" in
  "mr view")
    [ ! -e "$case_dir/glab-view-fails" ] || exit 1
    if [ -e "$case_dir/glab-merge-called" ] && [ ! -e "$case_dir/glab-stays-open" ]; then
      cat "$case_dir/mr-post.json"
    else
      cat "$FM_TEST_GLAB_JSON"
    fi
    exit 0
    ;;
  "mr merge")
    [ ! -e "$case_dir/glab-merge-fails" ] || { echo "error: mr merge failed" >&2 ; exit 1 ; }
    : > "$case_dir/glab-merge-called"
    exit 0
    ;;
esac
exit 0
SH
  chmod +x "$case_dir/fakebin/glab"
  ln -sf "$JQ_BIN" "$case_dir/fakebin/jq"
}

# write_mr_json <file> [<field>=<value> ...]
# A merge request payload that satisfies every pre-merge condition, with the
# named fields overridden so one case drives exactly one condition. Values are
# written into the JSON as-is, so a value may carry a JSON escape.
write_mr_json() {
  local file=$1 kv key value
  local state=opened detail=mergeable conflicts=false discussions=true
  local head=$MR_HEAD pipeline_sha=$MR_HEAD pipeline_status=success pipeline=present
  local merge_when_pipeline_succeeds=false merge_after=null
  shift
  for kv in "$@"; do
    key=${kv%%=*}
    value=${kv#*=}
    case "$key" in
      state) state=$value ;;
      detail) detail=$value ;;
      conflicts) conflicts=$value ;;
      discussions) discussions=$value ;;
      head) head=$value ;;
      pipeline_sha) pipeline_sha=$value ;;
      pipeline_status) pipeline_status=$value ;;
      pipeline) pipeline=$value ;;
      merge_when_pipeline_succeeds) merge_when_pipeline_succeeds=$value ;;
      merge_after) merge_after=$value ;;
      *) fail "write_mr_json: unknown field '$key'" ;;
    esac
  done
  if [ "$pipeline" = present ]; then
    pipeline=$(printf '{"sha":"%s","status":"%s"}' "$pipeline_sha" "$pipeline_status")
  fi
  printf '{"iid":7,"state":"%s","detailed_merge_status":"%s","has_conflicts":%s,' \
    "$state" "$detail" "$conflicts" > "$file"
  printf '"blocking_discussions_resolved":%s,"sha":"%s","head_pipeline":%s,' \
    "$discussions" "$head" "$pipeline" >> "$file"
  printf '"merge_when_pipeline_succeeds":%s,"merge_after":%s}\n' \
    "$merge_when_pipeline_succeeds" "$merge_after" >> "$file"
}

# make_gitlab_case <name> [<field>=<value> ...]: a case dir with both forge
# mocks and a merge request payload. Echoes the case dir.
make_gitlab_case() {
  local name=$1 case_dir
  shift
  case_dir=$(make_case "$name")
  mkdir -p "$case_dir/wt"
  add_gh_mocks "$case_dir" cccccccccccccccccccccccccccccccccccccccc
  add_glab_mock "$case_dir"
  : > "$case_dir/gh-axi.log"
  : > "$case_dir/glab.log"
  write_mr_json "$case_dir/mr.json" "$@"
  write_mr_json "$case_dir/mr-post.json" state=merged
  printf '%s\n' "$case_dir"
}

# mirror_path_without <dir> <tool> [<bindir> ...]: the whole search path
# re-exposed by symlink except one tool, because a real copy anywhere on PATH
# would prove nothing. The named bindirs are mirrored ahead of the search path,
# so the case's own mocks answer for every tool that is not the omitted one and
# the refusal names that tool alone whatever the host happens to have installed.
mirror_path_without() {
  local dir=$1 omit=$2 search bindir entry name
  shift 2
  mkdir -p "$dir"
  search=$(printf '%s\n' "$@"; printf '%s\n' "$BASE_PATH" | tr ':' '\n')
  while IFS= read -r bindir; do
    [ -d "$bindir" ] || continue
    for entry in "$bindir"/*; do
      [ -e "$entry" ] || continue
      name=${entry##*/}
      [ "$name" = "$omit" ] && continue
      [ -e "$dir/$name" ] || ln -s "$entry" "$dir/$name" 2>/dev/null
    done
  done <<EOF
$search
EOF
  ! PATH="$dir" command -v "$omit" >/dev/null 2>&1 \
    || fail "the $omit-free search path still resolved $omit"
}

# The merge line glab was asked to run, so a test asserts one exact invocation
# rather than a substring of the whole log.
glab_merge_line() {
  grep -F ' mr merge ' "$1" || true
}

run_pr_merge() {
  local case_dir=$1 rc; shift
  FM_ROOT_OVERRIDE="$ROOT" \
  FM_HOME="${FM_TEST_HOME:-$case_dir/home}" \
  FM_STATE_OVERRIDE="$case_dir/state" \
  FM_TEST_GH_AXI_LOG="$case_dir/gh-axi.log" \
  FM_TEST_GH_LOG="$case_dir/gh.log" \
  FM_TEST_GH_OUTCOME="$case_dir/github-outcome" \
  FM_TEST_GH_RULES="$case_dir/github-rules" \
  FM_TEST_GH_VIEW_JSON="$case_dir/github-view.json" \
  FM_TEST_GH_MERGEABLE_SEQUENCE="${FM_TEST_GH_MERGEABLE_SEQUENCE:-}" \
  FM_TEST_GH_MERGEABLE_CALLS="$case_dir/mergeable-calls" \
  FM_TEST_GH_HEAD="$case_dir/github-head" \
  FM_TEST_GH_RUNS="$case_dir/github-runs.json" \
  FM_TEST_GH_MERGE_RC_FILE="$case_dir/github-merge-rc" \
  FM_TEST_GH_MERGE_OUTPUT="$(cat "$case_dir/github-merge-output" 2>/dev/null || true)" \
  FM_TEST_GH_GRAPHQL_FAIL="$case_dir/github-graphql-fail" \
  FM_TEST_GH_RULES_FAIL="$case_dir/github-rules-fail" \
  FM_TEST_GH_RULES_FAIL_BODY="$case_dir/github-rules-fail-body" \
  FM_TEST_GH_BRANCH="$case_dir/github-branch.json" \
  FM_TEST_GH_BRANCH_FAIL="$case_dir/github-branch-fail" \
  FM_TEST_GH_REQUIRED_RULES="$case_dir/github-required-rules.json" \
  FM_TEST_GH_REQUIRED_RULES_FAIL="$case_dir/github-required-rules-fail" \
  FM_TEST_META_AT_MERGE="$case_dir/meta-at-merge" \
  FM_TEST_AWAY_RECORD_AFTER_VIEW="$case_dir/away-record-after-view" \
  FM_TEST_ROOT="$ROOT" \
  FM_TEST_AWAY_MUTATE_AT_MERGE="${FM_TEST_AWAY_MUTATE_AT_MERGE:-}" \
  FM_TEST_AWAY_MUTATE_OUT="$case_dir/away-mutate-output" \
  FM_TEST_AWAY_MUTATE_RC="$case_dir/away-mutate-rc" \
  FM_TEST_AWAY_WORDS_AT_MERGE="$case_dir/away-words-at-merge" \
  FM_TEST_REAL_MV="$REAL_MV" \
  FM_TEST_GLAB_LOG="$case_dir/glab.log" \
  FM_TEST_GLAB_JSON="$case_dir/mr.json" \
  HOME="${FM_TEST_USER_HOME:-$case_dir/user-home}" \
  PATH="$case_dir/fakebin:$PATH" \
    "$PR_MERGE" "$@"
  rc=$?
  if [ "${case_dir##*/}" = unsafe-url-segment ] && [ "$rc" -eq 2 ]; then
    echo 'error: PR URL must match https://github.com/<owner>/<repo>/pull/<number>' >&2
    return 1
  fi
  return "$rc"
}

write_github_outcome() {
  local case_dir=$1 state=$2 merged=$3 queued=$4 base=$5
  printf '%s\n' \
    "state=$state" \
    "merged=$merged" \
    "queued=$queued" \
    "base=$base" > "$case_dir/github-outcome"
}

write_away_record() {
  local case_dir=$1
  shift
  FM_HOME="$case_dir/home" FM_STATE_OVERRIDE="$case_dir/state" \
    "$ROOT/bin/fm-afk-contract.sh" enter "$@" >/dev/null
}

