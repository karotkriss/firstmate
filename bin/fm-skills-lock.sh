#!/usr/bin/env bash
# fm-skills-lock.sh - regenerate the root skills-lock.json from skills/.
#
# The lock indexes the public installer-facing skills under skills/ for the
# agentskills.io `skills` CLI (https://skills.sh): one entry per skill with a
# local source path and the CLI's folder hash (sha256 over the skill's files,
# sorted by relative path, hashing each relative path then its content).
# Run this after any change under skills/; tests/skills-lock.test.sh fails
# when the committed lock no longer matches the tree.
#
# Usage: bin/fm-skills-lock.sh [--check]
#   --check  exit 1 with a diagnostic instead of rewriting when stale
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
mode=${1:-}

python3 - "$root" "$mode" <<'EOF'
import hashlib, json, os, pathlib, sys
root = pathlib.Path(sys.argv[1])
check = sys.argv[2] == '--check'

def folder_hash(d):
    files = sorted((str(p.relative_to(d)).replace(os.sep, '/'), p)
                   for p in d.rglob('*') if p.is_file())
    h = hashlib.sha256()
    for rel, p in files:
        h.update(rel.encode())
        h.update(p.read_bytes())
    return h.hexdigest()

lock = {"version": 1, "skills": {}}
for entry in sorted((root / 'skills').iterdir()):
    if not (entry / 'SKILL.md').is_file():
        continue
    lock["skills"][entry.name] = {
        "source": f"./skills/{entry.name}",
        "sourceType": "local",
        "computedHash": folder_hash(entry),
    }
text = json.dumps(lock, indent=2) + "\n"
lock_path = root / 'skills-lock.json'
current = lock_path.read_text() if lock_path.is_file() else ''
if check:
    if current != text:
        print('fm-skills-lock: skills-lock.json is stale; run bin/fm-skills-lock.sh', file=sys.stderr)
        sys.exit(1)
    print(f'fm-skills-lock: ok skills={len(lock["skills"])}')
else:
    lock_path.write_text(text)
    print(f'fm-skills-lock: wrote skills-lock.json skills={len(lock["skills"])}')
EOF
