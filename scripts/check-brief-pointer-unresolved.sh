#!/usr/bin/env sh
# parallel-safe
# covers: skills/draft-article/** scripts/draft-pipeline.py
#   scripts/write-article-plan.py
# tier: inner — greps and one in-process validator call; no pipeline run, no
#   corpus, no seam. Measured 2026-07-31 at adoption: ~0.2s (ceiling 2s).
# removal-signal: `brief_source` stops being recorded on the plan — if a later
#   decision removes the pointer, or ratifies drafting AS a terrain consumer
#   (which #1050 forbids and names the ground for), this check is asserting the
#   absence of a thing that no longer exists and retires with it.
# check-brief-pointer-unresolved.sh — Story 20.94 (#1050); SPEC-article-draft-
# pipeline, the 2026-07-31 amendment.
#
# THE LOAD-BEARING HALF OF #1050 IS A PROHIBITION, NOT A FIELD. `brief_source`
# records where a terrain-adopted brief came from, and **the pipeline may never
# resolve it**. The ratified boundary property forbids drafting learning which
# producer ran, and its stated ground is that resolving a terrain pointer would
# oblige draft-article to know terrain's rendering, invocation and lifetime. A
# value nothing reads creates no such obligation — so what has to be asserted is
# an ABSENCE, and an absence nothing checks is one nobody notices ending.
#
# POSIX sh + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

# The DRAFTING surface: the stages and the pipeline they drive. `brief_source`
# may be WRITTEN here (stage 0 records it) and may never be READ.
#
# THE DETECTION IS IN PYTHON, NOT `grep -E`. The first cut used
# `(open|json\.load)[^\n]*brief_source`, which in a POSIX bracket expression
# reads as "not a backslash and not the letter n" — so it silently failed to
# match `json.load(open(plan["brief_source"]))`, and the check that was supposed
# to catch a resolver passed on one. A guard that cannot fail is worse than no
# guard, so the matching is done where it can be read.

# --- AC1/AC2/AC6:# --- AC1/AC2/AC6: the vocabulary is a closed PAIR, and the record is pins-first
python3 - <<'PYEOF' || fail=1
import importlib.util as u
import json
import os
import sys

spec = u.spec_from_file_location("wap", "scripts/write-article-plan.py")
wap = u.module_from_spec(spec)
spec.loader.exec_module(wap)

bad = 0


def check(cond, msg):
    global bad
    if cond:
        print(f"ok:   {msg}")
    else:
        print(f"FAIL: {msg}", file=sys.stderr)
        bad = 1


DRAFT_PY = "scripts/draft-pipeline.py"
DRAFT_MD = "skills/draft-article"
RESOLVERS = ("open(", "os.stat", "isfile", "os.path.exists", "read_text",
             "json.load", "Path(", "realpath", "abspath")


def lines_with(path, needle):
    with open(path, encoding="utf-8") as fh:
        return [(i, l.rstrip()) for i, l in enumerate(fh, 1) if needle in l]


# AC3 — no drafting code path reads, opens, stats or resolves the pointer.
hits = [(i, l) for i, l in lines_with(DRAFT_PY, "brief_source")
        if any(r in l for r in RESOLVERS)]
check(not hits,
      "AC3: no drafting code path RESOLVES brief_source — the pipeline may "
      "record that pointer and may never follow it; resolving it makes "
      "drafting a terrain consumer, obliged to know terrain's rendering, "
      f"invocation and lifetime ({hits[:1]})")

# The stage files are prompts, so the prohibition is broken there in prose: an
# instruction to open, read or follow the pointer is the same defect. A line
# that says the pointer is NEVER read is the criterion being met, not broken.
VERBS = ("open", "read", "follow", "resolve", "load", "inspect")
NEGATED = ("never", "not opened", "no stage", "nothing reads", "may never")
bad_prose = []
for name in sorted(os.listdir(os.path.join(DRAFT_MD, "stages"))) + ["SKILL.md"]:
    path = (os.path.join(DRAFT_MD, "stages", name) if name != "SKILL.md"
            else os.path.join(DRAFT_MD, name))
    if not os.path.isfile(path):
        continue
    for i, l in lines_with(path, "brief_source"):
        low = l.lower()
        if any(v in low for v in VERBS) and not any(n in low for n in NEGATED):
            bad_prose.append((path, i, l))
check(not bad_prose,
      "AC3: no draft-article stage file instructs resolving brief_source "
      f"({bad_prose[:1]})")

# AC4 — no stage BRANCHES on brief_provenance. A record widening, not a
# pipeline fork: a conditional on the producer is the fork, whether or not it
# resolves anything.
branches = [(i, l) for i, l in lines_with(DRAFT_PY, "brief_provenance")
            if any(t in l for t in ("if ", "elif ", "==", "!=", "match "))]
check(not branches,
      "AC4: no drafting code path branches on brief_provenance — the draft, "
      "the harvest emphasis and the argument plan are byte-identical "
      f"whichever producer shaped the brief ({branches[:1]})")

# AC1 — a closed pair, and every other value still refused.
check(tuple(wap.BRIEF_PROVENANCE) == ("owner-authored", "terrain-adopted"),
      f"AC1: the vocabulary is the closed pair {wap.BRIEF_PROVENANCE}")


SRC = json.dumps({"pins": {"terrain": "10e13b2083a3", "hub": "abc1234"},
                  "artifact": "/state/terrain-runs/2026/brief.json"})


def plan_issues(**extra):
    """The schema issues a conforming plan carrying `extra` produces."""
    fields = {"kind": "article-plan", "slug": "a-plan", "intent": "F2",
              "claim": "a claim", "status": "drafting", "run_id": "r1",
              "pin": "abc1234"}
    fields.update(extra)
    text = ("---\n" + "".join(f"{k}: {v}\n" for k, v in fields.items())
            + "---\n\nbody\n")
    return {k: v for k, v in wap.validate_plan(text, "plans/a-plan.md")}


# AC1 — the refusal names the REASON, not only the permitted values.
found = plan_issues(brief_provenance="tool-invented").get("brief_provenance")
check(found is not None and "never a tool-invented scope" in found,
      "AC1: a third value is refused, and the refusal names the reason rather "
      f"than only listing what is permitted ({(found or '')[:60]!r})")
check("brief_provenance" not in plan_issues(
          brief_provenance="terrain-adopted", brief_source=SRC),
      "AC1: `terrain-adopted` is accepted")
check("brief_provenance" not in plan_issues(brief_provenance="owner-authored"),
      "AC1: `owner-authored` is accepted, unchanged")

# AC2 — the pointer rides `terrain-adopted` and carries the pins.
check("brief_source" in plan_issues(brief_provenance="terrain-adopted"),
      "AC2: `terrain-adopted` without a source is refused — recording the "
      "producer and not what it produced from is the lossy record #1050 names")
check("brief_source" in plan_issues(brief_provenance="owner-authored",
                                    brief_source=SRC),
      "AC2: a pointer on an owner-typed brief is refused")
check("brief_source" not in plan_issues(brief_provenance="terrain-adopted",
                                        brief_source=SRC),
      "AC2: a well-formed pointer on a terrain-adopted brief is accepted")

# AC6 — PINS FIRST. A record with a path and no pins is refused, because a
# stale path with nothing behind it is exactly the authoritative-looking
# pointer to nothing this shape exists to avoid; a record with pins and no
# path is fine, which is the fallback shape #1050 named in advance.
try:
    wap.parse_brief_source(json.dumps({"artifact": "/gone"}))
    check(False, "AC6: a path with no pins is refused")
except ValueError as e:
    check("pins" in str(e), f"AC6: a path with no pins is refused ({e!s:.55})")
check(wap.parse_brief_source(json.dumps(
          {"pins": {"terrain": "t", "hub": "h"}}))["pins"]["hub"] == "h",
      "AC6: pins WITHOUT a path are valid — the named fallback shape, so a "
      "pointer is never required to look resolvable")

# AC2 — no new store. The record carries a pointer and refuses to grow one.
try:
    wap.parse_brief_source(json.dumps(
        {"pins": {"terrain": "t", "hub": "h"}, "registry": "x"}))
    check(False, "AC2: an extra key is refused")
except ValueError as e:
    check("never a store" in str(e),
          f"AC2: an extra key is refused — this is a pointer, not a store "
          f"({e!s:.45})")

# AC3, on the validator itself: it validates and never resolves.
src = open("scripts/write-article-plan.py", encoding="utf-8").read()
body = src.split("def parse_brief_source", 1)[1].split("\ndef ", 1)[0]
check(not any(t in body for t in ("open(", "os.stat", "isfile", "exists(")),
      "AC3: parse_brief_source validates the pointer and never touches it")

sys.exit(1 if bad else 0)
PYEOF
[ $? -eq 0 ] || fail=1

[ "$fail" -eq 0 ] || { printf '\nFAILED.\n' >&2; exit 1; }
printf '\nAll brief-pointer checks passed (recorded, never resolved).\n'
