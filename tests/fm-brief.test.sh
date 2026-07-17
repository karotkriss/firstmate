#!/usr/bin/env bash
# Behavior tests for bin/fm-brief.sh generated scaffolds.
#
# Covers the PR evidence-image upload rule: a no-mistakes ship brief must
# instruct the crewmate to upload run evidence images to the PR in one
# `gh attach --comment` call, fail-open (one-time self-install, then fall back
# to the local-path text), and skip silently when no images exist. A scout
# brief delivers a report, not a PR, so it must never carry the rule.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-brief-tests)

test_ship_brief_has_evidence_upload_rule() {
  local home brief
  home="$TMP_ROOT/ship-home"
  mkdir -p "$home/data"
  FM_HOME="$home" "$ROOT/bin/fm-brief.sh" evid-ship-a1 alpha >/dev/null 2>&1
  brief="$home/data/evid-ship-a1/brief.md"
  assert_present "$brief" "ship brief was not scaffolded"
  assert_grep 'gh attach --repo <owner>/<repo> --comment' "$brief" \
    "ship brief is missing the one-call gh attach upload command"
  assert_grep 'gh extension install enthus-appdev/gh-attach' "$brief" \
    "ship brief is missing the one-time self-install fallback"
  assert_grep 'never block or delay the ship' "$brief" \
    "ship brief is missing the fail-open contract"
  assert_grep 'skip this step silently' "$brief" \
    "ship brief is missing the no-images skip clause"
  pass "fm-brief: no-mistakes ship brief carries the fail-open evidence-upload rule"
}

test_scout_brief_has_no_evidence_upload_rule() {
  local home brief
  home="$TMP_ROOT/scout-home"
  mkdir -p "$home/data"
  FM_HOME="$home" "$ROOT/bin/fm-brief.sh" evid-scout-b2 alpha --scout >/dev/null 2>&1
  brief="$home/data/evid-scout-b2/brief.md"
  assert_present "$brief" "scout brief was not scaffolded"
  assert_no_grep 'gh attach' "$brief" \
    "scout brief must not carry the evidence-upload rule"
  pass "fm-brief: scout brief stays free of the evidence-upload rule"
}

test_ship_brief_has_evidence_upload_rule
test_scout_brief_has_no_evidence_upload_rule
