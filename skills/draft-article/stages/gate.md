<!-- stages/gate.md — draft-article stage companion (Story 19.3, #744/#740). Loaded on entry to this stage by the
     SKILL.md dispatcher; carries the stage's full operating detail,
     moved verbatim from the pre-split SKILL.md. -->

## Stage 3→4 — mandatory quality gate (Story 11.4)

Before the draft reaches the owner's verification pass, it must **pass the
article-quality gate** ([`quality-rubric.md`](../quality-rubric.md)). This is a
**stage-progression precondition** — like `verify-markers`, not an advisory
review finding: **Stage 3 does not complete until the gate passes**, so the
owner's ~4-minute budget never lands on a draft that reads like a stitched fact
sheet.

**Strengthened for the argument plan (#440/#434).** The gate is now a real
second-net *before* review, not after: the **narrative-arc dimension fails**
stitched-fact-sheet and **per-lesson-skeleton** drafts (a framework skeleton
reproduced verbatim per lesson), and a **plan-conformance** check requires the
draft to advance the argument plan's thesis (Stage-3 sub-step above). A
mechanical **per-lesson skeleton detector** (an identical `##` heading repeated
≥3×) is the zero-token backstop; the dim1 judge owns the varied-structure and
plan-conformance judgment. **This contract lives in three enforcement copies
that move in lockstep** — `scripts/draft-pipeline.py` (the mechanical
skeleton/stitched checks), [`quality-rubric.md`](../quality-rubric.md) (the dim1
contract the judge grades against), and this section — a change to one without
the others is a defect.

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py quality-gate \
  --draft <draft> --map "$WS/provenance-map.txt" --judge "$WS/rubric-verdicts.txt" \
  --framework-file "$FRAMEWORK_FILE" --state "$WS/checkpoint.json"
```

- **Per-section minimum evidence types are checked mechanically here (Story
  13.90, #416):** pass `--framework-file` (the run state's `framework_file`)
  and `--state` (the checkpoint carrying the fact sheet) so the gate verifies
  every slot carrying an authored `[EVIDENCE: …]` tag against the fact-sheet
  KINDs anchored into that section. **Two failure classes, routed differently
  (Story 19.12, #750):** `classification: "section-not-found"` means the join
  never located the section — a **draft-shape defect** (renamed heading) whose
  `upstream` names the expected slot key and the actual headings; repair it
  with the **heading fix**, never an `ask` elicitation — the evidence may be
  present under the wrong heading, and re-eliciting it is the incident this
  class exists to prevent. `classification: "missing-input"`
  (`section_present: true`) is the genuine evidence gap — its ready-made
  `upstream` line routes through `repair-hop` (below). In neither case
  backfill the section with unrelated factual material, and never report
  success past an unresolved finding. An unrepaired
  absence after the shared two-cycle bound surfaces as a publish blocker
  naming the section and the missing type. The gate **fails closed** (exit
  2) if the framework declares types but `--map`/`--state` are missing.
- **Dimension 4 (readability mechanics) is checked mechanically** here (zero
  tokens): sentence/paragraph-length distributions, heading density, and — from
  the provenance map — the **stitched-fact-sheet** signature (wall-to-wall
  `sourced` claims, no `derived`/`narration` tissue).
- **Audience presence is checked mechanically here too (Story 13.41):** an
  absent or unfilled `audience` fails the gate — the named reader must be set at
  stage-3 fill before the draft can progress.
- **Dimensions 1–2** are judged by **one single-pass cheap-tier rubric judge**
  emitting **pass/fail per dimension + failing locations, no rewritten text**;
  its verdicts feed `--judge`. **Verdict grammar (exact — instruct the judge
  verbatim, #303):** one line per dimension, `dim1: pass|fail [locations]` and
  `dim2: …` — the literal keys, never prose forms like `dimension 1: pass`.
  **Instruct the judge that dimensions 1–2 own only narrative/flow (Story
  13.66):** a dim1/dim2 finding must cite a narrative-arc or paragraph-flow
  defect, **never a sentence- or paragraph-length artifact** — length is
  dimension 4's (mechanical), and a sentence split/merge made to satisfy dim4
  is neutral for dim1/dim2. This is the rubric's dimension-separation contract
  ([`quality-rubric.md`](../quality-rubric.md)) and is what lets the second-cycle
  delta re-check converge. The
  gate refuses an unparseable judge file with a named error (exit 2) before
  judging anything; re-spawn the judge with the grammar restated rather than
  treating that error as a quality failure — it does not consume a revision
  cycle.
- **Dimension 3 is mechanical (#305)** — a deterministic scan over repo-internal
  vocabulary against the rubric's written introduction contract, emitting the
  **complete** violation set in one verdict, so one revision can clear the
  dimension inside the D5 bound. Pass the audience's known terms once, from the
  ratified audience answer, so audience judgment enters as owner-ratified data
  rather than being re-judged every pass:

  ```
  --audience-known "term one,term two"
  ```

  The judge may still offer a `dim3:` line; it is accepted and recorded as an
  **advisory** in the gate's `advisories` (informational bucket) — it never
  gates. Before #305 dim3 was an unpinned judgment reported one item per pass:
  four cycles over one draft named twelve terms and never passed, because each
  fix re-litigated what "introduced" means. Like `verify-provenance` (NFR13), this judge runs
  in a **fresh subagent that never saw the drafting turn** — spawn it with the
  harness Task tool, never inline; hand it only the draft, the rubric, and the
  provenance map, never the drafting rationale.
  So the drafting context never grades its own rubric pass. (These spawns cost
  turns against the pipeline budget — see #118.)

**On failure — bounded retry, then surface (never silent):**

1. Stage 3 **revises against the named failing dimensions only** (Read the
   current draft and provenance map before re-writing either — the
   artifact-write precondition; every cycle here is an overwrite), then re-runs
   **both** the quality gate **and** `verify-provenance` — readability revision
   is exactly where an unmarked claim would re-enter, so both gates run every
   cycle.
   - **The second cycle is a bounded delta re-check (#349, Story 13.65).** Pass
     `--cycle 2 --prior-locations "<cycle-1 dim1/dim2 failing locations>"`. The
     mechanical dims (3–4) re-run in full — they can raise a new finding — but a
     dim1/dim2 judge `fail` at a location cycle 1 never flagged is **suppressed
     as interpretive drift**, so revision converges instead of the judge naming
     a fresh 5-finding set each round. **Isolation is preserved**: hand the
     cycle-2 judge cycle-1's failing **locations** as its scope, never prior
     verdicts — spawn it in a fresh subagent as always. The gate output records
     what it suppressed under `delta_recheck` for the audit trail.

     ```
     python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py quality-gate \
       --draft <draft> --map "$WS/provenance-map.txt" --judge "$WS/rubric-verdicts.txt" \
       --framework-file "$FRAMEWORK_FILE" --state "$WS/checkpoint.json" \
       --cycle 2 --prior-locations "Section 2, para 3; Section 4"
     ```
2. **At most 2 revision cycles.** If the gate still fails after two, the failure
   is surfaced as a **publish blocker** in the completion summary (FR20 bucket)
   naming the **failing dimensions and locations** — never silently retried,
   never waived.
3. A revision **never silently alters or drops owner-approved content** (approved
   interview answers used as sourced claims, approved visuals) (NFR12); a change
   that would touch it surfaces to the owner instead (same principle as
   ">1 rewrite → new interview question").

**Missing-input repair hop (SPEC-article-draft-pipeline; Story 13.63).** A
review or quality-gate finding classified **missing-input** — an evidence gap
prose cannot fix (review Story 13.62) — does not route to an edit. It routes
back **one bounded hop** to the upstream remediation the finding names, then
re-enters the pipeline:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py repair-hop \
  --upstream "examine <the claim to ground>"   # or: "ask <one bounded question>"
```

**Evidence-type absences build episodes on the hop (Story 13.91, #417).**
When the missing-input finding came from the gate's evidence-type check
(`evidence_types.missing_input[]`, Story 13.90), do not go straight to the
generic `ask` — construct candidate episodes from what harvest already
captured:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py episode-candidates \
  --state "$WS/checkpoint.json" --section "<failing section>"
```

- The command reads **only the fact sheet** (never a source — the Stage-1
  scope boundary holds on the hop) and groups event-kind facts by source
  file, with same-source result/number/quote facts as support. Each
  candidate's `frame` is null: **author the one-line narrative frame
  yourself, from the grouped claims only** — compression, never new
  causality/significance (a frame asserting more than its constituents is
  invented evidence).
- Present **one** owner question (proposal contract, in-conversation): every
  candidate as an option — frame first, constituent pointers collapsed — plus
  an explicit decline. One question total, never one per candidate; this IS
  the hop's single bounded elicitation, so it counts against the same
  two-cycle bound.
- On selection, record it:

  ```
  python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py episode-select \
    --state "$WS/checkpoint.json" --frame "<approved one-line frame>" \
    --pointers "<primary>,<constituent>,…"
  ```

  The selected episode enters the fact sheet as a pinned entry (claim =
  frame, SOURCE = primary constituent, KIND `event` — harvest grammar
  unchanged); checkpoint the printed state, re-enter stage-3 fill, and the
  re-run gate can now satisfy the section's declared type.
- **Decline-all, or `episode-candidates` reports no candidates
  (`action: publish-blocker-path`):** the absence follows Story 13.90's
  publish-blocker semantics — surface it in the completion summary naming
  the section and missing type; never loop, never open-ended re-harvest.

- `examine <claim>` → run **one examination** for the named claim
  ([`examine.md`](examine.md) — harvest is retired, #1182: `next_stage: fill`,
  the re-grounding happens inside the fill, never a stage re-entry); the pin
  is recorded at the read (declared-scope boundary, derived `examine_scope`
  refusal and pin rules unchanged), and a policy line never becomes a SOURCE.
  The legacy `re-harvest <target>` spelling maps to this route, disclosed.
- `ask <question>` → re-enter the **interview** with exactly one owner-facing
  question under the proposal contract; the answer records as owner judgment
  (interview provenance), never a SOURCE.

This is the **only** backward edge to grounding/interview beyond the rewrite
route above, and it counts against the **same two-cycle bound** as
rewrites/gate revisions. Pass the cycles already spent on this draft as
`--cycle N`; when the cap is reached the command emits a **publish blocker**
(`action: publish-blocker`, `publishable: false`) instead of a third hop — the
unrepaired missing-input gap routes to the completion summary's
publish-blocker bucket (CAP-6), exactly as an unresolved rubric/config blocker
forces "not publishable":

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py repair-hop \
  --upstream "examine <claim>" --cycle 2   # -> publish-blocker, no third hop
```

A within-budget hop returns the incremented `cycle` so the next stage carries
it forward. A hop interrupted at the turn ceiling resumes from the checkpoint
like any stage.

A **fact-sheet-stitched draft fails** this gate (dimension 4) and does **not**
reach Stage 4 unrevised.


---

**Gate exit — two directions.** This is the pipeline's one non-linear
transition, so it names both:

- **Pass → Stage 4.** Read [`stage4.md`](stage4.md) and run
  `draft-pipeline.py verify <draft>`, driving `verify-markers --count` to 0.
- **Fail → back to Stage 3.** Return to [`stage3.md`](stage3.md) for the
  bounded repair hop, then re-run the gate. The cycle is bounded; a
  fact-sheet-stitched draft does not reach Stage 4 unrevised.
