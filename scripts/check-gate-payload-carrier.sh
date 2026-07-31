#!/usr/bin/env sh
# parallel-safe
# tier: inner
# covers: scripts/draft_gates.py scripts/draft_resume.py
# removal-signal: every owner-facing gate is emitted through one typed
#   composition point (the seam SPEC-writing-assistant's owner-surface register
#   clause leaves open) — at that point this check's subject becomes the seam
#   rather than the individual builders, and it retires with them.
# check-gate-payload-carrier.sh — a gate emits its question as DATA, in the
# shape that already ships (Story 20.103, #1081).
#
# THE ABSENCE IS WHAT THIS ASSERTS. An obligation produces no event to hook, so
# there is nothing to catch in the act; what is checkable is that a surface
# which asks the owner something HAS an emitted payload, and that the payload
# passes the same validator every other proposal surface passes. This check
# deliberately reads NO reply prose — nothing in this repository can, which is
# exactly why the carrier sits at the composed artifact instead.
set -u
cd "$(dirname "$0")/.."
fail=0
ok()  { printf 'ok:   %s\n' "$1"; }
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

python3 - "$work" <<'PY' || { err "gate payloads did not build"; printf '\nFAILED.\n' >&2; exit 1; }
import importlib.util, json, os, sys
sys.path.insert(0, "scripts")
spec = importlib.util.spec_from_file_location("dp", "scripts/draft-pipeline.py")
dp = importlib.util.module_from_spec(spec); spec.loader.exec_module(dp)
from draft_gates import intent_gate
from draft_resume import confirmation
w = sys.argv[1]
json.dump(intent_gate(dp.INTENT_LABELS), open(os.path.join(w, "intent.json"), "w"))
json.dump(confirmation("20260718T000000-111111", "/ws", {"next_stage": "harvest"},
                       "started 14 days ago, on a different calendar day"),
          open(os.path.join(w, "resume.json"), "w"))
PY

# EVERY emitted gate passes the SHIPPED validator — not a private mirror of it.
for g in intent resume; do
  if python3 scripts/validate-proposal-payload.py "$work/$g.json" >/dev/null 2>"$work/$g.err"; then
    ok "the $g gate emits a PRESENTABLE payload (shipped validator, #1081)"
  else
    err "the $g gate's payload is blocked: $(head -2 "$work/$g.err" | tr '\n' ' ')"
  fi
done

python3 - "$work" <<'PY' || fail=1
import json, os, re, sys
w = sys.argv[1]
fail = 0


def check(cond, msg):
    global fail
    print(("ok:   " if cond else "FAIL: ") + msg,
          file=sys.stdout if cond else sys.stderr)
    if not cond:
        fail = 1


for name in ("intent", "resume"):
    item = json.load(open(os.path.join(w, name + ".json")))["items"][0]
    # OPTIONS PLUS FREE FORM, never options alone: options-only is a different
    # violation of the same clause that prose-only violates.
    check(item.get("free_text") is True,
          f"#1081: the {name} gate carries a free-text channel beside its "
          f"options")
    check(len(item.get("choices") or []) >= 2,
          f"#1081: ...and offers a real choice rather than one option")
    # NOTHING PRE-SELECTED. Rank is not pre-selection, and neither is order,
    # but a `selected`/`default` key would be.
    check(not any(k in c for c in item["choices"]
                  for k in ("selected", "default", "recommended")),
          f"#1081: ...with nothing pre-selected in the {name} gate")

# THE OWNER-FACING LABEL IS NEVER THE INTERNAL ALIAS. `f1`-`f5` are declared
# internal/expert aliases that never appear in owner-facing text, and building
# the choices from the mapping's KEYS is the obvious implementation that ships
# one to the single surface it is barred from.
blob = json.dumps(json.load(open(os.path.join(w, "intent.json"))))
check(not re.search(r"\bf[1-5]\b", blob),
      "#1081: the intent gate's owner-facing text carries no F-alias")

sys.exit(1 if fail else 0)
PY

[ "$fail" -eq 0 ] || { printf '\nFAILED.\n' >&2; exit 1; }
printf '\nAll gate-payload-carrier checks passed.\n'
