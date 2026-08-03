#!/usr/bin/env sh
# parallel-safe
# tier: inner — a handful of in-process python calls over string fixtures and
#   one grep of the pipeline's complete path; no repo clone, no network.
# covers: scripts/product_citation.py scripts/draft-pipeline.py
# removal-signal: the "a reader-facing citation in an emitted product is
#   CONSTRUCTED repo-qualified" amendment (SPEC-writing-assistant,
#   2026-08-03, #1339) is overturned per its own recorded condition — drafts
#   prove to need short internal references with only the published variant
#   resolving them, which arrives as a variant-side amendment. The check
#   retires with the clause; it also retires if product_citation.py's
#   construct path is absorbed into the emitter such that no product text is
#   ever hand-authored.
# check-product-citation.sh — a product's reader-facing COMMIT citation is
# constructed repo-qualified from the examination record's `pin`, and a bare
# repo-unqualified sha is unconstructible (Story 20.195, #1339).
#
# THE CONSTRUCT SIDE IS THE MECHANISM, the scan is the backstop: these
# assertions are ordered that way on purpose. Scope is COMMIT references in
# emitted products — issue and URL references are emitted unchanged, and
# `path:line@sha` pins in this repository's own body text stay with
# check-citation-form.sh (asserted below, so no second authority is created).
#
# POSIX sh + stdlib Python only.

set -u

SCRIPTDIR=$(cd "$(dirname "$0")" && pwd)
MOD="$SCRIPTDIR/product_citation.py"
PIPELINE="$SCRIPTDIR/draft-pipeline.py"

fail=0
ok()  { printf 'ok:   %s\n' "$1"; }
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

[ -f "$MOD" ] || { err "scripts/product_citation.py is missing — the construct side has no carrier"; exit 1; }

WS=$(mktemp -d) || { err "mktemp failed"; exit 1; }
trap 'rm -rf "$WS"' EXIT INT TERM

# --- AC1: constructed from the record's pin, repo-qualified ------------------
out=$(python3 "$MOD" render --pin "writing-assistant@03e6cfa" 2>&1)
if [ "$out" = "writing-assistant@03e6cfa" ]; then
  ok "AC1 a commit citation renders repo-qualified from the record's pin ($out)"
else
  err "AC1 render from a pin did not produce the repo-qualified citation — got: $out"
fi

# --- AC1: a bare sha is UNCONSTRUCTIBLE, not silently passed through ---------
if python3 "$MOD" render --pin "03e6cfa" >/dev/null 2>"$WS/bare.err"; then
  err "AC1 a bare repo-unqualified sha was composed into a citation — it must be unconstructible"
elif grep -q "not composable" "$WS/bare.err"; then
  ok "AC1 a bare sha is refused at construction, naming the reason (not composable)"
else
  err "AC1 the bare-sha refusal did not explain itself: $(tr '\n' ' ' < "$WS/bare.err")"
fi

# --- AC1: the record IS the source — cite-map derives it from examinations ---
mkdir -p "$WS/examinations"
cat > "$WS/examinations/c1.json" <<'EOF'
{
  "claim_id": "c1",
  "evidence": [
    {"source_type": "commit", "pin": "writing-assistant@03e6cfa", "cite": "03e6cfa"},
    {"source_type": "issue",  "pin": "https://example.invalid/issues/7",
     "cite": "https://example.invalid/issues/7"}
  ]
}
EOF
mapout=$(python3 "$MOD" cite-map --ws "$WS" 2>&1)
case "$mapout" in
  *"03e6cfa	writing-assistant@03e6cfa"*)
    ok "AC1 the bare ledger cite maps to the record-derived repo-qualified citation" ;;
  *) err "AC1 cite-map did not derive the citation from the examination record — got: $mapout" ;;
esac
case "$mapout" in
  *example.invalid*) err "AC3 a URL reference was rewritten — issue/URL references are emitted unchanged" ;;
  *) ok "AC3 issue/URL evidence is untouched by the commit-citation construct" ;;
esac

# --- AC2: the backstop refuses a bare commit reference, NAMING it ------------
cat > "$WS/bad.md" <<'EOF'
---
title: A product
---
The guard landed in commit 556ab1b, which nobody can resolve.
EOF
scanout=$(python3 "$MOD" scan "$WS/bad.md" 2>&1)
if [ $? -eq 0 ]; then
  err "AC2 a product carrying a bare repo-unqualified commit reference was admitted"
else
  case "$scanout" in
    *556ab1b*) ok "AC2 the write is refused and the citation is NAMED ($(printf '%s' "$scanout" | head -1))" ;;
    *) err "AC2 refused but did not name the citation — got: $scanout" ;;
  esac
fi

# --- AC2: a run already carrying `<qualifier>@` names its repository ONCE ----
# The pipeline's own `generated_by` line is `<repo>@<version>+<sha>` — semver
# build metadata on an already-qualified token, not a second citation. A
# product carrying BOTH forms yields exactly ONE finding, and it is the bare
# one: keyed on the property that makes a reference resolvable, never on the
# field name, so the next generated field carrying a build sha does not reopen
# it (#1391).
cat > "$WS/mixed.md" <<'EOF'
---
title: A product
generated_by: writing-assistant@0.1.0+c223004
---
the runner declares it serially (`c0408c7`)
EOF
mixedout=$(python3 "$MOD" scan "$WS/mixed.md" 2>&1)
if [ $? -eq 0 ]; then
  err "AC2 the bare sha beside a generated_by line was admitted — the backstop went blind"
else
  nfound=$(printf '%s' "$mixedout" | grep -o 'line [0-9]*:' | wc -l | tr -d ' ')
  case "$mixedout:$nfound" in
    *c223004*) err "AC2 generated_by's build-metadata sha was flagged — the run already names its repository (#1391)" ;;
    *c0408c7*:1) ok "AC2 exactly one finding, and it is the bare sha — the qualified run is admitted (#1391)" ;;
    *c0408c7*) err "AC2 the bare sha was named but the finding count is $nfound, not 1 — got: $mixedout" ;;
    *) err "AC2 refused without naming the bare sha — got: $mixedout" ;;
  esac
fi

# --- AC3/AC4/AC5: what must be emitted UNCHANGED -----------------------------
cat > "$WS/good.md" <<'EOF'
---
title: A product
---
The guard landed in `writing-assistant@556ab1b` — see
https://github.com/example/writing-assistant/commit/556ab1b and issue #1339.
This repository's own pin form is untouched: scripts/probe.py:12@8f3c2d1.

```
a fenced literal is shown, not followed: commit 556ab1b
```
<!-- writing-assistant: canonical-sha256=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef -->
EOF
if python3 "$MOD" scan "$WS/good.md" >/dev/null 2>"$WS/good.err"; then
  ok "AC3/AC4/AC5 admitted unchanged: repo-qualified pin, commit URL, issue ref, path:line@sha pin, fenced literal, canonical-sha256 trailer"
else
  err "a conforming product was refused — the backstop is over-reaching: $(tr '\n' ' ' < "$WS/good.err")"
fi

# --- AC4: no second authority over this repository's own body text -----------
if grep -q "check-citation-form.sh" "$MOD"; then
  ok "AC4 the module states the boundary: path:line@sha pins stay with check-citation-form.sh"
else
  err "AC4 the module does not state that path:line@sha pins remain check-citation-form.sh's — the split must be written down where it is implemented"
fi

# --- AC2: the call site exists on the `complete` write path ------------------
if [ -f "$PIPELINE" ]; then
  if awk '/^def cmd_complete/,/^def _/' "$PIPELINE" | grep -q "product_citation.py"; then
    ok "AC2 the completion gate calls the backstop before persisting the canonical"
  else
    err "AC2 cmd_complete does not call product_citation — a hand-authored product could re-open the hole at the write layer"
  fi
else
  err "scripts/draft-pipeline.py not found — cannot verify the completion-gate call site"
fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll product-citation checks passed (scope: the construct path, the completion backstop, and the exemptions; standing product text elsewhere is not asserted).\n'
  exit 0
else
  printf '\nproduct-citation checks FAILED.\n' >&2
  exit 1
fi
