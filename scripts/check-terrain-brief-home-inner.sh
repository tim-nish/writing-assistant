#!/usr/bin/env sh
# parallel-safe
# parallel-verified 2026-08-03 (Story 20.191) — everything this check writes
# lives under one `mktemp -d`: the fixture map, the workspace briefs and the
# HOME directory are all passed explicitly (`--out`, `--home`), so the real
# terrain output root is never touched and no other check reads these paths.
# tier: inner
# covers: scripts/terrain_brief.py scripts/topic-map-directions.py
#   scripts/resolve-paths.py
# removal-signal: the per-run workspace copy of a Brief is retired and `--out`
#   stops existing — the migration half of this check (AC3) is then asserting
#   about a location nothing writes, and the remaining home assertions fold
#   into check-brief-content-contract.sh, which already owns the artifact's
#   shape at the write.
# check-terrain-brief-home-inner.sh — the Brief's DURABLE HOME and its STABLE
# ID (Story 20.191, #1342; SPEC-terrain amendments, the 2026-08-03 block).
#
# WHAT IS ASSERTED, and why each is mechanical rather than a matter of reading
# the code:
#   * the home is the RESOLVER'S (`terrain-briefs-dir`), and the Brief lands
#     there under an id that is a function of the Brief and nothing else;
#   * the home copy and the workspace copy are IDENTICAL BYTE FOR BYTE — the
#     one property that proves a single writer with a single record, which is
#     otherwise only visible by reading two call sites;
#   * a re-open goes through the sanctioned reader and yields the same id, so
#     the address survives the round trip and a lifecycle transition;
#   * a Brief in the OLD workspace location still opens, is copied rather than
#     moved, and the migration is STATED on stderr;
#   * the home holds NO INDEX FILE — the listing is the enumeration, which is
#     the declined alternative the amendment names, so it is asserted absent
#     rather than merely not implemented.

set -u
cd "$(dirname "$0")/.."
D="scripts/topic-map-directions.py"
R="scripts/resolve-paths.py"
fail=0
ok()  { printf 'ok:   %s\n' "$1"; }
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
home="$work/home"
ws="$work/ws"
mkdir -p "$ws"

python3 - "$work" <<'PYEOF'
import json, sys
w = sys.argv[1]
els = [{"kind": "lesson", "slug": f"s{n}", "title": f"S{n}",
        "gloss": f"a claim the material makes, number {n}",
        "tags": ["workflow"], "situation": f"LESSONS.md:{n}@abc1234",
        "evidence": ["LESSONS.md:1@abc1234"], "consumed": False,
        "projects": ["repo-a"],
        "journey_recorded": True, "journey": f"the position changed, {n}"}
       for n in range(4)]
json.dump({"kind": "topic-map", "topics": [],
           "coverage": {"pin": "h@abc1234", "hub_pin": "hub@def5678"},
           "elements": els}, open(w + "/map.json", "w"))
PYEOF

pin=$(python3 -c "import json;print(json.load(open('$work/map.json'))['coverage']['pin'])")

emit() {  # $1 = selection string, $2 = --out path, $3.. = extra flags
  sel="$1"; out="$2"; shift 2
  printf '{"index":"%s","pin":"%s"}' "$sel" "$pin" \
    | python3 "$D" brief --map "$work/map.json" --answer - --out "$out" "$@" \
        > "$work/stdout.json" 2>"$work/err" \
    || { err "brief failed for '$sel': $(cat "$work/err")"; return 1; }
}

# --- AC1: the write lands in the home, under a stable id ---------------------
emit "L1, L2" "$ws/brief.json" --home "$home" \
  || { printf '\nFAILED.\n' >&2; exit 1; }

id=$(python3 -c "import json;print(json.load(open('$work/stdout.json'))['artifact']['id'])")
case "$id" in
  brief-*) ok "AC1: the written brief carries a stable id ($id)" ;;
  *) err "AC1: the artifact's id is not a stable id: '$id'" ;;
esac

[ -f "$home/$id.json" ] \
  && ok "AC1: ...and the brief landed in the home at that id" \
  || err "AC1: no $home/$id.json — the brief did not land in the home"

# --- AC2: the two copies are identical, and the reader reads the home --------
cmp -s "$ws/brief.json" "$home/$id.json" \
  && ok "AC2: the home copy is byte-identical to the workspace copy" \
  || err "AC2: the home copy differs from the workspace copy"

python3 "$D" brief-open --at "$home/$id.json" --home "$home" \
    > "$work/reopened.json" 2>"$work/open.err" \
  && ok "AC2: the home copy re-opens through the sanctioned reader" \
  || err "AC2: the home copy did not re-open: $(cat "$work/open.err")"

python3 - "$work" "$id" <<'PYEOF' || fail=1
import json, sys
w, ident = sys.argv[1], sys.argv[2]
r = json.load(open(w + "/reopened.json"))
bad = 0
if (r.get("opened") or {}).get("id") != ident:
    print(f"FAIL: AC2: the re-opened brief reports id "
          f"{(r.get('opened') or {}).get('id')!r}, not {ident!r} — the id is "
          f"not stable across a round trip", file=sys.stderr)
    bad = 1
else:
    print("ok:   AC2: the id is unchanged across the round trip")
sys.exit(bad)
PYEOF

# THE ID IS A FUNCTION OF THE BRIEF, asserted IN PROCESS rather than through
# two more CLI runs: the property is about the id and the writer, and paying a
# process start per assertion is what puts a check over the inner ceiling.
python3 - "$work" "$home" <<'PYEOF' || fail=1
import importlib.util, json, os, sys
w, home = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("tb", "scripts/terrain_brief.py")
tb = importlib.util.module_from_spec(spec); spec.loader.exec_module(tb)
rec = tb.read_brief_artifact(w + "/ws/brief.json")
bad = 0

def check(cond, msg):
    global bad
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stderr if not cond else sys.stdout)
    bad = bad or (0 if cond else 1)

before = sorted(os.listdir(home))
tb.write_brief_record(rec, None, home)
check(sorted(os.listdir(home)) == before,
      "AC1: re-writing the same composition rewrites ONE home entry — the id "
      "is not minted per write")
other = dict(rec, indexes=list(rec.get("indexes") or []) + ["L3"])
check(tb.brief_id(other) != tb.brief_id(rec),
      "AC4: a different member set is a different Brief, with its own id")
moved = dict(rec, lifecycle={"state": "adopted"})
check(tb.brief_id(moved) == tb.brief_id(rec),
      "AC2: a lifecycle transition does NOT move the id — the address "
      "survives what a re-open changes")
sys.exit(bad)
PYEOF

# --- AC4: the listing IS the enumeration, and there is no index file ---------
python3 "$R" list-briefs --root "$work" >/dev/null 2>&1 \
  && ok "AC4: the resolver enumerates the home (list-briefs)" \
  || err "AC4: list-briefs failed"

idx=$(ls "$home" | grep -v '^brief-.*\.json$' || true)
[ -z "$idx" ] \
  && ok "AC4: the home holds Briefs and nothing else — no index file is written" \
  || err "AC4: the home holds a non-Brief file ($idx): the listing must BE the enumeration"

# --- AC3: an old workspace Brief opens, migrates, and says so ----------------
emit "L2, L3" "$ws/legacy.json"          # written with NO home, as before
[ -f "$ws/legacy.json" ] || { err "AC3: fixture legacy brief was not written"; }

python3 "$D" brief-open --at "$ws/legacy.json" --home "$home" \
    > "$work/legacy-open.json" 2>"$work/legacy.err" \
  && ok "AC3: a brief in the old workspace location still opens" \
  || err "AC3: a workspace brief did not open: $(cat "$work/legacy.err")"

grep -q 'durable home copy' "$work/legacy.err" \
  && ok "AC3: ...and its migration is STATED, never silent" \
  || err "AC3: the migration was not stated: $(cat "$work/legacy.err")"

[ -f "$ws/legacy.json" ] \
  && ok "AC3: ...and the workspace copy is NOT deleted" \
  || err "AC3: the workspace copy was removed — this story deletes no Brief"

lid=$(python3 -c "import json;print(json.load(open('$work/legacy-open.json'))['opened']['id'])")
[ -f "$home/$lid.json" ] \
  && ok "AC3: ...and the durable copy is in the home under its stable id" \
  || err "AC3: the migrated brief is not at $home/$lid.json"

cmp -s "$ws/legacy.json" "$home/$lid.json" \
  && ok "AC3: ...carrying exactly what the workspace form carried" \
  || err "AC3: the migrated copy differs from the workspace form"

# --- The home is the RESOLVER'S, never composed by hand ----------------------
grep -n 'briefs' scripts/terrain_brief.py | grep -q 'os.path.join' \
  && err "terrain_brief.py composes the home directory itself — D1 says the resolver owns it" \
  || ok "D1: the home directory is passed in, never composed in terrain_brief.py"

[ "$fail" = "0" ] && printf '\nPASSED.\n' || { printf '\nFAILED.\n' >&2; exit 1; }
