#!/usr/bin/env sh
# parallel-safe
# parallel-verified 2026-08-01 (#1201) — every fixture is a `mktemp -d` unique
# to this process, the reader is invoked with --repo so it never resolves a
# machine-global config or a state root, and nothing outside those temp dirs is
# written. Two concurrent instances collide with nothing.
# tier: inner — a handful of sub-100ms python invocations over temp fixtures,
#   plus greps over tracked text; no seam, no pipeline run
# covers: scripts/style-contract.py skills/draft-article/**
# grep-binding: token — the skill grep matches the 'style-contract.md'
#   filename token, not relocatable prose.
# removal-signal: retire this when the style contract stops being an artifact
#   this plugin reads — i.e. when either the contract is withdrawn, or its
#   consumption moves behind a mechanism that carries these properties itself
#   (one artifact, a version field, an uninstrumented syntax profile, no
#   writer). A drift check landing at corpus level does NOT retire it: that
#   instrument would measure the corpus, not these invariants.
#
# check-style-contract.sh — the ONE versioned style contract, consumed at
# GENERATION (Story 20.139, #1201; SPEC-writing-assistant, the 2026-08-01
# #1191 amendment).
#
# WHAT THIS ASSERTS, AND WHY EACH ONE IS MECHANICAL RATHER THAN PROSE:
#   1. exactly one artifact, one reader, one declaration of its section set —
#      a second copy of an enumeration goes stale silently (#1193);
#   2. the version field is REQUIRED — an unversioned file cannot be a
#      versioned contract, so its absence is a refusal, not a warning;
#   3. the SYNTAX PROFILE carries NO INSTRUMENT. This is the criterion most
#      likely to be "satisfied" by adding a metric, which is why it is checked
#      from two sides: the reader emits no measurement, and the contract's own
#      carrier line for that section reads `none`. A change that adds a syntax
#      metric FAILS here — that is the point of the section existing;
#   4. the exemplar slots are declared, keyed, and EMPTY — an invented exemplar
#      is the failure the declared-empty shape exists to prevent;
#   5. NO WRITER exists. The prohibition is carried by there being nothing that
#      can write the artifact, never by a rule someone must remember — the
#      shape check-journey-writer-absent.sh and check-footprint-invariant.sh
#      already use;
#   6. consumption is at GENERATION: the drafting skill reads it. (Review-side
#      measurement is a separate story and is deliberately NOT asserted about
#      here, in either direction.)
#
# THE CORPUS-LEVEL DRIFT CHECK IS NOT BUILT AND IS NOT ASSERTED HERE. It is
# HELD — the corpus is approximately zero published articles, so the instrument
# could not run if built — and its trigger is recorded at the reader:
# THE OWNER READS TWO SHIPPED ARTICLES AS WRITTEN BY DIFFERENT PEOPLE.
#
# POSIX shell + stdlib Python only, like every check-*.sh sibling.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

READER="scripts/style-contract.py"
COMPANION="skills/draft-article/style-contract.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

fx=$(mktemp -d)
trap 'rm -rf "$fx"' EXIT

# --- 0. the reader exists and compiles ---------------------------------------
if python3 -c "import py_compile; py_compile.compile('$root/$READER', doraise=True)" 2>/dev/null; then
  ok "the style-contract reader compiles"
else
  err "$READER is missing or does not compile"; printf '\nChecks FAILED.\n' >&2; exit 1
fi

# --- 1. ONE artifact, ONE reader, ONE declaration of the section set ---------
n=$(grep -rl "^CARRIERS = {" scripts/*.py | wc -l | tr -d ' ')
if [ "$n" = "1" ]; then
  ok "the contract's section set is declared exactly once ($READER)"
else
  err "the section set is declared in $n files — one enumeration, one home (#1193)"
fi
# No other SCRIPT composes the artifact path: a second reader is a second
# contract in waiting. (Skill prose may point at the companion file of the same
# name — a pointer is not a reader, which is why this is scoped to scripts/.)
others=$(grep -ln 'style-contract\.md' scripts/*.py 2>/dev/null | grep -v "^$READER$" || true)
if [ -z "$others" ]; then
  ok "no second reader: only $READER composes the artifact path"
else
  err "another script names the artifact — one artifact, one reader: $(echo "$others" | tr '\n' ' ')"
fi

# --- 2. the canonical format round-trips, and it is VERSIONED ----------------
python3 "$READER" format > "$fx/style-contract.md"
if grep -q '^style_contract_version:' "$fx/style-contract.md"; then
  ok "the record format carries an explicit version field"
else
  err "the record format declares no version field"
fi
if python3 "$READER" read --repo "$fx" --json > "$fx/payload.json" 2>/dev/null; then
  ok "the emitted format parses clean through the reader (round trip)"
else
  err "the reader refuses its own emitted format"
fi

# --- 3. carriers, the UNINSTRUMENTED syntax profile, and the empty slots -----
# One python invocation carries every payload assertion plus the code probe:
# process spawns are what an inner-tier check pays for, and each assertion
# still reports its own line. The code probe strips comments and string
# literals before matching, because the prose explaining why there is no
# instrument names every term an instrument would use — a grep that cannot
# tell the explanation from the implementation would force the explanation out
# of the file.
if python3 - "$fx/payload.json" "$READER" <<'PY'
import io, json, re, sys, tokenize

d = json.load(open(sys.argv[1]))
sec = d.get("sections", {})
ex = d.get("exemplars", {})
slots = ex.get("slots", {})
blob = json.dumps(d)

code = "".join(
    t.string for t in tokenize.generate_tokens(
        io.StringIO(open(sys.argv[2], encoding="utf-8").read()).readline)
    if t.type not in (tokenize.COMMENT, tokenize.STRING))
metric = re.findall(
    r"sentence_length|hedg\w*|word_count|avg_\w*|mean\(|density|_score|/ *len\(", code)

def carrier(name, kind):
    return sec.get(name, {}).get("carrier_kind") == kind

checks = [
    (d.get("status") == "present" and bool(d.get("version")),
     "the read contract reports its version"),
    (set(sec) == {"REGISTER", "STRUCTURAL VOICE", "LEXICON", "FIGURES", "SYNTAX PROFILE"},
     "the four carrier-labelled sections plus the syntax profile are all present"),
    (carrier("REGISTER", "judgment") and carrier("STRUCTURAL VOICE", "judgment"),
     "register and structural voice are labelled JUDGMENT (the Reviewer's one dimension)"),
    (carrier("LEXICON", "mechanical"),
     "lexicon is labelled MECHANICAL (the existing coinage lint)"),
    (carrier("FIGURES", "ratified-elsewhere"),
     "figures is a pointer to the already-ratified visual identity, not a restatement"),
    (carrier("SYNTAX PROFILE", "none")
     and sec["SYNTAX PROFILE"]["carrier"].lower().startswith("none"),
     "the syntax profile declares carrier NONE - deliberately uninstrumented"),
    (d.get("measured") == [] and d.get("uninstrumented_by_contract") == ["SYNTAX PROFILE"],
     "the reader measures nothing and says so in its payload"),
    (not metric,
     "no syntax metric in the reader's code - sentence length, hedging density, "
     "person/voice measured by nothing (a metric here FAILS the contract, #1191)"
     + (" -- computed: %s" % ", ".join(sorted(set(metric))) if metric else "")),
    (not [k for k in ("length", "density", "score", "ratio", "count", "average")
          if re.search(r'"[a-z_]*%s[a-z_]*":' % k, blob)],
     "the payload carries no measurement field for a downstream gate to enforce"),
    (bool(ex.get("lookup_key")) and set(slots) == {"register", "structural-voice"},
     "exemplar slots are declared with the key they are looked up by"),
    (all(v == [] for v in slots.values()),
     "every exemplar slot ships EMPTY - no exemplar is invented (none exists to pin)"),
]
bad = 0
for good, msg in checks:
    print(("ok:   " if good else "FAIL: ") + msg)
    bad += 0 if good else 1
sys.exit(1 if bad else 0)
PY
then :; else fail=1; fi

# --- 5. refusals: no version, wrong carrier ----------------------------------
grep -v '^style_contract_version:' "$fx/style-contract.md" > "$fx/nover.md"
cp "$fx/nover.md" "$fx/style-contract.md"
if python3 "$READER" read --repo "$fx" >/dev/null 2>"$fx/err.txt"; then
  err "an unversioned file is accepted as a versioned contract"
else
  rc=$?
  if [ "$rc" = "4" ] && grep -q 'style_contract_version' "$fx/err.txt"; then
    ok "an unversioned file is refused (exit 4), naming the missing version field"
  else
    err "an unversioned file must be refused with exit 4 naming the field (got $rc)"
  fi
fi
python3 "$READER" format | sed 's/^carrier: none — deliberately\./carrier: mechanical — a sentence-length check./' > "$fx/style-contract.md"
if python3 "$READER" read --repo "$fx" >/dev/null 2>"$fx/err2.txt"; then
  err "a contract instrumenting the syntax profile is accepted"
else
  ok "a contract that gives the syntax profile a carrier is refused, naming the section"
fi

# --- 6. ABSENCE is stated, and the reader creates nothing ---------------------
rm -f "$fx/style-contract.md"
before=$(ls -A "$fx" | sort | tr '\n' ' ')
if out=$(python3 "$READER" read --repo "$fx" 2>&1); then
  case "$out" in
    *"no style contract at"*"proceeds WITHOUT one"*"does not create it"*)
      ok "an absent contract is exit 0, stated verbatim, and the run proceeds" ;;
    *) err "the absence line must state that generation proceeds and that the plugin does not create the file" ;;
  esac
else
  err "an absent contract must exit 0 — absence is a fact about the destination, not an error"
fi
after=$(ls -A "$fx" | sort | tr '\n' ' ')
if [ "$before" = "$after" ]; then
  ok "reading an absent contract wrote nothing into the destination"
else
  err "the read created files in the destination — the plugin's only interaction is a READ"
fi

# --- 7. NO WRITER — the prohibition is carried by absence, not by prose -------
# This file is excluded: its own `format >` redirects build the temp FIXTURES
# the assertions above run against, in a mktemp dir that is not a destination.
if grep -rnE '(open\([^)]*style.contract[^)]*,[[:space:]]*["'"'"']?[wa]|>>?[[:space:]]*[^ ]*style-contract\.md|write_text\([^)]*style.contract|makedirs\([^)]*style.contract)' \
     scripts skills 2>/dev/null | grep -v '^scripts/check-style-contract.sh:'; then
  err "a code path writes the style contract — the artifact is owner-authored and read-only here (#1201)"
else
  ok "no code path opens, appends to, or redirects into the style contract"
fi
if grep -rniE '(write|create|generate|scaffold|offer to (add|write))[^.]{0,50}style contract' skills 2>/dev/null \
   | grep -viE 'never (write|create)|does not create|no (writer|setup-offers)|read-only'; then
  err "a skill instructs writing or offering to create the style contract (#1201)"
else
  ok "no skill instructs a write, a setup offer, or a config-writer path for it"
fi

# --- 8. consumed AT GENERATION ------------------------------------------------
if [ -f "$COMPANION" ] && grep -q 'style-contract.py read' "$COMPANION"; then
  ok "the drafting skill reads the contract at generation"
else
  err "$COMPANION must carry the generation-time read (style-contract.py read)"
fi
if grep -q 'style-contract.md' skills/draft-article/SKILL.md; then
  ok "the draft dispatcher routes stage 3 through the style-contract companion"
else
  err "the draft dispatcher does not route the fill stage through the companion"
fi
flat=$(tr '\n' ' ' < "$COMPANION" | tr -s ' ')
case "$flat" in
  *"never asks the owner a style question"*"never proposes a per-run style"*)
    ok "the companion states the lifetime: read once at generation, never a per-run ask" ;;
  *) err "the companion must state that the contract is read at generation and is not a per-run decision" ;;
esac

# --- 9. the HELD drift check and its trigger are recorded --------------------
if grep -qi 'two shipped articles as written by different people' "$READER"; then
  ok "the corpus drift check is recorded as HELD with its observable trigger"
else
  err "the held corpus-level drift check and its trigger must be recorded at the reader (#1191)"
fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll style-contract checks passed.\n'; exit 0
else
  printf '\nstyle-contract checks FAILED.\n' >&2; exit 1
fi
