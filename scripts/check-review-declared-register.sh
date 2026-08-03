#!/usr/bin/env sh
# tier: inner — greps over the review skill, its prompts companion, and the
#   quality rubric; no network, no repo mutation.
# measured: 100ms (three runs, 2026-08-04, all 100ms)
# ends: a LANGUAGE-SCOPED criterion entering the shared quality rubric, which
#   also gates the EN draft Stage 3->4 path — turning a Japanese defect into an
#   English gate (Story 20.4's property). NOT generation-side preventable: the
#   rubric is a hand-authored versioned asset and nothing at its writing point
#   knows which language paths consume it.
# removal-signal: the EN and JA gates stopping sharing one rubric asset, at
#   which point extending either cannot reach the other.
#
# Headers owed because the file LEFT the admission baseline when edited
# (#1356): the edit re-based 20.4's guard from its version pin onto its
# property (#1412).
# parallel-safe
# covers: config/language-conventions.yaml scripts/resolve-user-config.py skills/draft-article/quality-rubric.md skills/review-article/SKILL.md skills/review-article/phases/arbitration.md skills/review-article/phases/entry.md skills/review-article/phases/passes.md skills/review-article/phases/reentry.md skills/review-article/review-prompts.md specs/spec-article-review/SPEC.md specs/spec-canonical-adaptation/SPEC.md
# check-review-declared-register.sh — the review pass grades a derived
# canonical against the register its language DECLARES (Story 20.4, #800).
#
# The defect this guards is an asymmetry, not a missing feature: the target
# language's conventions were already declared and already authoritative for
# GENERATION (scripts/adapt-canonical.py reads them to decide how to write),
# and were read only on the way in. Structure passed while register failed,
# and nothing in the review contract was violated — a vacuously passing floor.
# SPEC-canonical-adaptation CAP-4 now names the criterion; this check asserts
# the shipped surface actually carries it.
#
# Scope discipline is the load-bearing half: the criterion is artifact-class
# scoped (derived canonicals only). SPEC-article-review keeps a deliberately
# CLOSED blocker-criterion set, and this opens it by exactly one class — so
# the check asserts the scoping too, not merely the presence.
#
# POSIX shell + coreutils only, like every check-*.sh sibling.

set -eu

PROMPTS="skills/review-article/review-prompts.md"
SKILL=$(mktemp)
cat skills/review-article/SKILL.md skills/review-article/phases/entry.md \
    skills/review-article/phases/passes.md skills/review-article/phases/arbitration.md \
    skills/review-article/phases/reentry.md > "$SKILL"
# ^ story 20.13 (#818): the skill is now a dispatcher + phase companions; checks
#   assert over the concatenation, whose order matches the pre-split file.
RUBRIC="skills/draft-article/quality-rubric.md"
CONV="config/language-conventions.yaml"
SPEC_REVIEW="specs/spec-article-review/SPEC.md"
SPEC_ADAPT="specs/spec-canonical-adaptation/SPEC.md"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

for f in "$PROMPTS" "$SKILL" "$RUBRIC" "$CONV" "$SPEC_REVIEW" "$SPEC_ADAPT"; do
  [ -f "$f" ] || { err "missing $f — wrong root?"; }
done
[ "$fail" -eq 0 ] || { printf '\ndeclared-register checks FAILED.\n' >&2; exit 1; }

# --- 1. the criterion exists, and is scoped to derived canonicals ------------

if grep -q 'Declared-convention conformance' "$PROMPTS"; then
  ok "review-prompts declares the declared-convention criterion"
else
  err "review-prompts declares no declared-convention criterion (Story 20.4)"
fi

if grep -q 'adapted_from' "$PROMPTS"; then
  ok "the criterion names its discriminator (adapted_from)"
else
  err "the criterion does not name adapted_from — an unscoped criterion would"\
" fire on authored EN canonicals, which SPEC-article-review forbids"
fi

# The severity table must admit it as blocker-eligible AND say derived-only in
# the same row; a blocker row that admits it without the scope is the exact
# widening the spec refuses.
row=$(grep -n '^| \*\*blocker\*\*' "$PROMPTS" | head -1 | cut -d: -f1)
if [ -n "$row" ]; then
  line=$(sed -n "${row}p" "$PROMPTS")
  case "$line" in
    *declared-convention*) ;;
    *) err "the blocker severity row does not admit the declared-convention criterion" ;;
  esac
  case "$line" in
    *"derived canonical"*) ok "the blocker row admits the criterion AS derived-canonical-scoped" ;;
    *) err "the blocker row admits the criterion WITHOUT its derived-canonical scope" ;;
  esac
else
  err "no blocker severity row found in $PROMPTS"
fi

# --- 2. undeclared language is skipped and DISCLOSED, never a defect ---------
# Precedent: #701's title claim-verb test. A check that cannot judge a whole
# artifact class must not report on it.

if grep -qi 'skip' "$PROMPTS" && grep -qi 'disclos' "$PROMPTS"; then
  ok "an undeclared language is skipped WITH the skip disclosed"
else
  err "no skip-and-disclose rule for a language with no declaration (#701 precedent)"
fi

# --- 3. the skill's prose pass routes to it (pointer, not copy) --------------

if grep -q 'Declared-convention conformance' "$SKILL"; then
  ok "the prose pass carries the declared-convention item"
else
  err "$SKILL prose pass does not mention declared-convention conformance"
fi

if grep -q 'review-prompts.md' "$SKILL"; then
  ok "the skill POINTS at the full contract rather than restating it"
else
  err "the skill does not point at review-prompts.md for the contract"
fi

# --- 4. no LANGUAGE-SCOPED criterion becomes an always-firing dimension ------
# Story 20.4's chosen alternative was "no fifth dimension", and it was pinned
# here as `rubric-version == 1` plus the literal "Four dimensions". Those are
# PROXIES for a moment, not the decision: re-based 2026-08-04 (#1412) onto the
# property 20.4 was actually about — the rubric ALSO gates the EN draft Stage
# 3->4 path, so a Japanese-specific criterion added to it would turn a Japanese
# defect into an English gate.
#
# The served position is the one that settles it: scope a trigger to the
# PROPERTY being claimed about rather than to the assertion, and a count
# survives as the OCCASION to check the property, never as the trigger
# *(owner decision record — 2026-08-01 (a trigger is scoped to the property,
# not to the count))*.
#
# #1412's dim5 does not violate the property and is why the re-base happened:
# it is CONDITIONAL — a run whose Brief carries no plain-register commitment
# emits `dim5: n/a` and passes — so an EN draft with no commitment is
# unaffected, which is exactly what a naturalness dimension could never have
# been. The naturalness ban below is therefore UNCHANGED and still verbatim.

if grep -qiE '^## Dimension [0-9]+ —.*(japanese|語|naturalness)' "$RUBRIC"; then
  err "a LANGUAGE-SCOPED dimension entered the rubric — it gates the EN draft"\
" Stage 3->4 path too, so this turns a Japanese defect into an English gate"\
" (Story 20.4's property, re-based #1412)"
else
  ok "no language-scoped dimension in the rubric (20.4's property, not its version pin)"
fi

# Any dimension beyond 20.4's four must state how it behaves where its subject
# is absent — the conditional discipline that keeps the EN path unaffected.
if [ "$(grep -cE '^## Dimension [0-9]' "$RUBRIC")" -gt 4 ]; then
  grep -qi 'n/a' "$RUBRIC" \
    && ok "a dimension beyond the original four declares its absent-subject behaviour (n/a), so the EN path stays unaffected" \
    || err "the rubric grew past four dimensions with no n/a clause — an"\
" unconditional new dimension gates every draft, which is what 20.4 refused"
fi

if grep -qi 'natural' "$RUBRIC"; then
  err "naturalness leaked into the quality rubric — it is a sibling criterion,"\
" not a fifth dimension (EN drafts and the Stage 3->4 gate must be unaffected)"
else
  ok "naturalness did NOT leak into the rubric (EN behavior unchanged)"
fi

# --- 5. the declaration the criterion grades against actually exists ---------
# Reuses the repo's own stdlib YAML subset reader, exactly as
# check-lint-article.sh does — a declaration is only a declaration if the
# shipped parser reads it whole (#701).

if python3 - "$CONV" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ruc", "scripts/resolve-user-config.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
langs = (m.load_yaml(open(sys.argv[1], encoding="utf-8").read()) or {}).get("languages") or {}
ja = langs.get("ja") or {}
missing = [k for k in ("register", "terminology") if not ja.get(k)]
if missing:
    print("ja lost: " + ", ".join(missing)); sys.exit(1)
sys.exit(0)
PY
then
  ok "ja declares both register and terminology (the criterion has a target)"
else
  err "the ja block does not declare register+terminology — the criterion"\
" would grade against nothing"
fi

# --- 6. both specs carry the decision ----------------------------------------

if grep -q 'declared-convention violation' "$SPEC_REVIEW"; then
  ok "SPEC-article-review's severity anchor names the fourth criterion"
else
  err "SPEC-article-review does not name the declared-convention criterion"
fi

if grep -q 'language half is graded' "$SPEC_ADAPT"; then
  ok "SPEC-canonical-adaptation CAP-4 grades the language half"
else
  err "SPEC-canonical-adaptation CAP-4 does not state that the language half is graded"
fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll declared-register checks passed.\n'; exit 0
else
  printf '\ndeclared-register checks FAILED.\n' >&2; exit 1
fi
