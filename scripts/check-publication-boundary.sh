#!/usr/bin/env sh
# check-publication-boundary.sh — reject private provenance in the public tree
# (owner decision 2026-07-16; SPEC-writing-assistant "Publication boundary",
# #211). This repo is public; the ratified boundary is "mechanism public,
# provenance private": the tree may state that a decision was ratified (date +
# title) and may document how the policy-source seam works, but never the
# address, layout, internal names, or commit pins of the owner's private hub.
# POSIX shell + stdlib Python only.
#
# TWO RULE SETS, DELIBERATELY DIFFERENT IN REACH (widened 2026-07-17):
#
#   A. PROVENANCE VALUES — the COMPLETE Git-tracked tree. A real commit pin is
#      owner-specific data wherever it sits, so this rule follows the VALUE,
#      not the directory: a leak cannot bypass merely by living under scripts/,
#      skills/, docs/, or fixtures — which is exactly what happened until
#      2026-07-17, when three test fixtures and four spec citations carried
#      real hub pins past a specs/-only check.
#        A1  a hub recall-surface pointer on a non-synthetic pin:
#            (GLOSSARY.md|LESSONS.md|topics/<f>.md):LINE[-LINE]@<sha>
#        A2  a hub-name pin `product-lab@<sha>` on a non-synthetic sha
#
#   B. HUB NAME / LAYOUT LITERALS — specs/ only (reach unchanged).
#      The hub name on the shipped surface (skills/, commands/) is already
#      governed by check-generic-engine.sh, which DELIBERATELY excludes
#      scripts/ ("tests/tools ... may name the proxy as a guard string") and
#      config/. Widening B tree-wide would fight that ratified exclusion and
#      flag legitimate documentation of the mechanism: `--pin product-lab@<sha>`
#      help text, reader fixtures that prove `q_a/` is refused by code,
#      `path: ../product-lab` in example configs. Rule A is what closes the
#      bypass; B stays where the ratified split put it.
#
# SYNTHETIC PINS: fixtures and docs must pin to a DECLARED synthetic value.
# This check cannot resolve a sha against the (private) hub, so the rule is
# inverted — anything outside the declared synthetic set is presumed real. That
# is a registry of fake values, never an allowlist of leaking files.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# The scanner is factored out so the self-tests below prove the rules on known
# shapes instead of trusting them by inspection.
cat > "$work/scan.py" <<'PY'
import re, sys

# Declared synthetic pin prefixes — the ONLY commit pins allowed in the public
# tree. When a fixture needs a new fake pin, extend THIS list; never add an
# exception for a file.
SYNTHETIC = ("8f3c2d1", "abc1234", "0000000", "deadbee", "1111111")

# Four shapes, because a pin does not only appear as a pointer. The first
# version of this check caught only HUB_POINTER and passed a tree that still
# held four real pins: a bare `sha = "..."` that BUILDS pointers at runtime, a
# pin quoted in spec prose, and a second hub name (`policy-hub@`). Each shape
# below exists because a real leak used it.
HUB_POINTER = re.compile(
    r"\b(GLOSSARY\.md|LESSONS\.md|topics/[A-Za-z0-9._-]+\.md)"
    r":\d+(?:-\d+)?@([0-9a-f]{7,40})\b")
# Any hub-ish name, not just one. Placeholders ($SHA, <commit>, {pin}) are
# documentation, not values, and never match: they are not hex.
HUB_PIN = re.compile(r"\b([a-z][a-z0-9-]*(?:-lab|-hub|-repo))@([0-9a-f]{7,40})\b")
# A pin quoted in prose: "pin <sha>", "pin: <sha>", "pin=<sha>".
PROSE_PIN = re.compile(r"\bpin[\s:=]+`?([0-9a-f]{7,40})`?\b", re.I)
# A bare commit value assigned to a sha-shaped name — the form that renders
# pointers at runtime while showing no pointer in the source.
BARE_SHA = re.compile(r"\b(?:sha|pin|commit)\s*[:=]\s*[\"']([0-9a-f]{7,40})[\"']", re.I)


def synthetic(sha):
    return any(sha.startswith(p) for p in SYNTHETIC)


def scan(paths):
    out = []
    rules = ((HUB_POINTER, 2, "hub line pointer on a non-synthetic commit"),
             (HUB_PIN, 2, "hub pin on a non-synthetic commit"),
             (PROSE_PIN, 1, "commit pin quoted in prose"),
             (BARE_SHA, 1, "bare commit value assigned to a sha/pin/commit name"))
    for p in paths:
        try:
            with open(p, encoding="utf-8", errors="replace") as fh:
                lines = fh.readlines()
        except OSError:
            continue
        for n, line in enumerate(lines, 1):
            seen = set()
            for rx, grp, label in rules:
                for m in rx.finditer(line):
                    if synthetic(m.group(grp)) or m.group(grp) in seen:
                        continue
                    seen.add(m.group(grp))
                    out.append((p, n, f"{label}: {m.group(0).strip()}"))
    return out


if __name__ == "__main__":
    findings = scan([l.strip() for l in sys.stdin if l.strip()])
    for p, n, msg in findings:
        print(f"{p}:{n}: {msg}")
    sys.exit(1 if findings else 0)
PY

# --- A. Provenance values across the complete tracked tree ---------------------
# The check names the patterns it hunts, so it must not scan itself.
git ls-files | grep -v '^scripts/check-publication-boundary\.sh$' > "$work/tracked"
if out=$(python3 "$work/scan.py" < "$work/tracked"); then
  ok "no real hub pins or line pointers in the tracked tree ($(wc -l < "$work/tracked" | tr -d ' ') files)"
else
  printf 'FAIL: owner-specific provenance in the public tree (publication boundary):\n' >&2
  printf '%s\n' "$out" | sed 's/^/  /' >&2
  printf '  Use a declared synthetic pin in fixtures/docs, or drop the locator and\n' >&2
  printf '  keep the idea (see #328) — never a real hub commit.\n' >&2
  fail=1
fi

# --- B. Hub name / layout literals under specs/ (reach unchanged) ---------------
# .memlog.md files are BMAD process artifacts, gitignored and never tracked, so
# they are excluded: process scratch must not gate the contract lint.
PATTERN='product-lab|q_a/|~/work|lessons/[a-z0-9-]*\.md'
violations=$(grep -rnE "$PATTERN" specs/ --include='*.md' | grep -v '/\.memlog\.md:' || true)
if [ -n "$violations" ]; then
  printf 'FAIL: private provenance markers under specs/ (publication boundary):\n' >&2
  printf '%s\n' "$violations" | sed 's/^/  /' >&2
  printf '  Replace with a generic decision line — e.g.\n' >&2
  printf '  "owner decision record — YYYY-MM-DD (title)" — and keep hub paths private.\n' >&2
  fail=1
else
  ok "no hub-name/layout literals under specs/"
fi

# --- Self-tests: prove the rules on known shapes -------------------------------
mkdir -p "$work/t/scripts"

# (1) Every former leak SHAPE must FAIL. The reproductions use a stand-in pin
# (F00DBABE…), never a real one: this script is excluded from its own scan, so
# a real pin pasted in here would be a leak the guard structurally cannot see —
# which is exactly what happened on the first attempt at this check.
FAKE="f00dbabe0000000000000000000000000000cafe"
printf '{"seed": {"pointer": "topics/articles.md:36@%s"}}\n' "$FAKE" > "$work/t/leak-companion.json"
printf '{"seed": {"pointer": "GLOSSARY.md:168@%s"}}\n'        "$FAKE" > "$work/t/leak-stale.json"
printf '(evidence-gate-must-be-agent-fed, LESSONS.md:44@%s).\n' "$FAKE" > "$work/t/leak-spec.md"
printf 'sha = "%s"\n'                                          "$FAKE" > "$work/t/leak-bare-sha.py"
printf 'pinned recall surface (pin %s, 2026-07-16)\n'          "$FAKE" > "$work/t/leak-prose-pin.md"
printf 'consulted: policy-hub@%s — LESSONS.md:39 → finding 1\n' "$FAKE" > "$work/t/leak-alt-hub.md"
for f in leak-companion.json leak-stale.json leak-spec.md leak-bare-sha.py \
         leak-prose-pin.md leak-alt-hub.md; do
  printf '%s\n' "$work/t/$f" | python3 "$work/scan.py" >/dev/null 2>&1 \
    && err "leak shape NOT caught: $f" || ok "leak shape caught: $f"
done

# (2) Valid, fully synthetic fixture provenance must PASS.
printf '{"seed": {"quote": "an illustrative fixture-owned line", "pointer": "LESSONS.md:41@8f3c2d1e4a5b6c7d8e9f0a1b2c3d4e5f60718293"}}\n' \
  > "$work/t/ok-fixture.json"
printf '%s\n' "$work/t/ok-fixture.json" | python3 "$work/scan.py" >/dev/null 2>&1 \
  && ok "synthetic fixture provenance passes (8f3c2d1…)" \
  || err "synthetic fixture provenance was flagged"

# (3) An equivalent leak OUTSIDE specs/ must FAIL — the bypass that existed.
printf 'pin="LESSONS.md:39@%s"\n' "$FAKE" \
  > "$work/t/scripts/leak-outside-specs.sh"
printf '%s\n' "$work/t/scripts/leak-outside-specs.sh" | python3 "$work/scan.py" >/dev/null 2>&1 \
  && err "a leak under scripts/ bypassed the check" \
  || ok "an equivalent leak outside specs/ fails (bypass closed)"

# (4) Ordinary generic documentation of the mechanism must NOT false-positive.
cat > "$work/t/generic-docs.md" <<'EOF'
The reader records the run pin `product-lab@<commit>`; every quote carries
`file:line@commit`. Pass `--pin product-lab@<sha>` in seeded mode; the helper
prints `consulted: product-lab@$SHA — LESSONS.md:39 → finding 1`. A fixture may
pin to product-lab@abc1234. Example: `path: ../product-lab`, drafts at
~/work/articles/drafts/, and the reader refuses q_a/secret.md by code.
EOF
printf '%s\n' "$work/t/generic-docs.md" | python3 "$work/scan.py" >/dev/null 2>&1 \
  && ok "generic mechanism documentation does not false-positive" \
  || err "generic documentation was flagged as a leak"

if [ "$fail" -eq 0 ]; then
  printf '\nOK: no owner-specific provenance in the public tree.\n'; exit 0
else
  printf '\npublication-boundary checks FAILED.\n' >&2; exit 1
fi
