#!/usr/bin/env sh
# check-terrain-member.sh — Screen 2's sectioning is a PERMUTATION, and its
# sections carry NO SELECTION AUTHORITY (Story 20.9, #811; SPEC-terrain as
# resolved 2026-07-27).
#
# The permutation invariant is the whole point: every Strand of the selected
# member appears in EXACTLY ONE section — count-in == count-out — so the
# information loss the abandoned cluster unit suffered cannot compile, and the
# worst case is a badly grouped but complete list. This check FAILS LOUDLY on
# a dropped or duplicated Strand; a count mismatch is never a warning.
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

D="scripts/topic-map-directions.py"

python3 - "$D" <<'PYEOF' || fail=1
import json, re, subprocess, sys, tempfile
D = sys.argv[1]
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

# A member large enough to exercise serve-whole (the measured worst case is
# 40-53), with co-tags to section by, a co-tagless Strand, and a consumed one.
els = []
for n in range(40):
    els.append({"kind": "lesson", "slug": f"w{n}", "title": f"W{n}",
                "gloss": f"claim {n}", "tags": ["workflow", "agents" if n % 2 else "cost"],
                "evidence": [], "consumed": False})
els.append({"kind": "lesson", "slug": "solo", "title": "Solo",
            "gloss": "a workflow-only claim", "tags": ["workflow"],
            "evidence": [], "consumed": True})
els.append({"kind": "journey", "slug": "other", "title": "Other",
            "gloss": "not in this member", "tags": ["agents"],
            "evidence": [], "consumed": False})
m = {"kind": "topic-map", "topics": [], "coverage": {"pin": "h@abc1234"},
     "elements": els}
f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
json.dump(m, f); f.close()
run = lambda tag: subprocess.run(
    ["python3", D, "member", "--map", f.name, "--tag", tag],
    capture_output=True, text=True)

out = run("workflow")
check(out.returncode == 0, f"member composes (rc={out.returncode})")
d = json.loads(out.stdout)

# --- THE PERMUTATION -------------------------------------------------------
member_slugs = {e["slug"] for e in els if "workflow" in e["tags"]}
sectioned = [s for sec in d["sections"] for s in sec["strands"]]
check(len(sectioned) == len(member_slugs) == d["count"] == 41,
      f"count-in == count-out ({len(member_slugs)} in, {len(sectioned)} out)")
check(len(set(sectioned)) == len(sectioned), "no Strand appears twice")
check(set(sectioned) == member_slugs, "no Strand is dropped and none invented")
check("other" not in sectioned, "a Strand outside the member never leaks in")

# --- SERVED WHOLE ----------------------------------------------------------
ids = re.findall(r"^- \*\*((?:L|J)\d+|E\d+\.\d+)\*\* — ", d["listing"], re.M)
check(len(ids) == 41, f"the listing carries every Strand, whole ({len(ids)} lines)")
check("41 Strand(s), shown whole" in d["listing"],
      "the count is disclosed on the listing")

# --- NO SELECTION AUTHORITY ------------------------------------------------
check("already consumed, still selectable" in d["listing"],
      "a consumed Strand is marked, never hidden")
heads = re.findall(r"^## (.+) \(\d+\)$", d["listing"], re.M)
check(len(heads) == len(d["sections"]) >= 2,
      f"sections carry a title and a count — presentation only ({heads[:3]})")
for banned in ("ranked", "top ", "best "):
    check(banned not in d["listing"].lower(),
          f"no ranking language on the listing ({banned!r})")

# --- determinism + selection contract --------------------------------------
check(out.stdout == run("workflow").stdout, "byte-identical across invocations")
check(re.search(r"^- \*\*L\d+\*\* — ", d["listing"], re.M),
      "lines carry the candidate ids selection already resolves")

# --- an empty member is a disclosed refusal --------------------------------
bad = run("no-such-tag")
check(bad.returncode != 0 and "no Strand carries the tag" in bad.stderr,
      "an unknown member is refused with the reason named")

# --- NEGATIVE TEST: a broken permutation must fail RED ---------------------
# Simulated at the assertion layer: feed the checker a sectioning that drops
# one Strand and assert THIS logic would catch it (a check never shown to
# fire is a clean bill nobody earned).
dropped = sectioned[1:]
check(not (len(dropped) == len(member_slugs)),
      "negative test: a dropped Strand breaks count-in == count-out")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

[ "$fail" -eq 0 ] || { printf '\nFAILED.\n' >&2; exit 1; }
printf '\nAll terrain-member checks passed (sectioning is a permutation).\n'
