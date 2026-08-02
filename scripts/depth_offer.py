#!/usr/bin/env python3
"""The CAP-8 depth offer's wording, composed from state the run already holds
(Story 20.169, #1285).

WHY THIS IS A MODULE. `scripts/draft-pipeline.py` is at its ratchet ceiling and
the sanctioned remedy for that file is the per-stage command-module split (a
spec decision, #759). Rather than spend the last of its headroom on offer
prose, the composition lives here and the pipeline keeps the constants and two
one-line call sites.

WHAT CHANGED AND WHAT DID NOT. The offer read "How deep should this go — a
quick note, a standard piece, or a deep-dive?", a REGISTER axis CAP-8 does not
control; run 20260802T185710-622820 read it as licence to leave repo-internal
terms unexplained. Terminology is the rubric's depth-blind Dimension 3. The
directive moves SCOPE, so the WORDS changed and the SEMANTICS did not — UX
defines correctness.

WHAT IT COMPOSES FROM, AND WHAT IT DOES NOT PLUMB. The member count comes from
one `journey_arcs.arcs` record per brief member (`draft_brief.py`) or a folded
`members` list; the thesis is the brief text. Both are existing state reads.
The full terrain brief record does NOT cross into run state, so absent both the
generic wording stands rather than new plumbing being invented for it.
"""


def holders(state):
    """Both shapes a run's record travels in: the stage-0 run state, then a
    folded one — so a directive is never missed for travelling under a
    different key."""
    s = state if isinstance(state, dict) else {}
    return [h for h in (s, s.get("run_state")) if isinstance(h, dict)]


def offer_text(state, generic, split_hint_n):
    """The composed offer, or `generic` when the run holds fewer than two
    members — an abstract menu makes the owner guess what "standard" means for
    THIS material, which is the defect being repaired."""
    hs = holders(state)
    brief = next((h["brief"] for h in hs if isinstance(h.get("brief"), dict)), {})
    arcs = next((h["journey_arcs"]["arcs"] for h in hs
                 if isinstance((h.get("journey_arcs") or {}).get("arcs"), list)), [])
    n = len(brief["members"] if isinstance(brief.get("members"), list) else arcs)
    if n < 2:
        return generic
    txt = " ".join(str(brief.get("text") or "").split())
    under = (f", under the brief “{txt[:90].rstrip(' ,;.')}{'…' if len(txt) > 90 else ''}”"
             if txt else "")
    split = " — or split them across more than one article?" if n > split_hint_n else "?"
    return (f"{n} story elements are in scope{under}. How much of that should this article "
            f"carry — all {n} in one fuller article (deep-dive), the main ones (standard), or "
            f"a single point only (note){split} That is scope, not reading level: repo-internal "
            "terms are explained at first use whichever you pick. Or name a scope in one line.")
