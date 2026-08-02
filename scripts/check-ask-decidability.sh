#!/bin/sh
# check-ask-decidability.sh — an owner ask is DECIDABLE by its recipient
# (Story 20.152, #1222).
#
# tier: inner
# parallel-safe
# covers: scripts/validate-proposal-payload.py scripts/draft_gates.py
# removal-signal: retires when a shipped instrument measures owner decision
#   quality directly — an answered-then-reversed rate, say — because that
#   measures the property this only proxies. It does NOT retire because it
#   passes: the defect it guards was invisible to every shipped check while a
#   run was being abandoned over it.
#
# WHY A THIRD AXIS. `SPEC.md:76` binds an ask's FORM, `:79` its PREMISES, `:80`
# its REGISTER. None tests whether the recipient can DECIDE. On 2026-08-02 a
# run was abandoned at Stage 3 after the owner answered gate after gate by
# picking the first option — "I selected the first option because the question
# was incomprehensible" — while every check passed. The consequence is not
# cosmetic: `answers.json` then carried an editorial anchor, a falsifier and a
# depth decision that encode escape-clicks, and Stage 3 consumed them as
# authoritative. A gate that collects a selection without giving a basis to
# decide produces records worse than no record.
#
# THE MECHANICAL/JUDGMENT SPLIT IS THE DESIGN, taken from `SPEC.md:80`'s own
# discriminator. Two of #1222's five obligations are mechanical facts and are
# DENIED by the validator; three require reading intent and are REPORTED for a
# gate where a human is present, because that clause forbids a judgment check
# becoming an automated blocking member. This file asserts the split holds —
# that the deniable ones deny, and that the judgment ones are still surfaced
# rather than quietly dropped.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fail=0
ok()  { printf 'ok:   %s\n' "$1"; }
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

run() { (cd "$ROOT" && python3 - "$@"); }

# --- 1. the observed defect shape is DENIED ------------------------------
if run <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("v", "scripts/validate-proposal-payload.py")
v = importlib.util.module_from_spec(s); s.loader.exec_module(v)
bad = {"items": [{
    "where": "Next is Stage 3 — fill.",
    "why": "Stage 3 will run now.",
    "choices": [{"label": "continue into stage 3", "effect": "runs fill"},
                {"label": "stop here", "effect": "keeps the run"}],
    "render": {"control": "selection", "recommended": None}}]}
errs = [p for p, _ in v.validate(bad)]
# The stage name must be caught in where, why AND the label.
need = {"item[0].where", "item[0].why", "item[0].choices[0].label",
        "item[0].render.recommended"}
sys.exit(0 if need <= set(errs) else 1)
PY
then
  ok "the observed shape is denied — stage names in where/why/label, and a
      multi-option ask with no recommendation"
else
  err "the 2026-08-02 defect shape passed validation"
fi

# --- 2. the denied form is the NUMBER, and the registry carries none ------
# Obligation 5 used to deny whatever strings `draft_gates.GATES` happened to
# carry, which was right while the registry said "stage 2". Since the owner
# ruling of 2026-08-02 (#1247) the registry names PROCESSES, so that
# derivation would now deny a gate the right to say which process it belongs
# to — the thing the ruling REQUIRES an ask to say, and the probe-entry gate's
# own shipped label ("run probe now") would have become a defect. Asserted
# both ways: the numbered family is denied by SHAPE wherever it appears, and
# no declared process name is a numbered form — the registry-side carrier for
# "the prohibited form has no source to leak from".
if run <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("v", "scripts/validate-proposal-payload.py")
v = importlib.util.module_from_spec(s); s.loader.exec_module(v)
d = importlib.util.spec_from_file_location("dg", "scripts/draft_gates.py")
dg = importlib.util.module_from_spec(d); d.loader.exec_module(dg)
declared = {str(x.get("stage") or "").strip().lower()
            for x in dg.GATES.values()} - {""}
bad = sorted(n for n in declared if v.numbered_stage_forms(n))
if bad:
    print("  registry stage values carrying a stage NUMBER: %s" % bad)
    sys.exit(1)
# Matched by shape, not by an enumeration, so a spelling nobody listed fails too.
for form in ("Stage 3", "stage 3", "stage3", "STAGE 0", "stage  5"):
    if not v.numbered_stage_forms("next is %s now" % form):
        print("  the numbered form %r is not denied" % form)
        sys.exit(1)
# And a process name is NOT denied — the inversion this check exists to catch.
if any(v.numbered_stage_forms(n) for n in declared):
    sys.exit(1)
sys.exit(0)
PY
then
  ok "the denied family is the NUMBERED form, matched by shape; no registry
      stage value carries a number, so the prohibited form has no source"
else
  err "either a numbered form is not denied, or the registry still carries one"
fi

# --- 3. a declared absence is accepted, an undeclared one is not ---------
if run <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("v", "scripts/validate-proposal-payload.py")
v = importlib.util.module_from_spec(s); s.loader.exec_module(v)
base = {"where": "Pick the shape the draft is written in.",
        "why": "Five shapes are on offer and they differ in what they emphasise.",
        "choices": [{"label": "a", "effect": "writes shape a"},
                    {"label": "b", "effect": "writes shape b"}],
        "render": {"control": "selection", "recommended": None}}
undeclared = [p for p, _ in v.validate({"items": [dict(base)]})]
declared = [p for p, _ in v.validate(
    {"items": [dict(base, no_recommendation="the choice is the owner's intent")]})]
sys.exit(0 if ("item[0].render.recommended" in undeclared
               and "item[0].render.recommended" not in declared) else 1)
PY
then
  ok "an undeclared missing recommendation is denied; a DECLARED one is
      accepted — an empty field and a considered 'I cannot rank these' are
      otherwise indistinguishable"
else
  err "no_recommendation does not discharge the recommendation obligation"
fi

# --- 4. the judgment obligations are still SURFACED ----------------------
if run <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("v", "scripts/validate-proposal-payload.py")
v = importlib.util.module_from_spec(s); s.loader.exec_module(v)
reports = v.decidability_reports({"items": [{
    "where": "Pick a telling.", "why": "A corpus read is available.",
    "choices": [{"label": "a", "effect": "x"}]}]})
# Obligations 1 and 4 must be named for the reader on every item; they cannot
# be decided mechanically and must not therefore vanish.
sys.exit(0 if any("obligations 1 and 4" in r for _, r in reports) else 1)
PY
then
  ok "the judgment obligations are reported, not dropped — a check that cannot
      decide them must still say they are owed"
else
  err "obligations 1/2/4 are neither denied nor reported — silently dropped"
fi

# --- 5. every SHIPPED gate satisfies the deniable half -------------------
if run <<'PY'
import importlib.util, sys
s = importlib.util.spec_from_file_location("v", "scripts/validate-proposal-payload.py")
v = importlib.util.module_from_spec(s); s.loader.exec_module(v)
d = importlib.util.spec_from_file_location("dg", "scripts/draft_gates.py")
dg = importlib.util.module_from_spec(d); d.loader.exec_module(dg)
labels = {"introduce the project": "a", "share engineering lessons": "b",
          "explain the evaluation methodology": "c",
          "survey a research area": "d", "write a working note": "e"}
bad = []
for name, p in (("probe_entry_gate", dg.probe_entry_gate(3)),
                ("intent_gate", dg.intent_gate(labels))):
    for path, reason in v.validate(p):
        bad.append(f"{name}: {path} — {reason}")
if bad:
    print("\n".join(bad), file=sys.stderr)
sys.exit(1 if bad else 0)
PY
then
  ok "every shipped gate builder satisfies the deniable obligations"
else
  err "a shipped gate fails the decidability axis (see above)"
fi

[ "$fail" -eq 0 ] || { echo; echo "ask-decidability checks FAILED."; exit 1; }
echo
echo "ask-decidability checks passed."
