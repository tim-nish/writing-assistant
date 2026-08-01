#!/usr/bin/env sh
# parallel-safe
# tier: inner
# covers: scripts/pin-source.py scripts/validate-fact-sheet.py
# removal-signal: every consumer of the KIND set imports it from one module
#   (no file re-declares the nine kinds as a literal), at which point divergence
#   is unrepresentable and there is nothing left for this check to compare.
# check-kind-lockstep.sh — the closed nine-KIND set has ONE authority, and the
# emitter cannot fall behind it (Story 20.112, #1120).
#
# WHY A CHECK AND NOT JUST THE FIX. The #438 amendment names its enforcement
# copies as `validate-fact-sheet.py` and `skills/harvest/SKILL.md §3` — and
# `pin-source.py` was a THIRD copy nobody had named, so when the four narrative
# kinds landed it kept its five-tuple and `--emit-entry` silently could not emit
# them. Nothing failed; the harvest simply routed 88 of 157 entries around "the
# only sanctioned construction path". A named-copy list cannot catch the copy it
# does not name, so what is asserted here is the ABSENCE of an unnamed copy.
set -u
cd "$(dirname "$0")/.."
fail=0
ok()  { printf 'ok:   %s\n' "$1"; }
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

report=$(python3 - <<'PY'
import importlib.util, os, re, sys
sys.path.insert(0, "scripts")


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


vfs = load("vfs", "scripts/validate-fact-sheet.py")
ps = load("ps", "scripts/pin-source.py")
src = open("scripts/pin-source.py", encoding="utf-8").read()

bad = []


def need(cond, msg):
    if not cond:
        bad.append(msg)


# 1. The authority is nine, and the emitter agrees with it exactly.
need(len(vfs.KINDS) == 9,
     "validate-fact-sheet.py's KIND set is %d, not nine — the closed set is "
     "nine (pipeline-stages.md:151, #438); widening it is a spec decision, "
     "never an in-place edit" % len(vfs.KINDS))
need(set(ps.KINDS) == set(vfs.KINDS),
     "pin-source.py and validate-fact-sheet.py disagree on KINDS: "
     "emitter-only=%s validator-only=%s"
     % (sorted(set(ps.KINDS) - set(vfs.KINDS)),
        sorted(set(vfs.KINDS) - set(ps.KINDS))))
ps_span = getattr(ps, "SPAN_ELIGIBLE", None)
need(ps_span is not None,
     "pin-source.py declares no SPAN_ELIGIBLE at all, so its accepted pointer "
     "forms are decided somewhere the validator cannot be compared against — "
     "source it from validate-fact-sheet.py")
need(ps_span is None or set(ps_span) == set(vfs.SPAN_ELIGIBLE),
     "SPAN_ELIGIBLE disagrees between emitter and validator — the "
     "kind/pointer-form rules and the emitter's accepted forms must not "
     "diverge (this rejected 54 entries on the 2026-08-01 run)")

# 2. The narrative kinds are reachable through --emit-entry's own argument
#    surface. Set equality is necessary, not sufficient: the CLI could still
#    restrict `--kind` independently of the module constant.
m = re.search(r'--kind",\s*choices=([A-Za-z_]+)', src)
need(m is not None and m.group(1) == "KINDS",
     "--kind's choices are not the module KINDS tuple — a second restriction "
     "on the emitter's surface reintroduces the gap set equality hides")
narrative = {"chronology", "motivation", "cost", "reversal"}
need(narrative <= set(ps.KINDS),
     "the narrative kinds are not all emittable via --emit-entry: missing %s"
     % sorted(narrative - set(ps.KINDS)))

# 3. THE ABSENCE OF AN UNNAMED COPY — the actual #1120 defect. Any script
#    re-declaring the five atomic kinds as a literal is a fourth copy waiting
#    to fall behind. The validator IS the authority and may state the set.
literal = re.compile(r'["\']result["\']\s*,\s*["\']decision["\']\s*,\s*'
                     r'["\']number["\']\s*,\s*["\']quote["\']\s*,\s*["\']event["\']')
offenders = []
for fn in sorted(os.listdir("scripts")):
    if not fn.endswith(".py") or fn == "validate-fact-sheet.py":
        continue
    text = open(os.path.join("scripts", fn), encoding="utf-8").read()
    mm = literal.search(text)
    if mm:
        offenders.append("scripts/%s:%d" % (fn, text[:mm.start()].count("\n") + 1))
need(not offenders,
     "the KIND set is re-declared as a literal outside the authority at %s — "
     "import it from validate-fact-sheet.py; an unnamed copy is exactly what "
     "#1120 was" % ", ".join(offenders))

print("\n".join(bad))
PY
) || { err "kind-lockstep harness did not run"; printf '\nFAILED.\n' >&2; exit 1; }

if [ -z "$report" ]; then
  ok "the nine-KIND set has one authority; emitter and validator agree"
  ok "the four narrative kinds are emittable through --emit-entry"
  ok "span-pointer eligibility is sourced, not re-stated"
  ok "no unnamed copy of the KIND set under scripts/"
  printf '\nOK: KIND set in lockstep.\n'
else
  printf '%s\n' "$report" | while IFS= read -r line; do
    [ -n "$line" ] && printf 'FAIL: %s (#1120)\n' "$line" >&2
  done
  printf '\nkind-lockstep checks FAILED.\n' >&2
  exit 1
fi
exit 0
