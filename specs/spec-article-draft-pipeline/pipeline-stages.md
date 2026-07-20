# Pipeline stages (companion to SPEC-article-draft-pipeline)

## Stage table

| # | Stage | Actor | Human time | Output |
|---|---|---|---|---|
| 0 | Invoke: `draft article <framework> from <sources>` (framework = F1–F4 from SPEC-article-frameworks; sources = paths/globs/commit ranges) | Owner | ~0 min | Run started |
| 1 | Harvest: read sources, extract candidate claims/results/numbers | AI | 0 | Fact sheet, every entry source-pointed (CAP-1) |
| 2 | Gap interview: candidates triaged (suppress / recommend / open); survivors presented as selective prompts with source-pointed recommended answers as defaults | AI asks; owner approves/modifies/replaces/skips (bullets for open questions) | ~5 min | Interview answers + interview journal (CAP-2) |
| 3 | Fill: populate the framework's slots from fact sheet + answers; frontmatter from the article schema; every sentence classed in the provenance map (sourced / derived / narration); inferred claims marked `[VERIFY]` | AI | 0 | Draft + provenance map (CAP-3) |
| 3→4 | Quality gate: four-dimension rubric + `verify-provenance`; fail → revise against named dimensions and re-run both, ≤2 cycles, then publish blocker (CAP-6) | AI | 0 | Gate-passing draft (CAP-7) |
| 4 | Verification pass: resolve `[VERIFY]` markers, veto off-voice text; >1 rewrite needed → new interview question, not editing | Owner | ~4 min | Draft ready for review |
| 5 | Variants: owner picks which platform variants to emit (in-conversation choice, never auto-emit); each variant is a projection of the canonical draft driven by its platform profile, with one lede-re-targeting proposal when the profile's audience/language differ | AI emits; owner chooses platforms + arbitrates the lede proposal | ~1 min (within the ≤10 budget) | Platform files per emission choice (CAP-4 → SPEC-platform-variants) |

Draft then exits this pipeline into SPEC-article-review.

**Stage 5 contract moved (2026-07-16).** The variant stage's full contract —
platform profiles as declared config, emission per publish decision, projection
with a single lede touchpoint, lint-sized per-variant checks — lives in
SPEC-platform-variants (`../spec-platform-variants/SPEC.md`), which wins where
this table and that spec disagree. The row above is the pipeline-level summary.

**Durability across the stage boundaries (added 2026-07-12).** Each stage
persists its completion state to the run workspace (`$WS`) alongside its
intermediates, so a re-invocation resumes from the last completed stage rather
than restarting — the turn/compute budget is a real ceiling even though
wall-clock is unconstrained (SPEC constraints). A stage that nears the ceiling
surfaces a budget-triage signal before hard failure, and a resumed or partial
run reports its last completed stage and resume path in the completion summary
(CAP-6). The AI-actor stages are the checkpoint boundaries.

**Automatic resumption + round-trip economy (added 2026-07-13, #142).** Resumption
is **automatic, not opt-in**: on invocation the pipeline detects an in-progress
run for the workspace and continues from the last checkpoint without the agent
deciding to resume; a large multi-source draft completing across several
invocations is the normal model, not a failure. Each stage also folds its
mechanical checks into as few script invocations as its contract allows (config
validation, path resolution, and source enumeration need not be separate
round-trips when one call can carry the others), so a realistic run makes
progress per turn instead of exhausting the budget on orchestration overhead.

## Fact-sheet entry format (stage 1)

```
- CLAIM: <one sentence>
  SOURCE: <path:line@sha | commit sha | URL>
  KIND: result | decision | number | quote | event | chronology | motivation | cost | reversal
```

The KIND set is a **closed set of nine** (amended 2026-07-20, #438): the five
atomic kinds `result | decision | number | quote | event` plus four
**narrative** kinds `chronology | motivation | cost | reversal`. The narrative
kinds admit **pointer-backed** narrative material — a timeline (`chronology`),
the *why*/problem behind work or a **free-standing** decision rationale
(`motivation`), a recorded price or tradeoff (`cost`), a superseded position
(`reversal`) — that was previously routed off the sheet into NEEDS-OWNER.
Rationale bound to a specific harvested `decision` fact may stay with the atomic
`decision` kind; the narrative kind is not forced where the atomic one already
fits. The set stays **fixed at nine** — no subtype axis, no free-text kind;
material fitting none of the nine is a spec decision, never an in-place widening.

SOURCE is a **single** commit-pinned line (`path:line@sha`, not a range) for
`result`, `decision`, `number`, and `event`; `quote` **and the four narrative
kinds** may span consecutive physical lines (`path:line1-line2@sha`) when the
material does (e.g. a wrapped table cell, a rationale paragraph, a chronology
block), so a natural boundary is never forced to fold in unrelated adjacent
text.
Quote matching is **whitespace-normalized** (amended 2026-07-13, #154): the
CLAIM matches when its whitespace-collapsed text is a contiguous span of the
whitespace-collapsed source, so a sentence that wraps is quotable by its real
boundary while still carrying no text beyond the source
(`skills/harvest/SKILL.md` §3).

Entries the AI wants to use but cannot source go to a `NEEDS-OWNER` list feeding stage 2 — never into the draft unmarked.

The fact sheet and `NEEDS-OWNER` list are written to the run workspace
(`docs/storage-architecture.md` D2), never into the host working tree — the
location is contract, not agent default.

## Interview question bank (stage 2)

**Policy-seeded candidates (amended 2026-07-14, SPEC-policy-source-seam / #188).**
When the host repo declares an optional `policy_source`, stage 2 first probes
the owner's policy repo through the bounded, pinned, read-only reader
(`GLOSSARY.md`, `LESSONS.md`, ≤2 track-matched `topics/*.md`; whitelist in
code, the hub's history archive unreadable) and authors **tension items** — schema-enforced
questions typed `contradiction | ambiguity | missing-rationale |
reversal-candidate`, each carrying a `seed {quote, pointer: file:line@commit}`
— validated **before** triage (`validate-interview-items.py`, rejection
classes R1–R5). Policy content seeds candidate **questions only**: triage and
recommendation generation below remain a view over harvest output, and a
policy seed can never supply or pre-fill an answer. Validated items join the
asked set as `open`/`policy-seed` questions; an absent `policy_source` is
silent, an unusable one logs one line and the interview proceeds generically
(the seam's own contract lives in SPEC-policy-source-seam).

Every candidate question is triaged against the harvest output — the fact
sheet and NEEDS-OWNER list, reading nothing else (`docs/interview-architecture.md` D1):

- **suppress** when fact-sheet entries fully cover the question's
  information need — the question never reaches the owner;
- **recommend** when entries provide a groundable candidate answer
  (including recorded owner judgments in sources) — the source-pointed
  candidate is presented as the default choice; NEEDS-OWNER re-raises are
  always recommended (confirm/deny the claim, its context as grounding);
- **open** when neither — genuinely owner-only knowledge, answered as a
  bullet.

Pick ≤5 survivors — confirmed NEEDS-OWNER gaps first, then policy-seeded
tension questions, then generic open (amended 2026-07-14: seeded items share
the same ≤5 cap, so seeds *displace* the lowest-priority generic questions
rather than adding to them) — prioritized top-down; tailor wording to the
framework's GATE slots:

1. What surprised you most while building this? (feeds F2 slot 3 / F1 slot 4)
2. Which single result or number matters most, and why that one? (feeds evidence GATE slots)
3. What would you warn a reader about before they adopt this? (feeds limits/boundaries slots)
4. What did this decision cost you — what did you give up? (feeds tradeoff slots)
5. Who exactly is this article for, and what should they do after reading? (feeds hook + pointer block)
6. What opinion in this piece are you willing to defend in comments? (voice anchor)
7. What would you do differently if starting over? (feeds F2 slot 6)

## Interview journal (stage 2)

Written to the run workspace (`docs/storage-architecture.md` D2). One line
per triaged question — format illustrative, the recorded fields are the
contract:

```
Q1: asked   outcome=recommended  rationale=owner-judgment      rec<-fs-22,fs-31  disposition=approved
Q2: asked   outcome=recommended  rationale=needs-owner-reraise rec<-no-17        disposition=modified
Q3: asked   outcome=open         rationale=topic-absent                          disposition=answered
Q6: suppressed                   covered-by=fs-08,fs-12
```

- Every **asked** question records its survival rationale (`topic-absent` |
  `needs-owner-reraise` | `owner-judgment` | `policy-seed`), the
  recommendation's grounding pointers (when recommended), the **seed
  pointer(s)** (when policy-seeded — the `seed<-` field, parallel to `rec<-`;
  amended 2026-07-14, SPEC-policy-source-seam), and the owner's disposition.
- Every **suppressed** question records its covering entries.
- A candidate that survived triage but fell to the ≤5 budget is journaled as
  **capped** — recorded without a disposition, since the owner never saw it
  (added 2026-07-14: policy seeds make >5 survivors possible for the first
  time).
- The journal **ends with the `consulted:` line** (SPEC-policy-source-seam
  CAP-5): the pin plus a seed → question map for a seeded run, or
  `consulted: none (policy_source unset | unavailable: <reason>)` — every
  interview run states its policy provenance.
- Answers carry their disposition into stage 3's provenance: an **approved**
  answer keeps its source pointers and grounds sourced claims like a
  fact-sheet entry; **modified**/**replaced** answers are interview-sourced
  owner judgment (harness classes, `docs/harness-architecture.md` D1).
- A **skip** records intent only — its slot effect is the framework slot's
  declared contract (SPEC-article-frameworks), resolved at stage 3, never
  by the interview engine.

The journal is the boundary diagnostic: a question asked that sources could
answer, or a suppression that should not have happened, is attributable from
run state (harvest scope gap vs. de-dup miss vs. triage error) instead of
being discovered by the owner mid-interview.

## Provenance map (stage 3)

Sidecar file in the run workspace (`docs/storage-architecture.md` D2), never
inline — the draft body stays clean for variants and review. One line per
sentence, keyed by paragraph/sentence position:

```
P4.S2: derived <- fs-12, fs-14
P4.S3: narration
P4.S4: sourced <- fs-15
P4.S5: verify            # sentence carries an inline [VERIFY] in the draft body
```

`verify-provenance` runs independent of the drafting context and checks:

- every `narration` sentence passes the **falsifiability test** (no reviewer
  with source access could mark it false); one that asserts a checkable
  proposition is a gate failure;
- every `derived` claim's pointers resolve to fact-sheet entries, and the
  sentence only **compresses, combines, or restates** them — introducing new
  causality, significance, evaluation, comparison, intent, or scope is a
  gate failure (the sentence must be reclassed `verify` or rerouted to the
  interview).

Scope: the three classes apply to prose sentences. Visual elements (diagram
nodes/edges, table cells, captions) keep SPEC-article-visuals CAP-3's binary
rule — source-pointed or `[VERIFY]` — and stay outside the provenance map;
diagrams are claims by that spec's contract, so they get no narration class.

## Quality gate (stage 3→4, CAP-7)

- Rubric dimensions: **1 narrative arc** (one claim, every section advances
  it — section-level deletion probe), **2 paragraph flow** (one idea per
  paragraph, topic sentence first, no orphan facts), **3 explanation
  calibration** (repo-internal terms introduced before first load-bearing
  use, for the framework hook's audience), **4 readability mechanics**
  (sentence/paragraph-length distributions, heading density, per-section
  quote density from the provenance map).
- Dimension 4 is mechanical (lint-class, zero tokens); dimensions 1–3 are
  judged by one single-pass cheap-tier rubric judge **run in a subagent that
  never saw the drafting turn** (same isolation as `verify-provenance`, NFR13,
  so the drafting context never grades its own rubric pass): pass/fail per
  dimension + failing locations, findings format, no rewritten text.
- Fail → stage 3 revises against the named dimensions and re-runs the
  rubric **and** `verify-provenance` (readability revision is where unmarked
  claims would re-enter). At most 2 revision cycles; then the failure lands
  in the completion summary's publish-blocker bucket with dimensions and
  locations.
- Revisions rework prose only. Owner-approved content — approved visuals
  (SPEC-article-visuals CAP-2) and interview answers used as sourced claims
  — is never silently altered or dropped by a revision cycle; a revision
  that needs to change it surfaces the need to the owner instead (same
  principle as ">1 rewrite → new interview question").
- The rubric is a versioned plugin asset; exemplar-derived threshold tuning
  updates the asset, not this contract.

## `[VERIFY]` marker convention (stages 3–4)

- Inline, adjacent to the claim: `The retry storm doubled token spend [VERIFY: inferred from logs 6/12–6/14, no exact figure found].`
- The bracket names *why* it's unverified so the owner verifies instead of re-deriving.
- Stage 4 exit criterion: zero `[VERIFY]` markers remain (each resolved to a source, an owner confirmation, or deletion of the claim).
