#!/usr/bin/env sh
# check-episode-candidates.sh — verify episode-candidate construction and
# selection on the missing-input repair hop (Story 13.91, #417). POSIX shell +
# stdlib Python.
#
# Checks: candidates group event-kind facts by source file with same-source
# support; the no-candidates state routes to the publish-blocker path;
# selection appends a pinned, grammar-valid fact-sheet entry; and the
# capture boundary holds — a pointer the fact sheet never captured is refused,
# as is a multi-line frame or a duplicate claim.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="scripts/draft-pipeline.py"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 - "$DP" <<'PY' && ok "episode-candidates/select behave per contract" || err "episode hop behavior drifted (see above)"
import importlib.util, io, json, os, sys, tempfile
from contextlib import redirect_stdout, redirect_stderr

spec = importlib.util.spec_from_file_location("dp", sys.argv[1])
dp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dp)

bad = []
tmp = tempfile.mkdtemp()
def w(name, obj):
    p = os.path.join(tmp, name)
    open(p, "w").write(json.dumps(obj))
    return p

FS = [
    {"claim": "loop breaker tripped on iter2", "source": "logs/loop.md:12@aaaaaaa", "kind": "event"},
    {"claim": "breaker reset after fix",       "source": "logs/loop.md:40@aaaaaaa", "kind": "event"},
    {"claim": "retry count fell to 0",         "source": "logs/loop.md:41@aaaaaaa", "kind": "number"},
    {"claim": "gateway shipped",               "source": "notes/ship.md:3@bbbbbbb", "kind": "event"},
    {"claim": "threshold is 3",                "source": "cfg/x.md:5@ccccccc",      "kind": "decision"},
]
state = w("state.json", {"fact_sheet": FS})

def run(fn, **kw):
    class A: pass
    a = A()
    for k, v in kw.items(): setattr(a, k, v)
    out, errbuf = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(errbuf):
        rc = fn(a)
    return rc, out.getvalue(), errbuf.getvalue()

# (a) grouping: two source files with events -> two candidates; support rides along.
rc, out, _ = run(dp.cmd_episode_candidates, state=state, section="evidence")
g = json.loads(out)
if rc != 0 or len(g["candidates"]) != 2:
    bad.append(f"expected 2 candidates, got {len(g.get('candidates', []))}")
else:
    loop = next((c for c in g["candidates"] if c["group"] == "logs/loop.md"), None)
    if not loop or len(loop["events"]) != 2:
        bad.append("logs/loop.md candidate missing its 2 events")
    elif not any(s["kind"] == "number" for s in loop["support"]):
        bad.append("same-source number fact not attached as support")
    if any(c["frame"] is not None for c in g["candidates"]):
        bad.append("a frame was pre-authored (must be null for the skill to fill)")
    if g["elicitation"]["options"][-1] != "decline":
        bad.append("elicitation lacks the explicit decline option")

# (b) no event facts -> publish-blocker path, zero candidates.
empty = w("empty.json", {"fact_sheet": [{"claim": "t", "source": "cfg/x.md:5@ccccccc", "kind": "decision"}]})
rc, out, _ = run(dp.cmd_episode_candidates, state=empty, section="evidence")
g = json.loads(out)
if rc != 0 or g.get("action") != "publish-blocker-path" or g["candidates"]:
    bad.append("no-candidates state did not route to the publish-blocker path")

# (c) select: appends a pinned entry; grammar-valid; constituents must be captured.
rc, out, _ = run(dp.cmd_episode_select, state=state,
                 frame="The loop breaker tripped, was fixed, and reset within one day",
                 pointers="logs/loop.md:12@aaaaaaa,logs/loop.md:40@aaaaaaa,logs/loop.md:41@aaaaaaa")
g = json.loads(out)
if rc != 0:
    bad.append("valid selection was refused")
else:
    added = g["fact_sheet"][-1]
    if added != {"claim": "The loop breaker tripped, was fixed, and reset within one day",
                 "source": "logs/loop.md:12@aaaaaaa", "kind": "event"}:
        bad.append(f"selected episode entry malformed: {added}")
    if g.get("episode_selected", {}).get("constituents", [])[-1] != "logs/loop.md:41@aaaaaaa":
        bad.append("constituent pointers not recorded")

# (d) capture boundary: an uncaptured pointer is refused (nothing new enters here).
rc, _, errtxt = run(dp.cmd_episode_select, state=state,
                    frame="frame", pointers="invented/file.md:1@ddddddd")
if rc != 2 or "already be captured" not in errtxt:
    bad.append("uncaptured constituent pointer was not refused")

# (e) multi-line frame and duplicate claim refused.
rc, _, _ = run(dp.cmd_episode_select, state=state, frame="a\nb", pointers="logs/loop.md:12@aaaaaaa")
if rc != 2: bad.append("multi-line frame accepted")
rc, _, _ = run(dp.cmd_episode_select, state=state, frame="gateway shipped", pointers="notes/ship.md:3@bbbbbbb")
if rc != 2: bad.append("duplicate claim accepted")

for b in bad: print(f"  drift: {b}", file=sys.stderr)
sys.exit(1 if bad else 0)
PY

if [ "$fail" -eq 0 ]; then printf '\nPASSED: episode candidates on the repair hop.\n'; else printf '\nFAILED.\n' >&2; exit 1; fi
