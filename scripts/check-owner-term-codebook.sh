#!/usr/bin/env sh
# parallel-safe
# covers: scripts/terrain_members.py skills/terrain/SKILL.md skills/terrain/steps/*.md
# check-owner-term-codebook.sh — a term meant to reach the owner is DEFINED
# where the owner reads it (Story 20.26, #861; SPEC-writing-assistant,
# owner-surface register, property (d)).
#
# WHAT THIS IS NOT. It is not a per-surface denial list and it never grows
# `INTERNAL_VOCAB` or `FORBIDDEN_MARKERS` — extending those is prohibited as
# the response to a register leak, and they could not express this rule anyway:
# the defect here is an ABSENT DEFINITION, not a present token. A denial list
# can only delete.
#
# WHAT IT ENFORCES, positively:
#   1. every declared first-class owner term has a real entry in the codebook;
#   2. the codebook carries no dead entry nothing declares;
#   3. every owner-facing surface using the vocabulary is ONE STEP from the
#      codebook — it carries a resolvable pointer, and the pointer resolves;
#   4. it REPORTS and never rewrites (the #637 rule: a surface the tool
#      silently launders hides the derivation defect that produced it).
#
# ITS STATED LIMIT: it binds DECLARED terms. Catching an undeclared new coinage
# is the same enumeration problem this class is trying to leave behind, and it
# belongs to the typed composition seam — still an open question in the spec.
# POSIX shell only — the loop's gate runs every check as `sh "$t"`
# (`~/.tanuki/scenarios/writing-assistant.scenarios.json`, key `loop.test_cmd`),
# so `set -o pipefail`, here-strings and process substitution are unavailable:
# a bash-only check fails the gate on `main` rather than guarding anything (#866).
set -u
cd "$(dirname "$0")/.."
fail=0
TMP=$(mktemp); TERMS_FILE=$(mktemp); trap 'rm -f "$TMP" "$TERMS_FILE"' EXIT
ok()   { echo "ok:   $1"; }
bad()  { echo "FAIL: $1" >&2; fail=1; }

DOC=$(python3 -c 'import importlib.util as u;s=u.spec_from_file_location("m","scripts/terrain_members.py");m=u.module_from_spec(s);s.loader.exec_module(m);print(m.OWNER_TERMS_DOC)')
# ONE TERM PER LINE, never a space-joined string: a ratified term may be a
# compound ("group claim", #888), and word-splitting one would demand a
# definition for each half — failing on a term nothing declares.
python3 -c 'import importlib.util as u;s=u.spec_from_file_location("m","scripts/terrain_members.py");m=u.module_from_spec(s);s.loader.exec_module(m);print("\n".join(m.OWNER_TERMS))' > "$TERMS_FILE"

[ -f "$DOC" ] && ok "the codebook exists at the declared path ($DOC)" \
              || { bad "the codebook is missing at the declared path ($DOC)"; exit 1; }

# --- 1. every declared term is defined, with a body -------------------------
while IFS= read -r t; do
  [ -z "$t" ] && continue
  body=$(awk -v t="## $t" '$0==t{f=1;next} /^## /{f=0} f' "$DOC" | tr -d '[:space:]')
  if [ -n "$body" ]; then
    ok "declared term '$t' has a definition the owner can read"
  else
    bad "declared term '$t' has NO definition in $DOC — a term meant to reach the owner is defined where the owner reads it"
  fi
done < "$TERMS_FILE"

# --- 2. no dead entry ------------------------------------------------------
# Redirected from a FILE, never piped: a pipeline runs the loop in a subshell,
# so `fail=1` would be set and then discarded — the check would print FAIL and
# still exit 0.
grep '^## ' "$DOC" | sed 's/^## //' > "$TMP"
while read -r entry; do
  [ -z "$entry" ] && continue
  if grep -Fxq "$entry" "$TERMS_FILE"; then
    ok "codebook entry '$entry' is declared first-class vocabulary"
  else
    bad "codebook entry '$entry' is declared nowhere — a definition for a term the surface never uses is drift"
  fi
done < "$TMP"

# --- 3. the surfaces are one step from the codebook ------------------------
# Screen 2's composed listing must carry the pointer, and the skill that
# presents Screen 1 must carry it too — Screen 1's own fields are budgeted, so
# the presenter is its carrier.
listing=$(python3 - "$DOC" <<'PYEOF'
import importlib.util as u, json, sys, tempfile
s = u.spec_from_file_location("m", "scripts/terrain_members.py")
m = u.module_from_spec(s); s.loader.exec_module(m)
md = {"kind": "topic-map", "topics": [], "coverage": {"pin": "h@abc1234"},
      "elements": [{"kind": "lesson", "slug": "l1", "title": "L1",
                    "tags": ["workflow"], "evidence": [], "consumed": False}]}
print(m.compose_member_listing(md, "workflow", m.candidates(md)))
PYEOF
)
case "$listing" in
  *"$DOC"*) ok "Screen 2's listing points at the codebook (one step from the surface)" ;;
  *) bad "Screen 2's listing carries no codebook pointer — the vocabulary is undecodable from the surface" ;;
esac

# Story 20.64 (#962): the pointer lives in the Step 2 companion the presenter
# reads on entry; assert over the dispatcher + step-companion family.
if cat skills/terrain/SKILL.md skills/terrain/steps/*.md | grep -q "$DOC"; then
  ok "the skill presenting Screen 1 carries the codebook pointer"
else
  bad "skills/terrain/SKILL.md carries no codebook pointer — Screen 1's fields are budgeted, so the presenter is its carrier"
fi

# --- 4. the pointer resolves ------------------------------------------------
# A pointer to a page that does not exist is worse than none: it reads as a
# definition the owner simply failed to find.
if [ -s "$DOC" ]; then ok "the codebook pointer resolves to a non-empty page"
else bad "the codebook pointer resolves to nothing"; fi

# --- 5. NEGATIVE TEST: the check must actually fail -------------------------
# A check nobody has seen fail is indistinguishable from one that cannot.
tmp=$(mktemp -d); cp "$DOC" "$tmp/doc.md"
python3 - "$tmp/doc.md" <<'PYEOF'
import re, sys
p = sys.argv[1]
t = open(p).read()
# strip the body of the first entry, leaving the heading
t = re.sub(r"(## brief\n).*?(?=\n## )", r"\1\n", t, flags=re.S)
open(p, "w").write(t)
PYEOF
if [ -z "$(awk -v t='## brief' '$0==t{f=1;next} /^## /{f=0} f' "$tmp/doc.md" | tr -d '[:space:]')" ]; then
  ok "negative test: a declared term stripped of its definition is detected as undefined"
else
  bad "negative test did NOT detect an undefined declared term — the check cannot fail"
fi
rm -rf "$tmp"

# --- 6. this check adds nothing to any denial list --------------------------
if grep -qE 'INTERNAL_VOCAB|FORBIDDEN_MARKERS' "$0"; then
  case "$(grep -cE 'INTERNAL_VOCAB|FORBIDDEN_MARKERS' "$0")" in
    *) grep -qE '^[[:space:]]*(INTERNAL_VOCAB|FORBIDDEN_MARKERS)=' "$0" \
         && bad "this check defines a denial list — the prohibited remedy shape" \
         || ok "this check names the denial lists only to disclaim them, never extends one" ;;
  esac
else
  ok "this check touches no denial list"
fi

[ $fail -eq 0 ] && echo "All owner-term codebook checks passed." \
                || echo "owner-term codebook checks FAILED." >&2
exit $fail
