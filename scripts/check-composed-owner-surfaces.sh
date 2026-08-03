#!/bin/sh
# check-composed-owner-surfaces.sh — the owner surface is COMPOSED, not
# assembled at relay time (Story 20.123, #1137).
#
# tier: inner
# parallel-safe
# covers: scripts/owner_surface.py skills/completion-summary.md scripts/draft_gates.py
# grep-binding: token — the one skill grep matches the composer call
#   fragment ('owner_surface as o'), code-shaped, not relocatable prose.
# removal-signal: this check retires when the relay layer itself becomes
#   constrainable — i.e. when the harness can guarantee that a composed block
#   reaches the owner unmodified. At that point the composer is enforced at the
#   layer where the rule breaks and asserting its existence here buys nothing.
#   It ALSO retires if the completion summary stops being a composed artifact
#   by a later ratified decision, in which case this check is the thing that
#   should fail loudly rather than be quietly deleted.
#
# WHY THIS EXISTS. `SPEC-writing-assistant` §Owner-surface register fixes the
# remedy order as CONSTRAIN -> DETECT -> ENUMERATE and prohibits an enumerated
# denial list as the response to a register leak. The typed value (#1117) was
# necessary and not sufficient: a conformant value can still be surrounded by
# free-composed prose, which is what the 2026-08-01 run did on three surfaces.
#
# WHAT IS ASSERTED is the CONSTRAIN half only — that a composer exists, that it
# emits every bucket including the empty ones, and that the skill instruction
# NAMES it rather than describing a shape for the relay to reproduce. This adds
# no per-surface denial member: the clause's own diagnostic is a suite growing
# one member per incident, and one composer assertion is not that.
set -eu
fail=0
ok()  { printf 'ok:   %s\n' "$1"; }
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

python3 - <<'PY' || fail=1
import sys
sys.path.insert(0, "scripts")
import owner_surface as o

bad = []
def need(c, m):
    if not c: bad.append(m)

need(hasattr(o, "completion_summary"), "no composed completion summary exists")
need(o.BUCKETS == ("informational notes", "publish blockers", "optional cleanup"),
     "the bucket vocabulary is not the one the contract mandates")

out = o.completion_summary("Harvest", notes=["a"], blockers=[], cleanup=[])
for b in o.BUCKETS:
    need(b in out, f"bucket {b!r} is missing from a composed summary")
need("publish blockers: none" in out,
     "an EMPTY bucket vanished — a bucket that disappears when empty is "
     "indistinguishable from one nobody filled")
need(out.endswith("\n"), "the block is not a complete, printable string")

nxt = o.completion_summary("Harvest", next_step="Continue, or stop?")
need("Continue, or stop?" in nxt,
     "the next step is not carried by the composed block")

for m in bad:
    print("FAIL: %s" % m, file=sys.stderr)
sys.exit(1 if bad else 0)
PY
[ "$fail" -eq 0 ] && ok "the completion summary is composed, with every bucket rendered"

# The instruction NAMES the composer. A skill that describes the shape leaves a
# free-form string; naming the call is what removes it.
grep -q 'owner_surface as o' skills/completion-summary.md \
  && ok "completion-summary.md names the composer rather than describing it" \
  || err "completion-summary.md still only describes the summary's shape"

# AC3, asserted as the DESIGN it already is: a gate too large for the host
# control renders as a block and carries its own banner and reply line, so the
# relay has nothing to invent. A selection-control gate deliberately has none —
# the host renders its own frame — and `render_form` refuses them there.
# The block threshold is the margin's (#1206): the five-option intent gate is
# a selection with its overflow disclosed, and only a set above the margin
# still owes the block's own fields.
python3 - <<'PY' || fail=1
import sys
sys.path.insert(0, "scripts")
import draft_gates as dg

bad = []
labels = {f"f{i}": f"type {i}" for i in range(1, 6)}
item = dg.intent_gate(labels)["items"][0]
if item["render"]["control"] != "selection":
    bad.append("the five-option intent gate no longer renders as a selection "
               "with a disclosed overflow (#1206)")
if item["render"].get("overflow") != ["type 5"]:
    bad.append("the intent gate's fifth label is not the declared overflow")
big = dg.payload(where="w", why="y",
                 choices=[{"label": f"c{i}", "effect": "e"}
                          for i in range(7)],
                 banner="Choose one.", reply_line="Reply with one.")
item = big["items"][0]
if item["render"]["control"] != "block":
    bad.append("a seven-option gate no longer renders as a block — the "
               "above-margin case is not reopened (#1206)")
for k in ("banner", "reply_line"):
    if not item["render"].get(k):
        bad.append(f"a block gate reached the owner with no {k} — the relay "
                   f"would have to compose one")
try:
    dg.payload(where="w", why="y",
               choices=[{"label": "a", "effect": "e"},
                        {"label": "b", "effect": "f"}],
               gate="intent", banner="x", reply_line="y")
    bad.append("a selection-control gate accepted a banner; the host renders "
               "its own frame and a second one is free composition")
except ValueError:
    pass
for m in bad:
    print("FAIL: %s" % m, file=sys.stderr)
sys.exit(1 if bad else 0)
PY
[ "$fail" -eq 0 ] && ok "a block gate carries its own banner and reply line; a selection gate refuses them"

# THE HANDOVER IS A POSITION RULE (Story 20.194, #1335). The paths were emitted
# on the run that reported them missing, so presence is not the property: what
# is asserted is that both persisted paths are the FIRST thing in the block,
# ahead of every bucket, rendered from `complete`'s JSON, and that a failed
# `complete` produces no path line at all.
python3 - <<'PY' || fail=1
import json, sys
sys.path.insert(0, "scripts")
import owner_surface as o
import draft_gates as dg

bad = []
D, P = "/w/articles/drafts/foo.md", "/w/articles/plans/foo.md"
cj = json.dumps({"stage": "complete",
                 "products": {"canonical": {"path": D}, "plan": {"path": P}}})

out = o.completion_summary("Draft", notes=["n"], blockers=[], cleanup=[],
                           next_step="Review, or stop?", complete_json=cj)
head = out.split("\n\n", 1)[0]
if D not in head or P not in head:
    bad.append("the persisted product paths are not the summary's FIRST block "
               "— position, not presence, is what #1335 reports")
for path in (D, P):
    if path + "\n" not in out and not out.rstrip().endswith(path):
        bad.append(f"{path} is not alone on its line")
if out.index(D) > out.index(o.BUCKETS[1]):
    bad.append("a bucket precedes the handover block — the ordering against "
               "publish blockers is declared, never incidental")

blocked = o.completion_summary("Draft", blockers=["[VERIFY] left"],
                               complete_json=cj)
if "1 publish blocker" not in blocked.split("\n\n", 1)[0]:
    bad.append("the handover block does not name the blocker count — a blocker "
               "outranks the handover and the tie-break must be visible")

try:
    o.completion_summary("Draft", complete_json="error: completion gate: ...")
    bad.append("a summary composed over a FAILED complete emitted a block — "
               "there is no completion to hand over")
except ValueError:
    pass
if o.product_handover(json.dumps({"products": {"canonical": {"path": D}}})):
    bad.append("a handover rendered with only one product path")

item = dg.review_entry_gate(D)["items"][0]
if D not in item["where"]:
    bad.append("the review/stop gate's `where` does not carry the draft path — "
               "the handover must ride a payload the carrier can observe")

for m in bad:
    print("FAIL: %s" % m, file=sys.stderr)
sys.exit(1 if bad else 0)
PY
[ "$fail" -eq 0 ] && ok "both persisted paths head the summary, ordered ahead of the buckets, and the review/stop gate carries the draft path"

[ "$fail" -eq 0 ] && printf '\nAll %s checks passed.\n' "$0" \
  || { printf '\n%s FAILED.\n' "$0" >&2; exit 1; }
