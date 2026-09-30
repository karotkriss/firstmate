#!/usr/bin/env bash
# Live driver for #6171: run the real bin/fm-spawn.sh (base or target checkout)
# into a disposable lab home, with a project whose own config sets
# core.hooksPath to <mode>, then execute the exact worker launch line spawn
# produced inside a real tmux pane on a private socket and report the commit.
# Usage: drive.sh <fm-root> <mode: empty|unresolvable|valueless|husky>
set -u
FMROOT=$1 MODE=$2
. "$FMROOT/tests/fixtures.sh"
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
"$FMROOT/bin/fm-lab-home.sh" create "$LAB" >/dev/null || { echo "lab create failed"; exit 2; }
trap 'TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab kill-server >/dev/null 2>&1; chmod -R u+w "$LAB" 2>/dev/null; rm -rf "$LAB"' EXIT
mkdir -p "$LAB/tmux" "$LAB/user-home"
touch "$LAB/state/.last-watcher-beat"; echo claude > "$LAB/config/crew-harness"
ID=hookspath-6171-z01
fm_test_spawn_brief "$LAB" "$ID"
PROJ="$LAB/case/project" WT="$LAB/case/wt"
fm_git_worktree "$PROJ" "$WT" "wt-6171" >/dev/null 2>&1
# The repository's default hooks dir holds a pre-commit that must NOT run when
# core.hooksPath is empty (plain git runs none).
mkdir -p "$(git -C "$PROJ" rev-parse --path-format=absolute --git-common-dir)/hooks"
HOOKDIR=$(cd "$PROJ" && cd "$(git rev-parse --git-common-dir)/hooks" && pwd)
printf '#!/bin/sh\necho default-pre-commit-RAN >&2\ntouch "%s/default-pre-commit.ran"\n' "$LAB" > "$HOOKDIR/pre-commit"; chmod +x "$HOOKDIR/pre-commit"
case $MODE in
  empty) git -C "$PROJ" config core.hooksPath '' ;;
  *) : ;;  # written after spawn: spawn's own pre-launch git checks read config
esac
FAKE=$(fm_test_make_spawn_fakebin "$LAB/fake")
printf '#!/usr/bin/env bash\nshift\nexec "$@"\n' > "$FAKE/timeout"; chmod +x "$FAKE/timeout"
: > "$LAB/launch.log"
CMD="git commit -q --allow-empty --trailer 'Co-authored-by: Cursor <cursoragent@cursor.com>' -m 'fix: worker commit under hooksPath=$MODE'; echo commit-exit=\$?"
out=$(env -u FM_ROOT_OVERRIDE -u FM_STATE_OVERRIDE -u FM_DATA_OVERRIDE -u FM_CONFIG_OVERRIDE -u FM_PROJECTS_OVERRIDE \
  FM_HOME="$LAB" HOME="$LAB/user-home" CLAUDE_CONFIG_DIR= FM_SPAWN_NO_GUARD=1 FM_FAKE_PANE_PATH="$WT" \
  FM_FAKE_LAUNCH_LOG="$LAB/launch.log" TMUX="fake,1,0" PATH="$FAKE:$PATH" \
  "$FMROOT/bin/fm-spawn.sh" "$ID" "$PROJ" --mode no-mistakes --yolo off "$CMD" 2>&1); st=$?
echo "== fm-spawn exit=$st"; [ $st = 0 ] || { echo "$out" | tail -5; exit 3; }
case $MODE in
  valueless) printf '[core]\n\thooksPath\n' >> "$PROJ/.git/config" ;;
  unresolvable) git -C "$PROJ" config core.hooksPath '~fm-no-such-user-6171/hooks' ;;
  husky) mkdir -p "$WT/.husky"; printf '#!/bin/sh\necho husky-pre-commit-RAN >&2\n' > "$WT/.husky/pre-commit"; chmod +x "$WT/.husky/pre-commit"; git -C "$PROJ" config core.hooksPath .husky ;;
esac
echo "== worker launch prefix: $(sed -E 's/(GIT_CONFIG_VALUE_0=[^;]*;).*/\1 .../' "$LAB/launch.log")"
HEAD0=$(git -C "$WT" -c core.hooksPath=x rev-parse HEAD)
# Real tmux pane on the lab's private socket runs the launch line spawn built.
cp "$LAB/launch.log" "$LAB/launch.sh"
env -u NO_MISTAKES_GATE -u FM_GATE_REFUSE_BYPASS TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab new-session -d -x 200 -y 50 -s worker -c "$WT" \
  "env -u GIT_CONFIG_COUNT -u GIT_CONFIG_KEY_0 -u GIT_CONFIG_VALUE_0 GIT_AUTHOR_NAME=Worker GIT_AUTHOR_EMAIL=w@example.invalid GIT_COMMITTER_NAME=Worker GIT_COMMITTER_EMAIL=w@example.invalid bash --norc -c 'bash $LAB/launch.sh; echo PANE-DONE; sleep 30'"
for _ in $(seq 1 100); do p=$(TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab capture-pane -p -t worker); case $p in *PANE-DONE*) break;; esac; sleep 0.1; done
echo "== worker pane:"; printf '%s\n' "$p" | sed '/^$/d'
HEAD1=$(git -C "$WT" -c core.hooksPath=x rev-parse HEAD)
[ "$HEAD0" = "$HEAD1" ] && echo "== result: commit REFUSED (HEAD unchanged)" || { echo "== result: commit LANDED"; echo "== message:"; git -C "$WT" log -1 --format=%B | sed 's/^/   /'; }
[ -e "$LAB/default-pre-commit.ran" ] && echo "== default .git/hooks/pre-commit RAN" || echo "== default .git/hooks/pre-commit did not run"
