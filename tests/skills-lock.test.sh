#!/usr/bin/env bash
# The root skills-lock.json must always match the actual contents of skills/,
# so an edit to a public skill cannot ship with a stale lock hash.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

test_lock_matches_tree() {
  local out
  if ! out=$("$ROOT/bin/fm-skills-lock.sh" --check 2>&1); then
    fail "skills-lock.json is stale against skills/: $out (run bin/fm-skills-lock.sh)"
  fi
  pass "skills-lock.json matches the skills/ tree"
}

test_lock_matches_tree
