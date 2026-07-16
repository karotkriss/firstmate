#!/usr/bin/env bash
# Tests for bin/fm-brief.sh --phase: the propose-then-implement two-phase
# scaffold for spec-worthy ship tasks.
#
# Matrix:
#   (a) default (no --phase) output is byte-identical to the phase-free contract
#       for every delivery mode - no phase text leaks into ordinary briefs
#   (b) --phase propose keeps every safety section and swaps the definition of
#       done for the committed-OpenSpec-change stop contract (never a PR)
#   (c) --phase implement asserts the existing branch instead of creating one,
#       points the Task section at the committed openspec change directory,
#       and keeps the mode-derived definition of done
#   (d) flag validation: bad value, missing value, and --scout/--secondmate
#       combinations are refused
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BRIEF="$ROOT/bin/fm-brief.sh"
TMP_ROOT=$(fm_test_tmproot fm-brief-two-phase-tests)

# Fresh home with a projects.md registry covering all three delivery modes.
make_home() {
  local home="$TMP_ROOT/$1"
  mkdir -p "$home/data"
  cat > "$home/data/projects.md" <<'EOF'
- alpha - no-mistakes project (added 2026-07-16)
- beta [direct-PR] - direct project (added 2026-07-16)
- gamma [local-only] - local project (added 2026-07-16)
EOF
  printf '%s\n' "$home"
}

# --- (a) default output carries no phase content -----------------------------

test_default_briefs_have_no_phase_content() {
  local home repo brief
  home=$(make_home default)
  for repo in alpha beta gamma; do
    FM_HOME="$home" "$BRIEF" "def-$repo" "$repo" >/dev/null 2>&1
    brief="$home/data/def-$repo/brief.md"
    assert_present "$brief" "default $repo brief was not scaffolded"
    assert_no_grep "PHASE" "$brief" "default $repo brief leaks phase content"
    assert_no_grep "openspec" "$brief" "default $repo brief leaks openspec content"
    assert_grep "git checkout -b fm/def-$repo" "$brief" \
      "default $repo brief lost the branch-creation step"
    assert_grep "at a detached HEAD on a clean default branch" "$brief" \
      "default $repo brief lost the standard setup opener"
  done
  pass "fm-brief: default briefs are phase-free for every delivery mode"
}

# --- (b) --phase propose ------------------------------------------------------

test_propose_brief_stops_at_committed_proposal() {
  local home brief
  home=$(make_home propose)
  FM_HOME="$home" "$BRIEF" prop-a1 alpha --phase propose >/dev/null 2>&1
  brief="$home/data/prop-a1/brief.md"
  assert_present "$brief" "propose brief was not scaffolded"
  # Safety sections intact.
  assert_grep "blocked: launched in primary checkout, not an isolated worktree" "$brief" \
    "propose brief lost the isolation assertion"
  assert_grep "git checkout -b fm/prop-a1" "$brief" \
    "propose brief must still create the task branch"
  assert_grep "Report status by appending one line" "$brief" \
    "propose brief lost the status protocol"
  # Definition of done is the phase A stop contract.
  assert_grep "PHASE A (propose)" "$brief" "propose brief missing phase A marker"
  assert_grep "never a PR" "$brief" "propose brief must forbid a PR"
  assert_grep "do NOT run /no-mistakes" "$brief" \
    "propose brief must not trigger the pipeline"
  assert_grep "done: proposal committed on fm/prop-a1" "$brief" \
    "propose brief missing the phase A done line"
  assert_grep "Implementation follows in a separate session" "$brief" \
    "propose brief missing the separate-session stop"
  # The normal ship DOD must be fully replaced.
  assert_no_grep "checks green" "$brief" "propose brief leaks the ship CI-green contract"
  pass "fm-brief: --phase propose stops at the committed proposal, never a PR"
}

# --- (c) --phase implement ----------------------------------------------------

test_implement_brief_asserts_existing_branch() {
  local home brief iso co
  home=$(make_home implement)
  FM_HOME="$home" "$BRIEF" impl-b1 alpha --phase implement >/dev/null 2>&1
  brief="$home/data/impl-b1/brief.md"
  assert_present "$brief" "implement brief was not scaffolded"
  # No branch creation; the existing branch is asserted instead.
  assert_no_grep "git checkout -b" "$brief" "implement brief must not create a branch"
  assert_grep "git checkout fm/impl-b1" "$brief" \
    "implement brief must check out the existing task branch"
  assert_grep "blocked: phase B launched without a committed proposal on fm/impl-b1" "$brief" \
    "implement brief missing the missing-proposal blocked contract"
  # Task section points at the committed openspec change directory.
  assert_grep "openspec/changes/" "$brief" \
    "implement brief must point at the committed openspec change directory"
  assert_grep "ships in the same PR as your implementation" "$brief" \
    "implement brief must keep the proposal commit in the PR"
  # Safety sections intact, isolation assertion before the checkout step.
  assert_grep "blocked: launched in primary checkout, not an isolated worktree" "$brief" \
    "implement brief lost the isolation assertion"
  iso=$(grep -n 'launched in primary checkout, not an isolated worktree' "$brief" | head -1 | cut -d: -f1)
  co=$(grep -n 'git checkout fm/impl-b1' "$brief" | head -1 | cut -d: -f1)
  if [ -z "$iso" ] || [ -z "$co" ] || [ "$iso" -ge "$co" ]; then
    fail "isolation assertion (line $iso) must precede the checkout step (line $co)"
  fi
  # Mode-derived DOD kept: default mode still ships through no-mistakes.
  assert_grep "run /no-mistakes to validate and ship a PR" "$brief" \
    "implement brief lost the mode-derived definition of done"
  pass "fm-brief: --phase implement asserts the existing branch and specs from openspec"
}

test_implement_brief_keeps_mode_dod() {
  local home brief
  home=$(make_home implement-modes)
  FM_HOME="$home" "$BRIEF" impl-c1 beta --phase implement >/dev/null 2>&1
  brief="$home/data/impl-c1/brief.md"
  assert_grep "direct-PR" "$brief" "implement brief on a direct-PR project lost its mode DOD"
  FM_HOME="$home" "$BRIEF" impl-c2 gamma --phase implement >/dev/null 2>&1
  brief="$home/data/impl-c2/brief.md"
  assert_grep "ready in branch fm/impl-c2" "$brief" \
    "implement brief on a local-only project lost its mode DOD"
  pass "fm-brief: --phase implement keeps the delivery-mode definition of done"
}

# --- (d) flag validation --------------------------------------------------------

test_phase_flag_validation() {
  local home
  home=$(make_home validation)
  if FM_HOME="$home" "$BRIEF" bad-v1 alpha --phase bogus >/dev/null 2>&1; then
    fail "--phase bogus was accepted"
  fi
  assert_absent "$home/data/bad-v1/brief.md" "--phase bogus still scaffolded a brief"
  if FM_HOME="$home" "$BRIEF" bad-v2 alpha --phase >/dev/null 2>&1; then
    fail "--phase without a value was accepted"
  fi
  if FM_HOME="$home" "$BRIEF" bad-v3 alpha --scout --phase propose >/dev/null 2>&1; then
    fail "--phase with --scout was accepted"
  fi
  if FM_HOME="$home" "$BRIEF" bad-v4 --secondmate alpha --phase propose >/dev/null 2>&1; then
    fail "--phase with --secondmate was accepted"
  fi
  # --phase=<value> form works too.
  FM_HOME="$home" "$BRIEF" ok-v5 alpha --phase=propose >/dev/null 2>&1
  assert_present "$home/data/ok-v5/brief.md" "--phase=propose form did not scaffold"
  pass "fm-brief: --phase validation refuses bad values and non-ship kinds"
}

test_default_briefs_have_no_phase_content
test_propose_brief_stops_at_committed_proposal
test_implement_brief_asserts_existing_branch
test_implement_brief_keeps_mode_dod
test_phase_flag_validation
