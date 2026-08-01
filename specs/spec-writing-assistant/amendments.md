# SPEC-writing-assistant — ratified amendments, 2026-08-01 onward

Companion to `SPEC.md`: the dated, ratified amendment blockquotes of this
spec. **New amendments append here, newest-last** — `SPEC.md` carries the
pointer, never the blocks.

Amendments dated **2026-07-24 -> 2026-08-01** live in `amendments-2026-07-24--2026-08-01.md`, relocated verbatim on
2026-08-01 when this file crossed the era-split threshold declared in
`scripts/check-skill-budget.sh`. That file is **closed**; nothing appends to it.

The cut is **mechanical and is not a decision** (Story 20.88, #1046): the
threshold lives in the check, which is the single enforcement copy, so no
byte figure appears here or in any spec. Ratified text is never compacted
and no already-relocated text moves — the rule is prospective.

> **Amended 2026-08-02 (triage, #1206) — a closed set overflowing the control capacity by at most two renders as a SELECTION with a disclosed overflow, and permanent block form stops being the fate of a five-member ratified set.** The #1102 amendment fixed the host control's capacity at 2–4 options and declared `control: "block"` the conforming form above it — written for the ≈50-Strand terrain listing, and silently claiming the intent gate, whose ratified closed set is exactly five. The pipeline's most central closed choice was therefore **permanently** above capacity by one: block form was not a degraded path there but the only path, on every run, by construction — and the owner's standing ruling is that rule-conformant but bad-for-the-user is incorrect design. **The contract:** a payload whose choice count exceeds `CONTROL_CAPACITY` by **at most two** declares `control: "selection"` and carries `render.overflow: [<labels>]` — the top-ranked members fill the control with the recommendation first, and every overflow member is **named in the question text** and reachable through the control's built-in free-text entry: disclosed, never hidden. Above that margin, block form stands unchanged — the ≈50-Strand case that motivated it is not reopened. The carrier check extends from existence to this form: `check-gate-payload-carrier.sh` asserts `overflow` is declared only within the margin, that a declared overflow's members are each named in the question text, and that the recommendation still leads. Rank is not pre-selection, and the overflow member is a full citizen of the choice — only its entry path differs. **What would overturn this** is the observation the gate itself named: an owner repeatedly failing to find the overflow member, which would show disclosure-by-text is hiding in practice; the remaining move is the two-render split declined here for spending a second ask on a single-axis choice. Delivery: story 20.142.
