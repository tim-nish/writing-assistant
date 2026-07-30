#!/usr/bin/env sh
# parallel-safe
# check-terrain-decisions.sh — the decisions-shard join (Story 20.22, #851;
# SPEC-terrain CAP-2 as amended 2026-07-27, #850).
#
# The defect this guards (#850 D1): the ratified renderings existed and the
# consumer never asked for them, so the owner read raw recall-register text
# and indicted the hub's authoring. The join keys a topic decision line's
# trailing `(q_a/<batch> D<n> …)` pointer to the served shard's
# `## (q_a/<batch> D<n> · <date>)` heading. A missing rendering is an
# ABNORMAL condition, disclosed loudly (owner ruling, #850 D4) — and the raw
# topic line is NEVER presented as if it were a rendering.
#
# POSIX sh + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

M="scripts/terrain_map.py"
D="scripts/topic-map-directions.py"

python3 - "$M" "$D" <<'PYEOF' || fail=1
import importlib.util, sys
def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod
tm = load(sys.argv[1], "tm")
dv = load(sys.argv[2], "dv")
fail = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: fail.append(msg)

# --- the shard parser reads the served shape --------------------------------
shard = "\n".join([
    "pin: hub@abc1234",
    "=== gloss/decisions/workflow.md @ abc1234",
    "1: # Gloss — decisions: workflow",
    "3: Ratified plain-register renderings of decision lines.",
    "8: Regenerated: 2026-07-27 · 2 entries",
    "10: ---",
    "12: ## (q_a/2026-07-20-retry-budget D1 · 2026-07-20)",
    "14: Retries without a budget turn one slow dependency into an outage.",
    "15: The budget is declared once and enforced by the client.",
    "16: ",
    "18: ## (q_a/2026-07-21-oncall D3 · 2026-07-21)",
    "20: A rota nobody owns silently stops.",
])
entries = tm.parse_decision_shard(shard)
check(set(entries) == {"q_a/2026-07-20-retry-budget D1", "q_a/2026-07-21-oncall D3"},
      f"shard entries key on the provenance pointer ({sorted(entries)})")
check(entries["q_a/2026-07-20-retry-budget D1"]["gloss"].startswith("Retries without")
      and entries["q_a/2026-07-20-retry-budget D1"]["gloss"].endswith("the client."),
      "a multi-line rendering is carried whole, in order")
check(entries["q_a/2026-07-20-retry-budget D1"]["cite"]
      == "gloss/decisions/workflow.md:12@abc1234",
      "the cite points at the entry heading in the served shard")
check(tm.parse_decision_shard("miss: gloss --tag decisions/workflow") == {},
      "a served miss parses to no entries, never to invented ones")

# --- the pointer is captured from the topic line ----------------------------
served = [("5", "- 2026-07-20 — **Retries need a budget.** Because reasons. "
                "(q_a/2026-07-20-retry-budget D1)"),
          ("9", "- 2026-07-22 — **No pointer on this line.**")]
els = tm.parse_topic_elements("workflow", served, "abc1234")
check(els[0]["decision_pointer"] == "q_a/2026-07-20-retry-budget D1",
      "the join key is captured before the summary strips the pointer")
check(els[1]["decision_pointer"] is None,
      "a line with no D-numbered pointer stays pointerless, never guessed")

# --- the join: served -> quoted; absent -> abnormal, loud -------------------
tm.join_decision_gloss(els, {"workflow": entries}, {})
check(els[0]["gloss"].startswith("Retries without")
      and els[0]["gloss_cite"] == "gloss/decisions/workflow.md:12@abc1234",
      "a joined Strand carries the served rendering and its cite")
check(els[0]["gloss_unavailable"] is None,
      "a served rendering carries no absence disclosure")
check(els[1]["gloss"] is None
      and "abnormal condition to fix now" in els[1]["gloss_unavailable"],
      "an absent rendering is disclosed as the abnormal condition it is")
missed = tm.parse_topic_elements("orphan", served, "abc1234")
tm.join_decision_gloss(missed, {}, {"orphan": "gateway unreachable"})
check("gateway unreachable" in missed[0]["gloss_unavailable"]
      and "abnormal condition" in missed[0]["gloss_unavailable"],
      "a whole-shard miss names its reason inside the abnormal disclosure")

# --- the renderer: quotes the rendering, never the raw line -----------------
line = dv._element_direction(dict(els[0], kind="decision"))
check("Retries without a budget" in line and "not being served" not in line,
      "a joined decision row quotes the served rendering")
bare = dv._element_direction(dict(els[1], kind="decision"))
check(els[1]["summary"] not in bare and "abnormal condition" in bare,
      "an unjoined decision row discloses; the raw topic line never poses as "
      "a rendering")
sys.exit(1 if fail else 0)
PYEOF
[ $? -eq 0 ] || fail=1

if [ "$fail" -eq 0 ]; then
  printf '\nAll terrain-decisions checks passed (the join is loud, never silent).\n'
else
  printf '\nFAILED.\n' >&2
  exit 1
fi
