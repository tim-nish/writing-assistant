#!/usr/bin/env sh
# check-framework-f5.sh — verify the F5 working-note framework and its slim
# entry path (Story 13.89, #412). POSIX shell + stdlib Python.
#
# Checks: the template exists with the 4 ratified blocks in order (one lesson /
# one number / published-links / what-I'm-building) plus the shared pointer
# GATE; the ratified source constraints are stated; no [SKIP: …] tags and no
# visual placeholder (slim profile: no interview, no visual); and the entry
# path — resolve accepts "working-note"/"write a working note", the invalid-
# type error enumerates all five members, consume --framework working-note
# routes to fill, interview rejects F5 with a named error, and quality-gate
# --profile slim waives dims 1-2.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

F5="skills/draft-article/frameworks/F5-working-note.md"
DP="scripts/draft-pipeline.py"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
has() { if grep -qF -- "$1" "$F5"; then ok "$2"; else err "$2 (missing: $1)"; fi; }
absent() { if grep -qF -- "$1" "$F5"; then err "$2 (should be absent: $1)"; else ok "$2"; fi; }
line() { grep -nF -- "$1" "$F5" | head -1 | cut -d: -f1; }

[ -f "$F5" ] && ok "present: $F5" || { err "missing $F5"; printf '\nFAILED.\n' >&2; exit 1; }

# 1. The 4 fixed blocks, in order, plus the shared pointer GATE.
prev=0; order_ok=1
check_order() {
  ln=$(line "$1")
  if [ -z "$ln" ]; then err "section missing: $1"; order_ok=0; return; fi
  if [ "$ln" -le "$prev" ]; then err "out of order: $1 (line $ln after $prev)"; order_ok=0; fi
  prev=$ln
}
check_order "## Frontmatter"
check_order "## GATE {One lesson}"
check_order "## GATE {One number}"
check_order "## {Published links}"
check_order "## {What I'm building}"
check_order "## GATE {Pointer block}"
[ "$order_ok" -eq 1 ] && ok "the 4 blocks + pointer GATE appear in the fixed order"

# 2. Ratified constraints stated; slim markers; conventions reused.
has "assembly <1hr"                    "assembly-<1hr contract stated"
has "lessons first"                    "policy recall surface constraint (lessons first)"
has "never a harvest source"           "Q&A-archive exclusion stated"
has "public repository links only"     "public-links-only constraint stated"
has "CONVENTIONS.md"                   "reuses shared conventions"
has "--profile slim"                   "names the lighter gate invocation"

# 2b. Narrative-arc sourcing for the one-lesson block (Story 13.93, #425).
has "narrative-arc sourcing"           "one-lesson arc sourcing contract referenced"
has "misconception"                    "arc mapping: misconception stated"
has "turning point"                    "arc mapping: turning point stated"
has "## Journey"                       "Journey-section selection input named"
has "origin:"                          "origin marker convention named"
has "the origin marker to the owner"   "origin marker surfaced to owner at selection"
has "never the batch history"          "batch-history exclusion restated at the source"

# Prose may MENTION the tags to explain their absence; the invariant is that
# no slot heading carries one and no placeholder line exists.
if grep -qE '^##.*\[SKIP:' "$F5"; then err "a slot heading carries [SKIP:] (slim profile has no interview)"; else ok "no slot carries a [SKIP] tag"; fi
if grep -qE '^\s*\{?\[Figure:' "$F5"; then err "a [Figure:] placeholder line exists (F5 declares no visual slot)"; else ok "no [Figure] placeholder line"; fi

# 3. Entry path (Story 13.89): pipeline behavior, no workspace needed.
python3 - "$DP" <<'PY' && ok "entry path: resolve/labels/consume/interview/gate behave per contract" || err "entry-path behavior drifted (see above)"
import importlib.util, io, json, sys
from contextlib import redirect_stdout, redirect_stderr

spec = importlib.util.spec_from_file_location("dp", sys.argv[1])
dp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dp)

bad = []
# resolve: both spellings reach f5; label registered.
if dp.resolve_framework("working-note") != "f5": bad.append("resolve('working-note') != f5")
if dp.resolve_framework("write a working note") != "f5": bad.append("resolve('write a working note') != f5")
if dp.INTENT_LABELS.get("f5") != "write a working note": bad.append("INTENT_LABELS missing f5")
if dp.FRAMEWORKS.get("f5") != "F5-working-note.md": bad.append("FRAMEWORKS missing f5")
if "f5" not in dp.SLIM_PROFILE_FRAMEWORKS: bad.append("f5 not marked slim")

# invalid-type error enumerates all five members.
buf = io.StringIO()
with redirect_stderr(buf):
    state, code = dp._run_state("a-listicle", [], None)
msg = buf.getvalue()
if state is not None or code != 2: bad.append("_run_state accepted an invalid type")
for lbl in dp.INTENT_LABELS.values():
    if lbl not in msg: bad.append(f"invalid-type error omits {lbl!r}")
if "all five" not in msg: bad.append("invalid-type error no longer names all five")

# consume --framework working-note routes to fill (in-process, stdin doc).
class A: doc = "-"; framework = "working-note"
doc = "# FACT SHEET\n\n# NEEDS-OWNER\n"
out, errbuf = io.StringIO(), io.StringIO()
sys.stdin = io.StringIO(doc)
with redirect_stdout(out), redirect_stderr(errbuf):
    rc = dp.cmd_consume(A())
sys.stdin = sys.__stdin__
if rc != 0: bad.append(f"consume --framework working-note failed: {errbuf.getvalue().strip()}")
else:
    st = json.loads(out.getvalue())
    if st.get("next_stage") != "fill": bad.append("consume slim route: next_stage != fill")
    if st.get("profile") != "slim": bad.append("consume slim route: profile != slim")

# interview rejects F5 with a named slim-profile error.
class B: framework = "f5"; items = None
errbuf = io.StringIO()
with redirect_stderr(errbuf):
    rc = dp.cmd_interview(B())
if rc != 2 or "no interview stage" not in errbuf.getvalue():
    bad.append("interview does not reject F5 with the named slim error")

# quality-gate --profile slim: dims 1-2 waived, no judge required.
class C:
    draft = "-"; map = None; judge = None; audience_known = None
    cycle = 1; prior_locations = None; profile = "slim"
draft = "---\naudience: maintainers of small OSS tools\naudience_id: oss-maintainer\n---\nBody.\n"
out = io.StringIO()
sys.stdin = io.StringIO(draft)
with redirect_stdout(out), redirect_stderr(io.StringIO()):
    rc = dp.cmd_quality_gate(C())
sys.stdin = sys.__stdin__
gate = json.loads(out.getvalue())
for d in ("dim1", "dim2"):
    if gate["dimensions"][d]["verdict"] != "waived": bad.append(f"slim gate: {d} not waived")
if "dim3" not in gate["dimensions"] or "dim4" not in gate["dimensions"]:
    bad.append("slim gate dropped a mechanical dimension")
# and with a judge file supplied, slim refuses (exit 2).
class D(C): judge = "/dev/null"
errbuf = io.StringIO()
sys.stdin = io.StringIO(draft)
with redirect_stdout(io.StringIO()), redirect_stderr(errbuf):
    rc2 = dp.cmd_quality_gate(D())
sys.stdin = sys.__stdin__
if rc2 != 2: bad.append("slim gate accepted --judge (should refuse, exit 2)")

for b in bad: print(f"  drift: {b}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY

if [ "$fail" -eq 0 ]; then printf '\nPASSED: F5 working-note framework + slim entry path.\n'; else printf '\nFAILED.\n' >&2; exit 1; fi
