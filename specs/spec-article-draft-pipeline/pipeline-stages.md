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
| 5 | Variants: dev.to copy (`canonical_url` placeholder) and/or Zenn repo-sync copy per language policy | AI | 0 | Platform files (CAP-4) |

Draft then exits this pipeline into SPEC-article-review.

**Durability across the stage boundaries (added 2026-07-12).** Each stage
persists its completion state to the run workspace (`$WS`) alongside its
intermediates, so a re-invocation resumes from the last completed stage rather
than restarting — the turn/compute budget is a real ceiling even though
wall-clock is unconstrained (SPEC constraints). A stage that nears the ceiling
surfaces a budget-triage signal before hard failure, and a resumed or partial
run reports its last completed stage and resume path in the completion summary
(CAP-6). The AI-actor stages are the checkpoint boundaries.

## Fact-sheet entry format (stage 1)

```
- CLAIM: <one sentence>
  SOURCE: <path:line@sha | commit sha | URL>
  KIND: result | decision | number | quote | event
```

SOURCE is a **single** commit-pinned line (`path:line@sha`, not a range) for
every KIND except `quote`; a `quote` SOURCE may span consecutive physical lines
(`path:line1-line2@sha`) when the verbatim text does (e.g. a wrapped table cell),
so a natural quote boundary is never forced to fold in unrelated adjacent text
(`skills/harvest/SKILL.md` §3).

Entries the AI wants to use but cannot source go to a `NEEDS-OWNER` list feeding stage 2 — never into the draft unmarked.

The fact sheet and `NEEDS-OWNER` list are written to the run workspace
(`docs/storage-architecture.md` D2), never into the host working tree — the
location is contract, not agent default.

## Interview question bank (stage 2)

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

Pick ≤5 survivors, prioritized top-down; tailor wording to the framework's
GATE slots:

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
  `needs-owner-reraise` | `owner-judgment`), the recommendation's grounding
  pointers (when recommended), and the owner's disposition.
- Every **suppressed** question records its covering entries.
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
