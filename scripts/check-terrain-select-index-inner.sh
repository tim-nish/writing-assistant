#!/usr/bin/env sh
# parallel-safe
# tier: inner — indexed-selection assertions against a derived over-budget
# covers: scripts/fixtures/terrain/screen-map.json scripts/topic-map-directions.py
#   fixture map; no seam, no corpus, no assembly. Split from
#   check-terrain-select-inner.sh (#948) — see its sibling
#   check-terrain-select-brief-inner.sh for the split's rationale. Assertion
#   content is unchanged. Measured 2026-07-30 at split: ~1.2s (ceiling 2s).
# removal-signal: the terrain checks are retired or re-shaped under the #910
#   retention sweep (a check provably subsumed by the #857/#858 seam, or the
#   full-tier terrain harnesses rebuilt fixture-based), which re-places these
#   assertions; removed with that pass.
# check-terrain-select-index-inner.sh — indexed selection {index, note}
# against the View's pin, through the real CLI: adoption, free-text
# precedence, stale-pin and no-pin refusals, stop, and ID stability.
set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

D="scripts/topic-map-directions.py"
FIX="scripts/fixtures/terrain/screen-map.json"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# One prep run builds the over-budget map (#950 batching: the big-map builder
# and the static stop answer share an interpreter).
python3 - "$FIX" "$work" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1])); w = sys.argv[2]
# An OVER-BUDGET terrain, built from STRANDS (Story 20.7, #809). It used to be
# built by cloning subtopics; subtopics no longer exist, and a Strand is now
# the only thing that counts toward the screen budget.
strands = list(d.get("elements") or [])
for n in range(12):                       # comfortably past the screen budget
    strands.append({
        "kind": "lesson", "slug": f"widened-{n:02d}",
        "title": f"Lesson {n}",
        # Two topics, so topic-spanning rendering is still exercised.
        "topic": "engineering" if n % 2 else "people",
        "date": f"2026-07-{(n % 28) + 1:02d}",
        "gloss": f"A claim the material itself makes, number {n}",
        "situation": f"LESSONS.md:{n + 10}@abc1234",
        "evidence": [f"LESSONS.md:{n + 10}@abc1234"],
        "consumed": (n == 0),
    })
# A strand whose rendering was NOT served: it must still appear, with the
# reason disclosed, never dropped and never quoting the one-liner as a gloss.
strands.append({
    "kind": "lesson", "slug": "no-rendering", "title": "Unrendered lesson",
    "topic": "people", "date": "2026-07-02",
    "gloss": None,
    "gloss_unavailable": "the served gloss index carries no rendering for this lesson",
    "situation": "LESSONS.md:40@abc1234",
    "evidence": ["LESSONS.md:40@abc1234"], "consumed": False,
})
d["elements"] = strands
d["coverage"] = dict(d.get("coverage", {}),
                     element_topics_read=["delivery", "engineering", "people", "nowhere"],
                     element_topics_skipped=["zeta"])
json.dump(d, open(w + "/big-map.json", "w"))
json.dump({"selection": "stop here", "index": "T1.1", "free_text": ""},
          open(w + "/answer-idx-stop.json", "w"))
PYEOF

python3 "$D" candidates --map "$work/big-map.json" > "$work/big-cands.json"

# One prep call writes every answer fixture and reports the pin and first
# element index (merged from the source check's per-file writers so the check
# clears the inner-tier runtime ceiling — same data, fewer interpreter starts).
pinidx=$(python3 - "$work" <<'PYEOF'
import json, sys
w = sys.argv[1]
pin = json.load(open(w + "/big-map.json"))["coverage"]["pin"]
c = [x for x in json.load(open(w + "/big-cands.json"))["candidates"]
     if x["kind"] == "element"]
idx = c[0]["id"]
json.dump({"index": idx, "note": "through the on-call retro, not the metrics",
           "pin": pin}, open(w + "/answer-idx.json", "w"))
json.dump({"index": idx, "note": "ignored", "pin": pin,
           "free_text": "my own direction, in my own words"},
          open(w + "/answer-idx-free.json", "w"))
json.dump({"index": idx, "note": "x", "pin": "deadbeef"},
          open(w + "/answer-stale.json", "w"))
json.dump({"index": idx, "note": "x"}, open(w + "/answer-nopin.json", "w"))
print(pin, idx)
PYEOF
)
bigpin=${pinidx% *}

python3 "$D" brief --answer "$work/answer-idx.json" --map "$work/big-map.json" \
  > "$work/brief-idx.json" 2>"$work/brief-idx.err" \
  && ok "indexed selection: an index plus a note composes a brief" \
  || err "indexed selection failed: $(cat "$work/brief-idx.err")"

python3 "$D" brief --answer "$work/answer-idx-free.json" --map "$work/big-map.json" \
  > "$work/brief-idx-free.json" 2>/dev/null

# A STALE index is refused with the pin mismatch NAMED — never re-resolved.
if python3 "$D" brief --answer "$work/answer-stale.json" --map "$work/big-map.json" \
     > "$work/brief-stale.out" 2>"$work/brief-stale.err"; then
  err "a stale-pin index produced a brief instead of a refusal"
else
  rc=$?
  [ "$rc" -eq 1 ] && ok "indexed selection: a stale-pin index is refused (exit 1)" \
    || err "stale-pin refusal used exit $rc, not the documented refusal exit"
  grep -q 'pin mismatch' "$work/brief-stale.err" \
    && grep -q 'deadbeef' "$work/brief-stale.err" \
    && grep -q "$bigpin" "$work/brief-stale.err" \
    && ok "indexed selection: the refusal NAMES both pins" \
    || err "the refusal does not name the mismatch: $(cat "$work/brief-stale.err")"
  [ -s "$work/brief-stale.out" ] \
    && err "a refused selection still emitted a brief" \
    || ok "indexed selection: a refused selection emits no brief"
fi

# An index with no pin at all cannot be proven current, so it is refused too.
python3 "$D" brief --answer "$work/answer-nopin.json" --map "$work/big-map.json" \
  > /dev/null 2>"$work/brief-nopin.err" \
  && err "an index without a pin was silently resolved" \
  || { grep -q 'no pin' "$work/brief-nopin.err" \
       && ok "indexed selection: an index without a pin is refused, and says why" \
       || err "wrong no-pin behaviour: $(cat "$work/brief-nopin.err")"; }

# Stopping stays first-class even from the View branch.
python3 "$D" brief --answer "$work/answer-idx-stop.json" --map "$work/big-map.json" \
  >"$work/idx-stop.out" 2>&1 \
  && err "stopping from the View branch produced a brief" \
  || { grep -q 'first-class outcome' "$work/idx-stop.out" \
       && ok "indexed selection: stop here still produces no brief and no run" \
       || err "wrong stop behaviour from the View branch"; }

# ID STABILITY within a pin: two invocations produce identical IDs.
python3 "$D" candidates --map "$work/big-map.json" > "$work/big-cands2.json"
cmp -s "$work/big-cands.json" "$work/big-cands2.json" \
  && ok "indexed selection: IDs are identical across invocations at one pin" \
  || err "the IDs are not stable within a pin"

# --- one assertion run over the produced files (#950 batching) --------------
python3 - "$work" <<'PYEOF' || fail=1
import json, sys
w = sys.argv[1]
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg,
          file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

b = json.load(open(w + "/brief-idx.json"))
cands = json.load(open(w + "/big-cands.json"))["candidates"]
note = "through the on-call retro, not the metrics"
check(note in b["brief"], "the owner's note is carried into the brief VERBATIM")
wording = next(c["direction"] for c in cands if c["id"] == b["index"])
check(b["brief"].startswith(wording),
      "the brief is the subtopic's coverage wording plus the note")
# THE RATIFIED VALUE (Story 20.102, #1080). This path composes the brief AT
# THE TERRAIN GATE from a Strand the owner selected, which is precisely what
# `terrain-adopted` names in the closed pair Story 20.94 (#1050) ratified.
# `owner-authored` is reserved for the owner's own free-form words, and
# asserting it here is what let a machine-composed coverage statement carry an
# attestation that the owner wrote it.
check(b["provenance"] == "terrain-adopted",
      "an adopted index is TERRAIN-ADOPTED — composed at the gate from the "
      "owner's selection, not typed by them (#1080)")
check(b["origin"] == "adopted-index", "the origin records that an index was adopted")
check(isinstance(b["brief"], str), "the outcome is one plain brief string")

b = json.load(open(w + "/brief-idx-free.json"))
check(b["brief"] == "my own direction, in my own words",
      "indexed selection: free text still always wins over an index")
check(b["origin"] == "free-form", "free text over an index records origin free-form")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

[ "$fail" -eq 0 ] && printf '\nAll %s checks passed.\n' "$0" \
  || { printf '\n%s FAILED.\n' "$0" >&2; exit 1; }
