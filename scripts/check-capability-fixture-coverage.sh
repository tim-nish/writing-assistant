#!/usr/bin/env sh
# parallel-safe
# tier: full — assembles a real map through the seam (gateway stub + fixture
# covers: scripts/fixtures/policy-gateway-stub.py scripts/fixtures/terrain/screen-map-served.json scripts/resolve-paths.py scripts/terrain_map.py
#   repos), so it is corpus/seam-dependent by construction. Measured 2026-07-30
#   at adoption: ~1.5s, over the INNER_MS ceiling and correctly declared rather
#   than absorbed (#913).
# removal-signal: CAPABILITIES.md stops being a cross-repository claim surface
#   (no upstream sitting consults it for two months AND the duplicate-build
#   class that produced #805 has not recurred), or capability rows are subsumed
#   by an upstream existence surface reading this repo's checks directly.
#   Removed with whichever lands first. Recorded per the #910/#913 clause and
#   restated from the governing spec section, never invented here.
# check-capability-fixture-coverage.sh — the fixture corpus must EXERCISE every
# declared capability (Story 20.57, #940; SPEC-writing-assistant §"Capability
# evidence is OBSERVED, and the fixture corpus is the coverage instrument").
#
# WHY THIS EXISTS. CAPABILITIES.md promises that "if the capability breaks, its
# evidence fails, and the manifest fails with it". #933 falsified it: Terrain's
# Journey material rendered nothing for days while the `terrain` row stayed
# `implemented` and its evidence check kept passing. The mechanism was not a
# missing assertion — it was that the committed fixture carried
# `journey_renderings: 0`, so a journey assertion would have been VACUOUS even
# if written. Nothing noticed the corpus never exercised the thing.
#
# TWO FIXTURES, DELIBERATELY. `screen-map.json` is a NOT-SERVED corpus
# (`gloss.served: false`) and stays that way — the not-served disclosure path is
# itself a declared capability (`gloss-consumption`: "and discloses on the
# surface when they are not served"), and four inner checks assert it. This
# check owns the SERVED corpus. Covering both is the instrument; flipping the
# one fixture would have destroyed the assertions for half the contract.
#
# POSIX sh + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

MANIFEST=${MANIFEST:-CAPABILITIES.md}
SERVED_FIXTURE="scripts/fixtures/terrain/screen-map-served.json"
fail=0
err()  { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()   { printf 'ok:   %s\n' "$1"; }
# A failed PRECONDITION is neither a pass nor a failure (spec clause (b)): a
# vacuous pass is the #933 failure mode, and a hard failure on a corpus that
# simply carries no such material would make the check unusable elsewhere.
pre()  { printf 'precondition: %s\n' "$1" >&2; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
XDG_STATE_HOME="$work/state"; export XDG_STATE_HOME
XDG_CONFIG_HOME="$work/xdg";  export XDG_CONFIG_HOME

# --- the SERVED fixture corpus ---------------------------------------------
# A hub that serves lesson renderings AND a journey arc, through the shipped
# seam. The journey record is a PAIRED record carrying a `journeys/<tag>`
# rendering, which is what makes the shard request fire — the exact path that
# was unexercised when #933 landed.
FX="$work/gateway.json"
python3 - "$FX" <<'PYEOF'
import json, sys
sha = "1" * 40   # declared synthetic prefix (check-publication-boundary.sh)
json.dump({
    "pin": f"product-lab@{sha}",
    "tools": ["glossary_entry", "lessons_index", "topic_thread", "policy_lookup",
              "gloss_index", "element_survey"],
    "elements_file": "gloss/ELEMENTS.jsonl",
    "gloss_index": [
        ["LESSONS.md", 3, "- [The retry storm](lessons/retry-storm.md) — retries without a budget"],
        ["LESSONS.md", 4, "- [Team shape](lessons/team-shape.md) — a rota nobody owns"],
    ],
    "gloss_shards": {
        "journeys/engineering": [
            ["gloss/journeys/engineering.md", 1, "## retry-storm"],
            ["gloss/journeys/engineering.md", 2,
             "It started as a slow dependency and became an outage."],
        ],
    },
    "elements": [
        {"kind": "lesson", "slug": "retry-storm", "title": "The retry storm",
         "tags": ["engineering"], "topic": "engineering", "date": "2026-07-20"},
        {"kind": "lesson", "slug": "team-shape", "title": "Team shape",
         "tags": ["engineering"], "topic": "engineering", "date": "2026-07-21"},
        {"kind": "journey", "slug": "retry-storm", "tags": ["engineering"],
         "renderings": ["journeys/engineering"]},
    ],
}, open(sys.argv[1], "w"))
PYEOF
WRITING_ASSISTANT_GATEWAY_CMD="python3 $root/scripts/fixtures/policy-gateway-stub.py $FX"
export WRITING_ASSISTANT_GATEWAY_CMD

h="$work/host"; mkdir -p "$h/docs"; git -C "$h" init -q
a="$work/articles"; mkdir -p "$a/drafts" "$a/backlog"; git -C "$a" init -q
: > "$a/INDEX.md"
printf '# intake\n\nThe retry storm doubled token spend.\n' > "$h/docs/intake.md"
git -C "$h" add -A >/dev/null 2>&1
git -C "$h" -c user.email=t@e -c user.name=t commit -qm init >/dev/null 2>&1
key=$(python3 "$root/scripts/resolve-paths.py" repo-key --root "$h")
cfg="$work/xdg/writing-assistant/repos/$key/writing-sources.yaml"
mkdir -p "$(dirname "$cfg")"
printf 'sources:\n  - path: docs\noutput:\n  drafts: %s\npolicy_source:\n  enabled: true\n  repo: product-lab\n' \
  "$a/drafts/" > "$cfg"

# PRECONDITION, reported distinctly (spec clause (b)). The corpus reaches the
# hub through the gateway STUB, and a stub that does not register the tools this
# corpus needs cannot serve records or shards. That is a fixture-layer fact, not
# a broken capability — so it is reported as its own state rather than as a pass
# (which would be the #933 vacuum) or a failure (which would blame the product
# for a fixture gap).
if ! python3 - "$FX" <<'PYEOF'
import json, sys
tools = set(json.load(open(sys.argv[1])).get("tools") or [])
missing = {"gloss_index", "element_survey"} - tools
sys.exit(1 if missing else 0)
PYEOF
then
  pre "the gateway stub does not register gloss_index/element_survey — the served corpus cannot be built, so capability coverage is UNDETERMINED here (neither exercised nor broken)"
  printf '\n%s: precondition unmet, no verdict.\n' "$0" >&2
  exit 0
fi
ok "precondition: the stub registers the tools the served corpus needs"

if ! python3 "$root/scripts/terrain_map.py" assemble --root "$h" \
       > "$work/map.json" 2>"$work/err"; then
  err "the served fixture corpus does not assemble: $(cat "$work/err")"
  printf '\n%s FAILED.\n' "$0" >&2; exit 1
fi
ok "the served fixture corpus assembles"

# --- 1. the corpus EXERCISES the served capabilities ------------------------
python3 - "$work/map.json" <<'PYEOF' || fail=1
import json, sys
d = json.load(open(sys.argv[1]))
g = d.get("gloss") or {}
bad = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg,
          file=sys.stdout if cond else sys.stderr)
    if not cond: bad.append(msg)

check(g.get("served") is True,
      "gloss-consumption: the corpus SERVES the hub (served=true), so a "
      "rendering assertion over it is not vacuous")
check((g.get("lesson_renderings") or 0) > 0,
      f"gloss-consumption: lesson renderings are exercised "
      f"({g.get('lesson_renderings')})")
# THE #933 ASSERTION. This is the one that could not have been written before,
# because the only fixture carried journey_renderings: 0.
check((g.get("journey_renderings") or 0) > 0,
      f"terrain: JOURNEY renderings are exercised "
      f"({g.get('journey_renderings')}) — the path that silently died in #933")
check(bool(g.get("journeys_requested")),
      f"terrain: a journeys/<tag> shard is REQUESTED "
      f"({g.get('journeys_requested')}) — requested, not awaited (CAP-4)")
s = g.get("strands") or {}
check(s.get("source") == "element manifest (records)",
      f"terrain: membership is record-authoritative, not the tier-1 fallback "
      f"({s.get('source')!r})")
check((s.get("journeys_attached") or 0) > 0,
      f"terrain: the arc ATTACHES to its lesson row "
      f"({s.get('journeys_attached')} attached)")
sys.exit(1 if bad else 0)
PYEOF

# --- 2. DRIFT GUARD: the committed served fixture matches a fresh assembly ---
# Same shape as check-topic-map-screen.sh's guard: per-run paths and the pin are
# excluded. A real change to the served map's shape lands here first.
if [ ! -f "$SERVED_FIXTURE" ]; then
  err "$SERVED_FIXTURE does not exist — regenerate it from this check's corpus"
else
  python3 - "$work/map.json" "$SERVED_FIXTURE" <<'PYEOF' \
    && ok "drift guard: the committed served fixture matches a fresh assembly" \
    || err "the committed served fixture has drifted — regenerate $SERVED_FIXTURE"
import json, sys
def norm(p):
    d = json.load(open(p))
    for k in ("articles_repo", "host_root"):
        d.pop(k, None)
    d.get("coverage", {}).pop("pin", None)
    return d
a, b = norm(sys.argv[1]), norm(sys.argv[2])
if a != b:
    ka = {k for k in a if a[k] != b.get(k)} | {k for k in b if k not in a}
    print("drift in keys: %s" % sorted(ka), file=sys.stderr)
    sys.exit(1)
PYEOF
fi

# --- 3. every declared capability is either EXERCISED or a NAMED GAP ---------
# Clause (c)'s completeness half: a capability with no fixture coverage is
# visible as a gap rather than silently uncovered. The manifest is parsed by
# COLUMN HEADER, never by position and never by capability name — the property
# that lets another consumer repo adopt the format unedited (#805).
python3 - "$MANIFEST" <<'PYEOF' || fail=1
import re, sys

# Capabilities this check's served corpus exercises directly, with the assertion
# above standing as the evidence. Declared here rather than inferred from the
# row: inference would drift with every manifest edit.
EXERCISED = {"terrain", "terrain-screen", "gloss-consumption"}

rows, headers = [], None
for line in open(sys.argv[1], encoding="utf-8"):
    if not line.lstrip().startswith("|"):
        continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if headers is None:
        if "id" in cells and "status" in cells:
            headers = cells
        continue
    if all(set(c) <= set("-: ") for c in cells):
        continue
    if len(cells) != len(headers):
        continue
    rows.append(dict(zip(headers, cells)))

if not rows:
    print("FAIL: no capability rows parsed from the manifest", file=sys.stderr)
    sys.exit(1)

live = [r for r in rows if r.get("status") in ("implemented", "partial")]
print(f"ok:   {len(live)} live capability row(s) parsed by column header")

gaps = [r["id"].strip("`") for r in live if r["id"].strip("`") not in EXERCISED]
covered = sorted(r["id"].strip("`") for r in live if r["id"].strip("`") in EXERCISED)
print(f"ok:   fixture-exercised capabilities: {covered}")

# A GAP IS REPORTED, NEVER A FAILURE. Clause (c) makes the set of uncovered
# capabilities visible; it does not demand a fixture per capability today, and
# turning that into a failure would be the one-observable-per-feature shape the
# governing decision rejected. The gap list IS the instrument.
if gaps:
    print("gap:  declared but not fixture-exercised by this check: "
          + ", ".join(sorted(gaps)), file=sys.stderr)
    print("      each is covered by its own row evidence only — see the story "
          "question in 20.57 on a per-row coverage expression", file=sys.stderr)
PYEOF

[ "$fail" -eq 0 ] && printf '\nAll %s checks passed.\n' "$0" \
  || { printf '\n%s FAILED.\n' "$0" >&2; exit 1; }
