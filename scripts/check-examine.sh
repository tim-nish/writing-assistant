#!/usr/bin/env sh
# parallel-safe
# parallel-verified 2026-08-02 — all writes land in a private `mktemp -d`
#   (fixture repo + workspace); the only reads outside it are this repo's
#   scripts. No XDG state, no config home, no network source is consulted —
#   the issues source is exercised only with its transport stubbed, and its
#   ETag cache is redirected into the same private dir via EXAMINE_ETAG_CACHE.
# tier: inner
# covers: scripts/examine.py scripts/terrain_scope.py skills/draft-article/stages/examine.md skills/draft-article/stages/fan-out.md
# removal-signal: retire this check when examine's contract (never-judge,
#   anchored commits, derived-scope refusal, coverage separation, at-the-read
#   pin recording) is enforced by a schema over the emitted record rather than
#   by assertions here, or when the examine step itself is superseded.
# check-examine.sh — per-claim examination grounds a claim at the read that
# produced its pin, and the tool NEVER judges (Story 20.147, #1182/#1097/#1185).
#
# POSIX shell + stdlib Python.
set -u
cd "$(dirname "$0")/.."
fail=0
ok()  { printf 'ok:   %s\n' "$1"; }
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

EX="scripts/examine.py"
python3 -c "import py_compile; py_compile.compile('$EX', doraise=True)" 2>/dev/null \
  && ok "examine.py compiles" \
  || { err "examine.py syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
h="$work/host"; mkdir -p "$h"
git -C "$h" init -q
printf 'the retry storm was fixed by widening the backoff\n' > "$h/notes.md"
git -C "$h" add -A
git -C "$h" -c user.email=t@example.com -c user.name=t commit -qm "widen the retry backoff"

WS="$work/ws"; mkdir -p "$WS"

# 1. Commits are ANCHOR-ADDRESSED: no anchor -> skipped with the stated reason,
#    never a keyword search over history.
out=$(python3 "$EX" --root "$h" --claim "the retry backoff was widened" --sources commits)
printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["verdict"] is None, "verdict not null"
assert d["verdict_owner"], "no verdict_owner"
assert d["searched"] == [], "anchorless commits were searched"
sk = {s["source"]: s for s in d["skipped"]}
assert "commits" in sk and "anchor" in sk["commits"]["reason"], sk
' && ok "anchorless commits are SKIPPED with the anchor-addressing reason (never keyword-searched)" \
  || err "anchorless commits were not skipped with a reason"

# 2. An anchored query returns pinned, time-axis material with a citable form,
#    and --ws records the pin AT THE READ (record + ledger).
out=$(python3 "$EX" --root "$h" --claim "the retry backoff was widened" \
      --sources commits --anchor "path:notes.md" --ws "$WS")
printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["verdict"] is None and d["verdict_owner"], "tool judged, or no owner"
ev = d["evidence"]
assert ev and ev[0]["source_type"] == "commit" and ev[0]["time_axis"] is True, ev
assert ev[0]["cite"] and ev[0]["cite"] == ev[0]["ref"], "commit cite is not the sha"
assert d["counts"]["time_axis"] == len(ev), d["counts"]
assert d["recorded"]["record"] and d["recorded"]["pin_ledger"], "not recorded"
' && ok "anchored commit query: pinned time-axis evidence with a citable sha" \
  || err "anchored commit query wrong shape"
[ -s "$WS/examination-pins.txt" ] \
  && grep -qE '^[0-9a-f]{7,40}$' "$WS/examination-pins.txt" \
  && ok "the pin is recorded at the read: ledger carries the citable sha (AC1)" \
  || err "examination-pins.txt missing or carries no sha"
ls "$WS/examinations/"*.json >/dev/null 2>&1 \
  && ok "the full examination record persists under \$WS/examinations/" \
  || err "no examination record written"

# 3. Coverage separates read-empty from unreachable-empty (AC3): prose with no
#    declared sources is a SKIP with a reason, not an absence finding.
out=$(python3 "$EX" --root "$h" --claim "anything" --sources prose)
printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
sk = {s["source"]: s for s in d["skipped"]}
assert "prose" in sk and sk["prose"]["reason"], "prose skip carries no reason"
assert "coverage_claim" in d, "no coverage claim"
' && ok "coverage: an unreachable source is a skip WITH ITS REASON, never absence" \
  || err "coverage separation missing"

# 4. Derived scope binds (AC2): a repository outside the served attribution is
#    REFUSED, NOT SEARCHED — through terrain_scope's one refusal layer.
cat > "$work/scope.json" <<'EOF'
{"examine_scope": {"projects": ["other-repo"], "served": true,
 "by_member": [{"index": "1.2", "projects": ["other-repo"]}]}}
EOF
out=$(python3 "$EX" --root "$h" --claim "x" --scope "$work/scope.json" --member 1.2)
rc=$?
[ "$rc" -eq 3 ] && ok "out-of-scope examination exits 3 (refused)" \
  || err "out-of-scope examination did not exit 3 (rc=$rc)"
printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["refusal"]["refused"] is True, "no refusal"
assert "refused, not searched" in d["refusal"]["line"], d["refusal"]["line"]
assert d["evidence"] == [] and d["searched"] == [], "a refused scope was searched"
assert "false attribution" in d["refusal"]["line"], "refusal does not name the reason"
' && ok "refusal names the Strand attribution and searches NOTHING (#1185)" \
  || err "refusal shape wrong"

# 5. An in-scope repository proceeds (membership, not classification).
cat > "$work/scope2.json" <<EOF
{"examine_scope": {"projects": ["host"], "served": true,
 "by_member": [{"index": "1.2", "projects": ["host"]}]}}
EOF
python3 "$EX" --root "$h" --claim "x" --scope "$work/scope2.json" --member 1.2 \
  --sources commits >/dev/null 2>&1 \
  && ok "an in-scope repository is examined, not asked about" \
  || err "in-scope examination refused"

# 6. The retired sources gate stays unconstructible here too (AC4): the skill
#    text carries no sources-gate instruction, and no gate composes a file list.
grep -q 'sources_gate' skills/draft-article/stages/stage0.md \
  && err "stage0.md still instructs composing the retired sources gate (#1209)" \
  || ok "stage0.md carries no sources-gate instruction (#1209)"
grep -q 'compose or approve a file list' \
  skills/draft-article/stages/examine.md \
  && ok "examine.md states the no-file-list-gate contract" \
  || err "examine.md missing the no-file-list-gate statement"

# --- anchor-finding lives here, and reproducibility is the enumerator's ------
# (Story 20.155, #1224.) Probe is a permission check now and emits no anchors,
# so a dangling reference to "the probe's anchors" would send the model looking
# for a field that no longer exists.
grep -q "the probe's anchors" skills/draft-article/stages/examine.md \
  && err "examine still points at probe's anchors — probe emits none (#1224)" \
  || ok "no dangling reference to probe anchors"
grep -q "Anchor-finding lives HERE" skills/draft-article/stages/examine.md \
  && ok "examine states that anchor-finding is its own, per claim" \
  || err "the relocation of anchor-finding is undocumented"

# DETERMINISTIC ENUMERATION is CAP-10's one surviving mechanism, so it is
# asserted rather than assumed: the enumerator sorts, and examine consumes that
# order without re-deriving it.
python3 - <<'PY' && ok "the declared-file enumeration is deterministic (sorted at the source)" || err "the file enumeration is not sorted — CAP-10's reproducibility does not hold"
import re, sys
src = open("scripts/resolve-writing-sources.py").read()
assert re.search(r"files\s*=\s*sorted\(enumerate_files\(sources\)\)", src), \
    "cmd_files does not sort"
ex = open("scripts/examine.py").read()
assert "re-derive" in ex or "single source of truth" in ex, \
    "examine does not declare that it consumes the enumerator's order"
PY

# --- the writer contracts, reproduced (Story 20.162, #1248) ------------------
# The ledger is DERIVED, records are ID-NAMED, and the three sources run
# CONCURRENTLY. Reproduction-style, in one interpreter: the acceptance for the
# derived ledger is BYTE-IDENTITY between a serial and a concurrent run of the
# same claim set, never absence-of-crash — so all three orderings are run and
# their ledgers compared, not merely exercised.
for f in alpha beta gamma; do
  printf 'the %s path was widened\n' "$f" > "$h/$f.md"
  git -C "$h" add -A
  git -C "$h" -c user.email=t@example.com -c user.name=t commit -qm "widen $f"
done

H="$h" W="$work" python3 - <<'PY' && ok "writer contracts hold: derived ledger is byte-identical serial vs concurrent, records are id-named, sources run concurrently" || err "writer contracts (#1248) do not hold — see the assertion above"
import contextlib, io, json, os, sys, threading, time
sys.path.insert(0, "scripts")
import examine

H, W = os.environ["H"], os.environ["W"]
CLAIMS = [("c-one", "1", "the alpha path was widened", "alpha.md"),
          ("c-two", "2", "the beta path was widened", "beta.md"),
          ("c-three", "3", "the gamma path was widened", "gamma.md")]

def one(ws, spec):
    cid, idx, claim, path = spec
    rc = examine.main(["--root", H, "--ws", ws, "--claim", claim,
                       "--claim-id", cid, "--claim-index", idx,
                       "--sources", "commits", "--anchor", "path:" + path,
                       "--defer-ledger"])
    assert rc == 0, f"examination {cid} exited {rc}"

def ledger(ws):
    with open(os.path.join(ws, "examination-pins.txt"), "rb") as fh:
        return fh.read()

wss = {n: os.path.join(W, "ws-" + n) for n in ("fwd", "rev", "con")}
for ws in wss.values():
    os.makedirs(ws, exist_ok=True)
with contextlib.redirect_stdout(io.StringIO()):
    for spec in CLAIMS:
        one(wss["fwd"], spec)
    for spec in reversed(CLAIMS):
        one(wss["rev"], spec)
    threads = [threading.Thread(target=one, args=(wss["con"], s))
               for s in CLAIMS]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    for ws in wss.values():
        examine.derive_ledger(ws)

fwd, rev, con = (ledger(wss[n]) for n in ("fwd", "rev", "con"))
assert fwd.count(b"\n") == 3, f"expected one pin per claim, got {fwd!r}"
assert fwd == con, f"CONCURRENT ledger differs from serial:\n{fwd!r}\n{con!r}"
assert fwd == rev, f"ledger depends on completion order:\n{fwd!r}\n{rev!r}"

# Claim order GOVERNS: an explicit order reorders the derived ledger, so the
# byte-identity above is order-independence and not an accident of one pin set.
examine.derive_ledger(wss["fwd"], ["c-three", "c-two", "c-one"])
assert ledger(wss["fwd"]) != fwd, "claim order does not govern the derivation"

# No examination appended to the ledger: with --defer-ledger the join is the
# only writer, and each record names itself.
recs = dict(examine.read_records(wss["con"]))
assert sorted(recs) == ["c-one", "c-three", "c-two"], sorted(recs)
assert all(r["claim_index"] for r in recs.values()), "claim_index not recorded"

# ID-NAMED, so the 60-char truncation collision is unreachable: two long claims
# sharing a 70-character prefix are two records.
pre = "the pipeline stopped appending to the shared pin ledger because "
a, b = examine.claim_id(pre + "two concurrent examinations interleaved"), \
       examine.claim_id(pre + "a lock buys serialisation, not determinism")
assert a != b, f"truncation collision still reachable: {a}"
assert len(set([a[:60], b[:60]])) == 2 or a != b

# The join is invocable ON ITS OWN — the fan-out derives once over the set,
# and --derive-ledger needs no claim.
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    assert examine.main(["--ws", wss["con"], "--derive-ledger"]) == 0
assert json.loads(buf.getvalue())["records"] == 3, buf.getvalue()
assert ledger(wss["con"]) == con, "the standalone join derived a different ledger"

# THE OUTPUT CONTRACT IS PRESERVED under the concurrent gather (AC5): per-source
# searched/skipped records stay apart, in source order, with their reasons.
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    examine.main(["--root", H, "--claim", "the alpha path was widened",
                  "--sources", "commits,prose", "--anchor", "path:alpha.md"])
d = json.loads(buf.getvalue())
assert [s["source"] for s in d["searched"]] == ["commits"], d["searched"]
assert [s["source"] for s in d["skipped"]] == ["prose"], d["skipped"]
assert d["skipped"][0]["reason"], "prose skip lost its reason"
assert all(e["source_type"] == "commit" for e in d["evidence"]), d["evidence"]

# The three sources go CONCURRENTLY and the join is by source order: a claim's
# wall time is bounded by its SLOWEST source, not by their sum.
def slow(tag):
    def f(*a, **k):
        time.sleep(0.06)
        return [], tag
    return f
examine.examine_commits = slow("c")
examine.examine_issues = slow("i")
examine.examine_prose = slow("p")
t0 = time.monotonic()
res = examine.gather_sources(H, {"commits", "issues", "prose"}, ["x"],
                             {"path": [], "symbol": [], "ref": [],
                              "since": None, "until": None}, 5, True)
el = time.monotonic() - t0
assert set(res) == {"commits", "issues", "prose"}, res
assert el < 0.13, f"the three sources ran sequentially ({el:.2f}s of 0.18s)"
assert list(examine.SOURCE_ORDER) == ["commits", "issues", "prose"]
PY

# --- the issues source's THREAD FETCHES ride the REST core pool (20.165) -----
# Transport is STUBBED — no fixture may touch the real `gh` — and the cache is
# redirected into the private work dir. What is asserted is the transport, the
# conditional request, and that neither the population nor the output moved.
H="$h" W="$work" python3 - <<'PY' && ok "issue threads ride REST core with ETag conditional requests; list call and output contract unmoved (#1249)" || err "the issues source's thread transport (#1249) does not hold — see the assertion above"
import json, os, sys
sys.path.insert(0, "scripts")
import examine

H, W = os.environ["H"], os.environ["W"]
os.environ["EXAMINE_ETAG_CACHE"] = os.path.join(W, "etag-cache")

ETAG = 'W/"abc123"'
LIST = json.dumps([{"number": 7, "title": "the retry storm", "body": "body",
                    "createdAt": "2026-07-01T09:00:00Z",
                    "updatedAt": "2026-07-02T09:00:00Z",
                    "url": "https://example.invalid/o/r/issues/7",
                    "state": "OPEN", "labels": [{"name": "bug"}]}])
COMMENTS = json.dumps([{"created_at": "2026-07-02T09:00:00Z",
                        "body": "widening the backoff settled it"}])
CALLS = []
MODE = {"thread": "ok"}

def fake_run(cmd, cwd=None, timeout=60):
    CALLS.append(list(cmd))
    if cmd[:1] == ["git"]:
        return True, "git@example.invalid:o/r.git\n", ""
    if cmd[:3] == ["gh", "issue", "list"]:
        return True, LIST, ""
    if cmd[:2] == ["gh", "api"]:
        if MODE["thread"] == "unreachable":
            return False, "", "gh: could not connect"
        inm = [cmd[i + 1] for i, a in enumerate(cmd)
               if a == "-H" and cmd[i + 1].startswith("If-None-Match:")]
        if inm:
            assert ETAG in inm[0], inm
            # gh exits non-zero on a non-2xx status; `-i` still prints it.
            return False, "HTTP/2.0 304 Not Modified\r\netag: %s\r\n\r\n" % ETAG, \
                   "gh: HTTP 304"
        return True, ("HTTP/2.0 200 OK\r\nETag: %s\r\n"
                      "Content-Type: application/json\r\n\r\n%s" % (ETAG, COMMENTS)), ""
    raise AssertionError("unexpected transport call: %r" % (cmd,))

examine.run = fake_run
TERMS = ["retry", "backoff"]

first, why = examine.examine_issues(H, TERMS, 5, True)
assert why is None, why

# AC-1: the thread fetch is a REST core-pool read of the comments endpoint,
# and `gh issue view` (GraphQL) is gone.
api = [c for c in CALLS if c[:2] == ["gh", "api"]]
assert len(api) == 1, CALLS
assert "repos/{owner}/{repo}/issues/7/comments" in api[0], api[0]
assert not any(c[:3] == ["gh", "issue", "view"] for c in CALLS), CALLS

# AC-2: the term-searched list call is UNTOUCHED — still `gh issue list
# --search`, never migrated to /search/issues (pool limit 30).
lst = [c for c in CALLS if c[:3] == ["gh", "issue", "list"]]
assert len(lst) == 1 and "--search" in lst[0], CALLS
assert not any("search/issues" in a for c in CALLS for a in c), CALLS

# AC-5: the emitted shape is the one the GraphQL read produced.
assert [e["ref"] for e in first] == ["#7"], first
e = first[0]
assert e["source_type"] == "issue" and e["time_axis"] is True
assert e["cite"] == e["pin"] == "https://example.invalid/o/r/issues/7"
assert e["when"] == "2026-07-01" and e["state"] == "OPEN"
assert e["thread"] == [{"when": "2026-07-02",
                        "excerpt": "widening the backoff settled it"}], e["thread"]
assert "thread_unavailable" not in e

# AC-3: a thread consulted before is re-requested conditionally, the 304 is
# not an error, and the cache scope is the individual issue thread.
CALLS[:] = []
second, why2 = examine.examine_issues(H, TERMS, 5, True)
assert why2 is None
sent = [a for c in CALLS if c[:2] == ["gh", "api"] for a in c
        if a.startswith("If-None-Match:")]
assert sent and ETAG in sent[0], CALLS
cached = [n for n in os.listdir(os.environ["EXAMINE_ETAG_CACHE"])
          if n.endswith(".json")]
assert len(cached) == 1, cached

# AC-4 + AC-5: population and output are byte-identical across the fresh read
# and the 304 — the 304 path serves the same thread, it does not empty it.
assert json.dumps(second, sort_keys=True) == json.dumps(first, sort_keys=True)

# AC-6: an unreachable endpoint is CANNOT-DETERMINE — thread_unavailable —
# never an empty thread read as absence.
MODE["thread"] = "unreachable"
third, why3 = examine.examine_issues(H, TERMS, 5, True)
assert why3 is None and len(third) == 1, third
assert third[0].get("thread_unavailable") is True, third[0]
assert third[0]["thread"] == [], third[0]

# The cache key carries the repository: issue numbers collide across repos.
p1 = examine._thread_cache_path(H, 7, "git@example.invalid:o/r")
p2 = examine._thread_cache_path(H, 7, "git@example.invalid:o/other")
assert p1 != p2, p1
assert examine._thread_cache_path(H, 7, "x") != examine._thread_cache_path(H, 8, "x")
PY

# --- the fill's fan-out, and the trigger it must NOT widen (Story 20.164) ----
# The scheduling contract is prose (the dispatch has no code carrier — the fill
# is an LLM step), so what is checkable is that the prose exists, names the
# flags examine.py actually ships, and carries the constraint the whole
# amendment turns on: enumeration never becomes a stockpile.
FO="skills/draft-article/stages/fan-out.md"
[ -f "$FO" ] && ok "the fan-out scheduling companion exists" \
  || err "skills/draft-article/stages/fan-out.md missing (#1248)"
grep -q -- '--defer-ledger' "$FO" && grep -q -- '--derive-ledger' "$FO" \
  && grep -q -- '--claim-id' "$FO" \
  && ok "fan-out dispatches with the flags examine.py ships for it" \
  || err "fan-out.md does not use --claim-id/--defer-ledger/--derive-ledger"
grep -q 'byte-identical' "$FO" \
  && ok "fan-out states the derived ledger's byte-identity acceptance" \
  || err "fan-out.md omits the byte-identity acceptance (absence-of-crash is not it)"
grep -q 'claims we might need' "$FO" && grep -qi 'stockpile' "$FO" \
  && ok "fan-out FORBIDS widening enumeration to speculative claims (the ratified reading-pattern ruling)" \
  || err "fan-out.md does not forbid the speculative widening — AC-3's failure mode is unguarded"
grep -qi 'emerge mid-fill\|emerges mid-fill\|emerging mid-fill' "$FO" \
  && ok "fan-out keeps a mid-fill claim inline, as today" \
  || err "fan-out.md does not state that mid-fill claims stay inline"
grep -qi 'stockpile' skills/draft-article/stages/examine.md \
  && ok "examine.md restates the trigger against the fan-out's scheduling" \
  || err "examine.md does not hold the trigger against the fan-out"
grep -q 'fan-out.md' skills/draft-article/stages/stage3.md \
  && grep -q 'fan-out.md' skills/draft-article/SKILL.md \
  && ok "the fill and the dispatcher both point at the scheduling contract" \
  || err "fan-out.md is unreachable from stage3.md or the dispatcher"
# The win is reported honestly: owner-paced gates and composition are excluded
# BY NAME, because an end-to-end wall-clock claim would silently include them.
grep -qi 'owner-paced' "$FO" && grep -qi 'composition' "$FO" \
  && ok "fan-out names what its timings do NOT improve (owner-paced gates, composition)" \
  || err "fan-out.md does not exclude owner-paced gates / composition from the win"

[ "$fail" -eq 0 ] || { printf '\nexamine checks FAILED.\n' >&2; exit 1; }
printf '\nAll examine checks passed.\n'
