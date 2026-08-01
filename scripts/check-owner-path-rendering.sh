#!/usr/bin/env sh
# parallel-safe
# tier: inner
# covers: scripts/owner_surface.py scripts/terrain_text.py scripts/terrain_members.py
# removal-signal: every owner-facing string (not only paths) is composed
#   through the typed seam SPEC-writing-assistant §Owner-surface register
#   describes, at which point an inline path is unrepresentable and the
#   detector below has no shape left to catch.
# check-owner-path-rendering.sh — an owner-facing ARTIFACT path renders whole,
# on its own line, never inline in a sentence (Story 20.115, #1117).
#
# WHY THE DETECTOR IS NOT THE REMEDY. §Owner-surface register(a) prohibits an
# enumerated denial list as the RESPONSE to a leak — "a denial list's
# non-member fallback is ADMIT, so the defect is in the shape rather than in
# any list's contents" — and orders the remedy CONSTRAIN -> DETECT -> ENUMERATE.
# The constraint is `scripts/owner_surface.py`; this is the fast path beneath
# it, per (b), where the enumerated form is demoted rather than deleted.
#
# It decides a SHAPE and reads no intent, so under the mechanical-vs-judgment
# discriminator it is an ordinary check and needs no special siting.
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


osx = load("owner_surface", "scripts/owner_surface.py")
tt = load("terrain_text", "scripts/terrain_text.py")

bad = []


def need(cond, msg):
    if not cond:
        bad.append(msg)


LONG = ("/home/someone/.local/state/writing-assistant/"
        "-home-someone-work-repo/terrain-runs/20260801T091400-250105/brief.json")

# 1. THE SEAM RENDERS A BLOCK. The path occupies a line by itself — nothing
#    before it, nothing after it — which is the form that survives wrapping.
block = osx.artifact_block("Brief artifact", LONG, note="Say `open the brief`.")
lines = block.split("\n")
need(LONG in lines,
     "artifact_block does not put the path alone on its own line — it is the "
     "placement, not the length, that a wrap or an elision acts on (#1117)")
need(not any(LONG in ln and ln.strip() != LONG for ln in lines),
     "artifact_block leaves text on the path's line")
need(not osx.is_elided(block), "artifact_block emitted an elided path")

# 2. THE TWO SURFACES THE 2026-08-01 RUN LEAKED ON go through it.
brief = tt._brief_artifact_line(LONG)
need(LONG in brief.split("\n"),
     "the brief artifact line renders its path inline in a sentence — this is "
     "the line the owner reported as truncated, which made the sitting's "
     "central artifact uninspectable (#1117)")
need(not osx.is_elided(brief), "the brief artifact line emitted an elided path")

src = open("scripts/terrain_members.py", encoding="utf-8").read()
need("artifact_block(" in src,
     "Screen 2's View pointer does not go through the owner-surface seam — "
     "rendering it WHOLE (#1073) was necessary and not sufficient; it still "
     "sat inline between two clauses (#1117)")
need(not re.search(r'file: \{view_path\}', src),
     "terrain_members.py still interpolates view_path into a sentence")

# 3. THE DETECTOR DISCRIMINATES. A rule that fires on prose would be turned
#    off, and a rule that misses `…/` is the one that let #1073 reopen.
need(osx.is_elided("artifact: …/terrain-runs/x/brief.json"),
     "is_elided misses a leading-ellipsis path — the exact shape the terrain "
     "completion summary emitted on 2026-08-01")
need(osx.is_elided("…/.writing-assistant/-home-tomoya-work-writing-assistant/te"),
     "is_elided misses the mid-path cut Screen 2's pointer arrived with")
need(not osx.is_elided("the complete rendering — every Strand… is in the View"),
     "is_elided fires on ordinary prose, which would get the check disabled")
need(not osx.is_elided("Brief artifact:\n%s" % LONG),
     "is_elided fires on a correctly rendered block")

# 4. THE TYPE IS THE CONSTRAINT, not a helper anyone may bypass silently.
need(issubclass(osx.ArtifactPath, str),
     "ArtifactPath is not a str subclass, so it cannot be passed where a path "
     "is expected and the seam becomes opt-in")
need(hasattr(osx.ArtifactPath, "bare"),
     "ArtifactPath has no conspicuously named escape hatch — an unnamed one "
     "is indistinguishable from an accident at review")

print("\n".join(bad))
PY
) || { err "owner-path-rendering harness did not run"; printf '\nFAILED.\n' >&2; exit 1; }

if [ -z "$report" ]; then
  ok "artifact paths render whole, alone on their line"
  ok "the brief artifact line and Screen 2's View pointer go through the seam"
  ok "the detector catches path cuts and spares prose"
  ok "ArtifactPath constrains rather than advises"
  printf '\nOK: owner-facing artifact paths are openable.\n'
else
  printf '%s\n' "$report" | while IFS= read -r line; do
    [ -n "$line" ] && printf 'FAIL: %s\n' "$line" >&2
  done
  printf '\nowner-path-rendering checks FAILED.\n' >&2
  exit 1
fi
exit 0
