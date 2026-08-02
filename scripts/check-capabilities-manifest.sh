#!/usr/bin/env sh
# parallel-safe
# tier: full — binds the manifest to the pre-PR gate run that executes the
# covers: CAPABILITIES.md scripts/check-*.sh
# covers-note (#1321): flag `sparse:1-paths/199-lines` ANSWERED BY WIDENING. The one derived
#   glob is right — a manifest row naming a check that was renamed or deleted is exactly the
#   rot this exists to catch, so every check file is covered. What the derivation could not
#   see is the subject itself: MANIFEST=CAPABILITIES.md sits at the repo ROOT, outside the
#   trees the extractor scans. Added by hand.
#   suite-resident evidence (#949); measured ~1s after the re-execution class
#   was removed (was 81.7s — evidence re-run per row)
# check-capabilities-manifest.sh — every CAPABILITIES.md row's evidence EXISTS
# and PASSES (Story 20.6, #805). The carrier-check idiom applied to capability
# claims: a manifest whose rows are prose rots exactly the way the status line
# that caused #805 rotted, so the claim is bound to a check that runs.
#
# The observed incident: an upstream sitting judged a shipped capability
# unimplemented from prose and started a duplicate build. A row here is only
# worth reading if it cannot make that claim falsely.
#
# The parser reads the table by its COLUMN HEADERS, never by position and never
# by any capability name — so another consumer repo can adopt the format
# unedited, which is the generic-seam half of #805.
#
# POSIX sh + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

MANIFEST=${MANIFEST:-CAPABILITIES.md}
# Failure state lives in a FILE, not a variable: the row loops below run in a
# pipeline subshell, where `fail=1` would be assigned and then discarded — a
# lint that reports failures and exits 0 is worse than no lint.
flag=$(mktemp)
trap 'rm -f "$flag" "${rowfile:-}"' EXIT
err() { printf 'FAIL: %s\n' "$1" >&2; printf 1 > "$flag"; }
ok()  { printf 'ok:   %s\n' "$1"; }
failed() { [ -s "$flag" ]; }

[ -f "$MANIFEST" ] || { err "$MANIFEST does not exist"; printf '\nFAILED.\n' >&2; exit 1; }

# 1. Parse the manifest by column header. A row missing a required column is a
#    format defect, reported as such rather than silently skipped.
rows=$(python3 - "$MANIFEST" <<'PY'
import re, sys

REQUIRED = ["id", "what it does", "status", "since", "evidence", "spec"]
text = open(sys.argv[1], encoding="utf-8").read()

# The manifest table is the one whose header carries every required column.
tables, cur = [], []
for line in text.splitlines():
    if line.startswith("|"):
        cur.append(line)
    elif cur:
        tables.append(cur); cur = []
if cur:
    tables.append(cur)

def cells(line):
    return [c.strip() for c in line.strip().strip("|").split("|")]

table = None
for t in tables:
    if len(t) < 3:
        continue
    head = [h.lower() for h in cells(t[0])]
    if all(r in head for r in REQUIRED):
        table = t
        break

if table is None:
    sys.stderr.write("error: no table carries every required column "
                     f"({', '.join(REQUIRED)})\n")
    raise SystemExit(1)

head = [h.lower() for h in cells(table[0])]
idx = {name: head.index(name) for name in REQUIRED}
STATUSES = {"implemented", "partial", "spec-only", "retired"}

out, bad = [], []
for line in table[2:]:                       # [1] is the |---| separator
    c = cells(line)
    if len(c) < len(head):
        bad.append(f"row has {len(c)} cells, header has {len(head)}: {line[:60]}")
        continue
    cap = c[idx["id"]].strip("`")
    status = c[idx["status"]]
    if status not in STATUSES:
        bad.append(f"{cap}: status {status!r} is not one of {sorted(STATUSES)}")
        continue
    ev = c[idx["evidence"]].strip("`")
    spec = c[idx["spec"]].strip("`")
    if not c[idx["what it does"]]:
        bad.append(f"{cap}: no one-liner")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", c[idx["since"]]):
        bad.append(f"{cap}: 'since' is not an ISO date ({c[idx['since']]!r})")
    out.append("\t".join([cap, status, ev, spec]))

for b in bad:
    sys.stderr.write(f"FAIL: {b}\n")
print("\n".join(out))
raise SystemExit(1 if bad else 0)
PY
) || { err "$MANIFEST does not parse as a capability manifest"; printf '\nFAILED.\n' >&2; exit 1; }

[ -n "$rows" ] || { err "$MANIFEST carries no capability rows"; printf '\nFAILED.\n' >&2; exit 1; }
ok "manifest parsed by column header ($(printf '%s\n' "$rows" | wc -l | tr -d ' ') capabilities)"

# The rows go to a FILE and the loops read from it. Piping them into `while`
# puts the pipe on the loop's stdin, and every check script invoked inside then
# INHERITS that pipe — the first one that reads stdin swallows the remaining
# rows, so later capabilities are silently never checked and the reader that
# consumed them looks like the failure. Each child also gets </dev/null.
rowfile=$(mktemp)
printf '%s\n' "$rows" > "$rowfile"

# 2. Every row's spec pointer resolves. A capability claiming a contract that
#    does not exist is the same defect as one claiming a check that does not.
while IFS="$(printf '\t')" read -r cap status ev spec; do
  if [ "$spec" = "—" ]; then continue; fi
  if [ -f "$spec" ]; then ok "$cap: spec pointer resolves ($spec)"
  else err "$cap: spec pointer does not exist ($spec)"; fi
done < "$rowfile"

# 3. Every row's evidence script EXISTS and PASSES. A `spec-only` or `retired`
#    row is exempt from the passing half by definition — it claims no running
#    implementation — but an `implemented` or `partial` row is not.
#
#    HOW the passing half is established depends on where the evidence lives
#    (#949). Evidence at `scripts/check-*.sh` is SUITE-RESIDENT: the full tier
#    executes every such file in the same pre-PR run, so a failing evidence
#    check already fails the gate on its own line, and re-running it here
#    charged the tier twice for the same information — measured 2026-07-30 at
#    ~80s of an 81.7s check (check-topic-map.sh re-run at 23.6s per citing
#    row, twice). For those rows this check asserts the BINDING — the evidence
#    exists inside the executed set — and the tier supplies the execution.
#    Evidence OUTSIDE the suite has no other executor, so it is still run
#    here: that is the generic-seam half of #805, where an adopting repo may
#    cite any script it likes. The rot incident stays caught either way — a
#    manifest row cannot claim a green check the same gate run shows red.
while IFS="$(printf '\t')" read -r cap status ev spec; do
  case "$status" in
    spec-only|retired)
      ok "$cap: $status — no running evidence required"; continue;;
  esac
  if [ ! -f "$ev" ]; then
    err "$cap: claims '$status' but its evidence does not exist ($ev)"
    continue
  fi
  case "$ev" in
    scripts/check-*.sh)
      ok "$cap: $status, evidence suite-resident ($ev — executed by this tier run)";;
    *)
      if sh "$ev" </dev/null >/dev/null 2>&1; then
        ok "$cap: $status, evidenced by a passing $ev"
      else
        err "$cap: claims '$status' but $ev FAILS"
      fi;;
  esac
done < "$rowfile"

# 4. NEGATIVE TEST: a row claiming `implemented` with a non-existent evidence
#    script must be caught and NAMED. A lint that has never been shown to fire
#    is a clean bill nobody earned — and this is the exact failure mode the
#    manifest exists to prevent, so it is tested, not assumed.
# GUARDED against self-recursion: the child invocation below runs this same
# script, and without the guard it would run this same negative test forever.
if [ "${CAPLINT_SELFTEST:-}" = "1" ]; then
  if failed; then printf '\nFAILED.\n' >&2; exit 1; fi
  printf '\nAll capability manifest checks passed.\n'
  exit 0
fi

tmp=$(mktemp -d); trap 'rm -rf "$tmp"; rm -f "$flag" "${rowfile:-}"' EXIT
cat > "$tmp/bad.md" <<'EOF'
| id | what it does | status | since | evidence | spec | hub carrier |
|---|---|---|---|---|---|---|
| `ghost` | Claims to exist with no evidence behind it. | implemented | 2026-07-27 | `scripts/check-nonexistent-capability.sh` | — | — |
EOF
if CAPLINT_SELFTEST=1 MANIFEST="$tmp/bad.md" sh "$0" </dev/null >"$tmp/out" 2>&1; then
  err "the lint PASSED a row whose evidence script does not exist"
else
  if grep -q "ghost" "$tmp/out"; then
    ok "negative test: a row with missing evidence fails, and the row is named"
  else
    err "the lint failed but did not name the offending row"
  fi
fi

# 5. The manifest states its own precedence. A capability surface that does not
#    say what it is authoritative FOR invites the reader to treat it as
#    authoritative for everything, including upstream state it never saw.
if grep -qi "precedence" "$MANIFEST"; then
  ok "the manifest declares its precedence"
else
  err "the manifest does not state what it is authoritative for"
fi

if failed; then printf '\nFAILED.\n' >&2; exit 1; fi
printf '\nAll capability manifest checks passed.\n'
