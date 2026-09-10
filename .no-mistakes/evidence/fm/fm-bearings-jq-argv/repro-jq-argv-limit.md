# fm-bearings-snapshot.sh - jq argv MAX_ARG_STRLEN fix (issue #3056)

End-to-end reproduction driving the real `bin/fm-bearings-snapshot.sh --include-prs --json`
with a fleet whose accumulated candidate-PR JSON exceeds Linux's 128 KiB
MAX_ARG_STRLEN per-argv-argument cap (500 padded PRs across 2 repos = 1000 rows,
per-repo array > 131072 bytes).

## Before the fix (base commit b1ad702, argv accumulation at line 282)

```
bin/fm-bearings-snapshot.sh: line 282: jq: Argument list too long
bin/fm-bearings-snapshot.sh: line 282: jq: Argument list too long
jq: invalid JSON text passed to --argjson
fm-bearings-snapshot: projection failed
not ok - projection failed on PR rows above the per-argument limit
EXIT=1
```

The board is killed exactly at `rows=$(jq -n --argjson a "$rows" --argjson b "$repo_rows" ...)`.

## After the fix (target commit 55c9eee, temp-file + --slurpfile transport)

```
ok - candidate-PR rows above the per-argument limit still project completely
EXIT=0
```

The projection completes; `.candidate_prs | length == 1000`, the PR summary reads
`checked (2 repos, 1000 open)`, and each repo's row batch (> 131072 bytes) is
fully preserved - proving the rows now travel by file, never argv.

## Neighboring PR-path behavior unchanged by the transport switch

```
ok - --include-prs is the only path that fetches, and it enriches correctly
ok - a partial GitHub failure degrades gracefully
ok - live PR enrichment caps repositories with counted expansion
ok - per-repository open-PR caps are disclosed with an expansion knob
ok - TOON and JSON are parity representations of the same model
```
