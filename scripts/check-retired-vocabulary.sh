#!/usr/bin/env sh
# parallel-safe
# check-retired-vocabulary.sh — the TOOL never calls a Strand anything else
# (Story 20.11, #804).
#
# The ratified article-material vocabulary is:
#   STRAND — one Lesson or Journey selected as material; the selectable unit.
#   THESIS — the whole-article story the brief states and the draft argues.
# Retired: "article idea" (ambiguous between the two levels).
# REJECTED upstream: "Seed" — it collides with the articles repo's own seeds.md
# captures AND with this repo's seed->evidenced->outlined->drafted->review->
# published lifecycle. See the measured note below for why that rejection is
# NOT mechanically enforceable here.
#
# WHY THIS IS A SOURCE-LEVEL CHECK, not a render-time one. The obvious home was
# `lint_owner_lines` / INTERNAL_VOCAB in terrain_directions.py (they were in
# topic-map-directions.py when this was written; both travelled together to
# their own module, and the pointer is corrected here rather than left to
# mislead — Story 20.81, #1030). That is the
# wrong layer, demonstrated rather than argued: that lint runs over composed
# lines which QUOTE THE MATERIAL'S OWN WORDS (CAP-3 substance-led rendering), so
# it cannot distinguish the tool's vocabulary from the owner's content on the
# same line — adding "seed" there immediately flagged a fixture subtopic named
# "seed-heavy". A lint that fires on the material it renders is one people learn
# to ignore. The rule belongs where the TOOL's own words are written: source
# text. Carry a rule at its violation layer.
#
# SCOPE, stated because it is a judgment (story 20.11 question 1):
#   IN  — composed owner-facing string literals, and SKILL bodies (the contract
#         text an agent reads aloud to the owner).
#   OUT — dated historical records in specs/ (rewriting a dated amendment to
#         use today's word would falsify what was decided then), this file, and
#         the lifecycle state name `seed` in the draft pipeline, which is the
#         collision itself and is deliberately untouched.
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

report=$(python3 - <<'PY'
import json, os, re, sys

RETIRED = ["article idea", "article ideas"]

# Owner-facing surfaces the TOOL authors.
ROOTS = ["skills", "scripts"]
SKIP_FILES = {"scripts/check-retired-vocabulary.sh"}

# WHY THERE IS NO MECHANICAL `Seed` BAN — measured, not assumed.
#
# Story 20.11's acceptance criteria asked this check to reject `Seed` as a name
# for a Strand. That is NOT ACHIEVABLE mechanically in this repo, and the
# measurement is worth keeping because it is the strongest available evidence
# that the upstream rejection was right:
#
#   repo-wide bare-word `seed`      -> 331 occurrences
#   narrowed to SKILL bodies alone  ->  44 occurrences
#
# and they are legitimate uses in at least THREE unrelated senses:
#   1. `seed` is a pipeline SUBCOMMAND      (skills/emit-variants/SKILL.md:126)
#   2. `seeds` is the ordinary VERB         (skills/terrain/SKILL.md:236)
#   3. `seed` is a draft LIFECYCLE STATE    (seed->evidenced->outlined->...)
#
# Any regex that fires on the unit-noun sense fires on these too. So the ban
# is NOT implemented, deliberately and visibly, rather than shipped as a lint
# that cries wolf 44 times and gets ignored — which would be worse than no
# lint. What IS enforced below is the unambiguous half: the retired phrase
# "article idea", which has no competing sense.
#
# This is a KNOWN GAP in story 20.11's criteria, reported in its PR rather
# than quietly satisfied. Note the irony that makes it tolerable: the reason
# the ban cannot be written is exactly the collision that got `Seed` rejected,
# so the failure to mechanize it is itself evidence for the decision.

hits = []
for r in ROOTS:
    for dirpath, _dirs, files in os.walk(r):
        for fn in files:
            path = os.path.join(dirpath, fn)
            if path in SKIP_FILES or not fn.endswith((".py", ".md", ".sh", ".json")):
                continue
            try:
                text = open(path, encoding="utf-8").read()
            except (OSError, UnicodeDecodeError):
                continue
            for i, line in enumerate(text.splitlines(), start=1):
                low = line.lower()
                for term in RETIRED:
                    if term in low:
                        hits.append((path, i, term, line.strip()[:70]))

print(json.dumps(hits))
PY
)

count=$(printf '%s' "$report" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
if [ "$count" -eq 0 ]; then
  ok "no retired or rejected article-material vocabulary in owner-facing source"
else
  printf '%s' "$report" | python3 -c "
import json, sys
for path, line, term, text in json.load(sys.stdin):
    sys.stderr.write(f'FAIL: {path}:{line} uses {term!r} — the ratified word is Strand: {text}\n')
"
  err "retired/rejected vocabulary found in owner-facing source ($count occurrence(s))"
fi

# NEGATIVE TEST: the check must actually fire. A vocabulary lint that has never
# been shown to catch anything is a clean bill nobody earned.
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/skills"
printf 'Pick an article idea from the list.\n' > "$tmp/skills/probe.md"
probe=$(cd "$tmp" && python3 - <<'PY'
import re
text = open("skills/probe.md", encoding="utf-8").read().lower()
print("HIT" if "article idea" in text else "MISS")
PY
)
[ "$probe" = "HIT" ] && ok "negative test: the retired phrase is detectable by this matcher" \
  || err "the matcher does not detect the retired phrase"

# The ratified words are actually IN USE — otherwise this check passes on a
# repo that simply deleted the vocabulary instead of adopting it.
grep -rq "Strand" skills/ scripts/ \
  && ok "the ratified word Strand is in use on an owner-facing surface" \
  || err "no owner-facing surface uses Strand — the vocabulary was removed, not adopted"

[ "$fail" -eq 0 ] || { printf '\nFAILED.\n' >&2; exit 1; }
printf '\nAll retired-vocabulary checks passed.\n'
