#!/usr/bin/env sh
# parallel-safe
# tier: inner — stdlib-python over a private mktemp state root; no network, no
#   repo mutation, no touch of the real state root (XDG_STATE_HOME redirected).
# measured: 205ms (three runs, 2026-08-04: 200/210/210ms)
# covers: scripts/resolve-paths.py docs/storage-architecture.md
# ends: the run-workspace retention rule deleting something still needed, or
#   silently keeping everything. D2a states the rule as KEEP-conditions so
#   "delete work" is unproducible; this asserts the conditions actually hold
#   in the shipped scan, including the not-`complete` clause that protects
#   resume. NOT generation-side preventable: a retention rule is a predicate
#   over accumulated state, and nothing at the point of writing it can see the
#   states it will meet.
# removal-signal: run workspaces ceasing to be machine-local disposable state
#   — e.g. moving under a store with its own lifecycle — at which point D2a
#   has no subject and this check retires with it.
# check-workspace-gc.sh — the D2a lifecycle (Story 20.215, #1393).
# POSIX sh + stdlib Python.

set -eu
root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1; }
cd "$root"
fail=0
ok()  { printf 'ok:   %s\n' "$1"; }
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT INT TERM

python3 - "$work" <<'PY' || fail=1
import importlib.util as iu, json, os, sys, time
w = sys.argv[1]
spec = iu.spec_from_file_location("rp", "scripts/resolve-paths.py")
rp = iu.module_from_spec(spec); spec.loader.exec_module(rp)
bad = []
def need(c, m):
    if not c: bad.append(m)

OLD = time.time() - 40 * 86400
def mk(key, rid, stage, age_old=True, host=None):
    d = os.path.join(w, key, "runs", rid); os.makedirs(d, exist_ok=True)
    json.dump({"next_stage": stage}, open(os.path.join(d, "checkpoint.json"), "w"))
    if age_old: os.utime(d, (OLD, OLD))
    if host is not None:
        with open(os.path.join(w, key, rp.HOST_MARKER), "w") as fh:
            fh.write(host + "\n")
    return d

# One host repo: 8 old completed runs, one old INCOMPLETE, one young completed.
live = os.path.join(w, "live-host"); os.makedirs(live, exist_ok=True)
olds = [mk("-a-repo", "old-%02d" % i, "complete") for i in range(8)]
held = mk("-a-repo", "held-run", "quality-gate")
young = mk("-a-repo", "young-run", "complete", age_old=False)
unknown_cp = os.path.join(w, "-a-repo", "runs", "broken")
os.makedirs(unknown_cp); open(os.path.join(unknown_cp, "checkpoint.json"), "w").write("{not json")
os.utime(unknown_cp, (OLD, OLD))

scan = rp._gc_scan(w)
cand = {r["path"] for r in scan["runs"]}

# AC-2 clause 1 — a run not `complete` is NEVER a candidate, at any age.
need(held not in cand, "an INCOMPLETE run was a deletion candidate — this is "
     "the clause that protects resume")
need(unknown_cp not in cand, "a run with an unreadable checkpoint was a "
     "candidate — unknown is not `complete`, and guessing deletes resumable work")
# AC-2 clause 2 — the N most recent completed are kept.
# `young` is completed too and legitimately occupies one of the N slots, so
# the invariant is over ALL completed runs, not over `olds` alone.
all_completed = set(olds) | {young}
need(len(all_completed) - len(cand & all_completed) == rp.GC_KEEP_RECENT,
     "the keep-recent clause kept %d completed runs, not %d"
     % (len(all_completed) - len(cand & all_completed), rp.GC_KEEP_RECENT))
# AC-2 clause 3 — nothing young is ever a candidate.
need(young not in cand, "a run younger than the age floor was a candidate")
# AC-1 — every candidate carries its reason.
need(all(r.get("why") for r in scan["runs"]), "a candidate carried no reason")

# AC-3 — deadness is decidable ONLY from the marker, and is three-valued.
# N+1 runs: with <= N the keep-recent clause keeps them all, so the dir could
# never qualify — the fixture must exceed the threshold to exercise the case.
dead = os.path.join(w, "-dead-host")
for i in range(rp.GC_KEEP_RECENT + 1):
    mk("-dead-host", "r%d" % i, "complete", host=os.path.join(w, "gone"))
scan2 = rp._gc_scan(w)
need(any(r["path"] == dead for r in scan2["repos"]),
     "a host dir whose marker names a missing path, all runs candidates, was "
     "not itself a candidate")
mk("-legacy-host", "r1", "complete")          # no marker at all
scan3 = rp._gc_scan(w)
need(all("legacy" not in r["path"] for r in scan3["repos"]),
     "a host dir with NO marker was called dead — repo_key is lossy, so that "
     "is cannot-determine and must never be a candidate")
mk("-live-host2", "r1", "complete", host=live)
scan4 = rp._gc_scan(w)
need(all("live-host2" not in r["path"] for r in scan4["repos"]),
     "a host dir whose marker names an EXISTING path was called dead")

# The stray/unknown split: empty is sweepable, non-empty is report-only.
os.makedirs(os.path.join(w, "empty-thing"))
nonempty = os.path.join(w, "nonempty-thing"); os.makedirs(nonempty)
open(os.path.join(nonempty, "something.txt"), "w").write("x")
scan5 = rp._gc_scan(w)
need(any(r["path"].endswith("empty-thing") for r in scan5["stray"]),
     "an empty non-runs directory was not a stray candidate")
need(any(r["path"] == nonempty for r in scan5["unknown"]),
     "a NON-EMPTY non-runs directory was not report-only — the rule has "
     "nothing to say about it and must disclose rather than guess")
need(all(r["path"] != nonempty for r in scan5["stray"]),
     "a non-empty directory was a DELETION candidate — the predicate is "
     "too broad and would reach a legitimate sibling")

# AC-8 — THE MUTATED RULE. A gc test that only ever sees a correct rule
# certifies nothing about what it protects: with keep_recent=0 and no age
# floor, the previously-protected classes must STILL be protected, because
# clause 1 is a property of the workspace rather than of the thresholds.
mut = rp._gc_scan(w, keep_recent=0, min_age_days=0)
mcand = {r["path"] for r in mut["runs"]}
need(held not in mcand, "under a mutated rule the INCOMPLETE run became a "
     "candidate — clause 1 is not independent of the thresholds")
need(unknown_cp not in mcand, "under a mutated rule the unknown-checkpoint "
     "run became a candidate")
need(young in mcand, "the mutated rule changed nothing — the fixture is not "
     "actually exercising the thresholds, so its passes are vacuous")

for m in bad: print("FAIL: 20.215: " + m)
if not bad:
    for line in ("a run not `complete` is never a candidate, at any age",
                 "an unreadable checkpoint is `unknown`, kept like incomplete",
                 "the N most recent completed runs are kept",
                 "nothing younger than the age floor is a candidate",
                 "every candidate carries the reason it qualified",
                 "host-dir deadness is decidable only from the marker, and "
                 "no marker means NOT dead",
                 "empty non-runs dirs sweep; non-empty ones are report-only",
                 "under a MUTATED rule the protected classes stay protected"):
        print("ok:   20.215: " + line)
sys.exit(1 if bad else 0)
PY

# The contract carrier and the command's own refusal to delete unasked.
grep -q 'D2a' docs/storage-architecture.md \
  && ok "20.215: the D2a lifecycle section is present in the contract" \
  || err "20.215: docs/storage-architecture.md carries no D2a section"
out=$(XDG_STATE_HOME="$work/xdg" python3 scripts/resolve-paths.py gc 2>&1 || true)
printf '%s' "$out" | grep -qE 'deleted [0-9]+ of' \
  && err "20.215: bare \`gc\` reported deleting something — it must require --yes" \
  || ok "20.215: bare \`gc\` deletes nothing without --yes"

if [ "$fail" -eq 0 ]; then
  printf '\nAll workspace-gc checks passed.\n'; exit 0
else
  printf '\nworkspace-gc checks FAILED.\n' >&2; exit 1
fi
