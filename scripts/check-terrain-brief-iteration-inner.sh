#!/usr/bin/env sh
# parallel-safe
# covers: scripts/topic-map-directions.py scripts/terrain_text.py
#   skills/terrain/steps/brief.md
# tier: inner — the brief gate's ITERATION LOOP (Story 20.77, #997) against a
#   derived fixture map; no seam, no corpus, no assembly. Its own check rather
#   than more assertions in check-terrain-select-brief-inner.sh (~1.0s of a 2s
#   ceiling): the loop needs a chain of compositions, which is CLI runs, and
#   the #948 split exists because exactly that kind of growth pushed a check
#   to ~90% of INNER_MS and made it fail on load variance. Measured
#   2026-07-31: ~1.2s (ceiling 2s).
# removal-signal: the terrain checks are retired or re-shaped under the #910
#   retention sweep (a check provably subsumed by the #857/#858 seam, or the
#   full-tier terrain harnesses rebuilt fixture-based), which re-places these
#   assertions; removed with that pass.
# check-terrain-brief-iteration-inner.sh — the edit-set option class, the
# recomposition it reaches, the retained chain, the within-sitting bound, and
# the refusals that keep an edit from being anything other than what the owner
# named.
set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

D="scripts/topic-map-directions.py"
FIX="scripts/fixtures/terrain/screen-map.json"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# One prep run widens the fixture to enough Strands for a set to be edited
# (#950 batching: one interpreter for the map and every answer fixture).
python3 - "$FIX" "$work" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1])); w = sys.argv[2]
strands = list(d.get("elements") or [])
for n in range(6):
    strands.append({
        "kind": "lesson", "slug": f"widened-{n:02d}", "title": f"Lesson {n}",
        "topic": "engineering" if n % 2 else "people",
        "date": f"2026-07-{n + 1:02d}",
        "gloss": f"A claim the material itself makes, number {n}",
        "situation": f"LESSONS.md:{n + 10}@abc1234",
        "evidence": [f"LESSONS.md:{n + 10}@abc1234"], "consumed": False})
d["elements"] = strands
json.dump(d, open(w + "/map.json", "w"))
PYEOF

python3 "$D" candidates --map "$work/map.json" > "$work/cands.json"

# One prep call writes every answer fixture and reports the pin.
pin=$(python3 - "$work" <<'PYEOF'
import json, sys
w = sys.argv[1]
pin = json.load(open(w + "/map.json"))["coverage"]["pin"]
ids = [c["id"] for c in json.load(open(w + "/cands.json"))["candidates"]
       if c["kind"] == "element"]
a, b, c, d = ids[0], ids[1], ids[2], ids[3]
put = lambda name, obj: json.dump(obj, open(f"{w}/{name}.json", "w"))
put("a-first", {"index": [a, b], "note": "through the on-call retro",
                "pin": pin})
put("a-edit", {"edit": f"+{c} −{a}", "pin": pin})          # unicode minus
put("a-edit2", {"edit": f"+{d}", "pin": pin})
put("a-free", {"edit": f"+{d}", "pin": pin,
               "free_text": "my own direction, in my own words"})
put("a-unsigned", {"edit": c, "pin": pin})
put("a-stale", {"edit": f"+{c}", "pin": "deadbeef"})
print(f"{pin} {a} {b} {c} {d}")
PYEOF
)
mappin=${pin%% *}

# --- the loop itself: compose, then edit twice, in ONE workspace ------------
python3 "$D" brief --answer "$work/a-first.json" --map "$work/map.json" \
  --out "$work/ws/brief.json" > "$work/b1.json"
python3 "$D" brief --answer "$work/a-edit.json" --map "$work/map.json" \
  --from "$work/ws/brief.json" --out "$work/ws/brief-2.json" > "$work/b2.json"
python3 "$D" brief --answer "$work/a-edit2.json" --map "$work/map.json" \
  --from "$work/ws/brief-2.json" --out "$work/ws/brief-3.json" > "$work/b3.json"

# AC5 — free text wins at ANY point in the loop, including over an edit.
python3 "$D" brief --answer "$work/a-free.json" --map "$work/map.json" \
  --from "$work/ws/brief.json" --out "$work/ws/brief-f.json" > "$work/bfree.json"

# --- the refusals ----------------------------------------------------------
# An UNSIGNED index is not an edit: it cannot be told from a fresh selection.
if python3 "$D" brief --answer "$work/a-unsigned.json" --map "$work/map.json" \
     --from "$work/ws/brief.json" --out "$work/ws/x.json" >/dev/null 2>"$work/e-unsigned"; then
  err "an unsigned index was accepted as an edit"
else
  grep -q 'carries no + or' "$work/e-unsigned" \
    && ok "an unsigned index is refused rather than guessed at" \
    || err "wrong unsigned behaviour: $(cat "$work/e-unsigned")"
fi

# AC4 — an edit may not reach across workspaces. This is the whole difference
# between within-sitting retention and a cross-invocation cache.
if python3 "$D" brief --answer "$work/a-edit.json" --map "$work/map.json" \
     --from "$work/ws/brief.json" --out "$work/other-ws/brief.json" \
     >/dev/null 2>"$work/e-cross"; then
  err "an edit reached across run workspaces — retention is not within-sitting"
else
  grep -q 'WITHIN-SITTING' "$work/e-cross" \
    && grep -q 'never-read-back' "$work/e-cross" \
    && ok "an edit across workspaces is refused, with the reason named" \
    || err "wrong cross-workspace behaviour: $(cat "$work/e-cross")"
fi

# AC6 — the ANSWER's pin discipline is unchanged by the edit path.
if python3 "$D" brief --answer "$work/a-stale.json" --map "$work/map.json" \
     --from "$work/ws/brief.json" --out "$work/ws/x.json" \
     >/dev/null 2>"$work/e-stale"; then
  err "an edit carrying a stale pin produced a recomposition"
else
  grep -q 'pin mismatch' "$work/e-stale" && grep -q 'deadbeef' "$work/e-stale" \
    && grep -q "$mappin" "$work/e-stale" \
    && ok "an edit with a stale pin is refused, both pins named" \
    || err "wrong stale-pin behaviour: $(cat "$work/e-stale")"
fi

# AC6 — and the pin of the composition BEING EDITED is checked too: its
# indexes were resolved at that pin. sed, not an interpreter, so the check
# keeps its INNER_MS headroom.
sed "s/$mappin/deadbeefdead/g" "$work/ws/brief.json" > "$work/ws/brief-old.json"
if python3 "$D" brief --answer "$work/a-edit.json" --map "$work/map.json" \
     --from "$work/ws/brief-old.json" --out "$work/ws/x.json" \
     >/dev/null 2>"$work/e-base"; then
  err "a composition pinned elsewhere was edited anyway"
else
  grep -q 'the brief being edited was composed at' "$work/e-base" \
    && ok "editing a composition from another pin is refused" \
    || err "wrong base-pin behaviour: $(cat "$work/e-base")"
fi

# --- one assertion run over the produced files (#950 batching) --------------
python3 - "$work" "$mappin" <<'PYEOF' || fail=1
import json, os, sys
w, mappin = sys.argv[1], sys.argv[2]
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg,
          file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

b1 = json.load(open(w + "/b1.json"))
b2 = json.load(open(w + "/b2.json"))
b3 = json.load(open(w + "/b3.json"))

# --- AC1 — an edit-set option class exists at the gate ---------------------
it = b1.get("iteration") or {}
opt = it.get("option") or {}
check("+L" in opt.get("label", "") and "recompose" in opt.get("label", ""),
      "the gate offers the edit-set option class, +Lxx −Lyy → recompose")
check(opt.get("editable") == b1["indexes"] and "edit" in (opt.get("answer") or {}),
      "the option names the set it edits and the form the answer takes")
check("--from" in (opt.get("command") or ""),
      "the option carries the move itself, not a description of one")
check(bool(it.get("line")), "the gate states where in the loop the owner is")

# --- AC2 — each recomposition is pinned to its own member set --------------
a, c = b1["indexes"][0], b2["indexes"][-1]
check(b2["indexes"] == [b1["indexes"][1], c] and a not in b2["indexes"],
      "the edit drops and adds exactly what the owner named")
check(b2["recomposition"]["over"] == b2["indexes"],
      "the recomposition is over the EDITED set, and nothing wider")
check([m["index"] for m in b2["members"]] == b2["indexes"],
      "the new composition records the new member set")
check(b2["pins"]["terrain"] == mappin and b2["pin"] == mappin,
      "the new composition records its pins, as any composition does")
check(len(b2["recomposition"]["claims"]) == len(b2["indexes"])
      and all(cl in b2["brief"] for cl in b2["recomposition"]["claims"]),
      "the recomposition inputs are the members' served claims and nothing "
      "else — a composer at the gate cannot widen the scope")
check(b2["brief"] != b1["brief"],
      "a set change is a GATE EVENT: the claim recomposes, never carries over")
check("through the on-call retro" in b2["brief"]
      and "inherited" in (b2.get("edit") or {}).get("note", ""),
      "the owner's angle survives an edit they did not restate, disclosed")

# --- AC3 — prior compositions are retained and visible ---------------------
chain = (b3.get("iteration") or {}).get("compositions") or []
check([r["n"] for r in chain] == [1, 2, 3],
      "three compositions in one sitting, all three retained")
check([r["indexes"] for r in chain] == [b1["indexes"], b2["indexes"],
                                        b3["indexes"]],
      "each retained composition carries the set it was composed over")
check(all(r["brief"] for r in chain) and len({r["brief"] for r in chain}) == 3,
      "the owner compares THESES, not just member lists")
check(chain[1]["edit"]["drop"] == [a] and chain[2]["artifact"]
      == os.path.join(w, "ws", "brief-3.json"),
      "the chain records what each edit changed and where each brief lives")

# --- AC4 — retention is not a cache ---------------------------------------
check((b1["iteration"]["n"], len(b1["iteration"]["compositions"])) == (1, 1),
      "a fresh invocation starts with an empty chain — nothing carried in")
check("sitting" in (b3["iteration"].get("retention") or "")
      and "cache" in b3["iteration"]["retention"],
      "the retention states its scope, so it does not read as a cache")
src = open("scripts/topic-map-directions.py", encoding="utf-8").read()
check("def read_brief_artifact(" in src
      and not any(t in src for t in ("read_view(", "load_view(", "VIEW_CACHE")),
      "the loop added no second reader and no rendering cache")
check(json.load(open(w + "/ws/brief-2.json"))["iteration"]["n"] == 2,
      "the chain lives in the workspace's own artifacts, nowhere else")

# --- AC5 — free text still wins -------------------------------------------
bf = json.load(open(w + "/bfree.json"))
check(bf["brief"] == "my own direction, in my own words"
      and bf["origin"] == "free-form",
      "free text beats an edit, unchanged from before the loop existed")
check("iteration" not in bf and "edit" not in bf,
      "a free-form brief claims no member set to edit")

# --- AC6 — pin discipline is unchanged ------------------------------------
body = src.split("def _base_composition_pin")[1].split("\ndef ")[0]
check("_which_half_moved(" in body,
      "the base-pin refusal routes through _which_half_moved")
msg = open(w + "/e-base", encoding="utf-8").read()
check("Moved:" in msg or "not recorded in the selection" in msg
      or "Neither recorded half differs" in msg,
      "the refusal says which half of the composite pin moved, or says "
      "plainly that it cannot be named")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

[ "$fail" -eq 0 ] && printf '\nAll %s checks passed.\n' "$0" \
  || { printf '\n%s FAILED.\n' "$0" >&2; exit 1; }
