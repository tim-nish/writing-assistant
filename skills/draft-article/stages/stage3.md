<!-- stages/stage3.md — draft-article stage companion (Story 19.3, #744/#740). Loaded on entry to this stage by the
     SKILL.md dispatcher; carries the stage's full operating detail,
     moved verbatim from the pre-split SKILL.md. -->

## Stage 3 — fill the framework (with `[VERIFY]` markers)

Fill the chosen framework's slots from the fact sheet and the interview answers.

**Who performs each sub-step.** Stage 3 is the one stage that interleaves
authoring with validation, so read this before running anything: *you* write
the prose sub-steps, and the commands only check what you wrote. A run that
mistakes a validator for the generator waits for a draft no command will
produce.

| Sub-step | Who | What it is |
|---|---|---|
| argument plan (`$WS/argument-plan.md`) | **you (LLM)** | compose the thesis, arc, and section intents — no command generates this |
| candidate structures (the `structures` sub-command, invoked in the CAP-4 block below) | mechanical | derives 2-3 candidates from the selected elements' evidence kinds; the **owner** chooses |
| `structure-record` | mechanical | records the owner's choice into the plan; refuses a second gate or a second store |
| per-section fill | **you (LLM)** | write the draft body against the section intents, with `[VERIFY]` markers |
| provenance map (sidecar) | **you (LLM)** | author the per-position map alongside the draft |
| `draft-pipeline.py provenance` / `verify-provenance` | mechanical | validate the map against the draft; never write prose |
| visual-set plan | **you (LLM)**, ratified mechanically | propose the set; the ratification refuses a non-conforming plan |
| isolated provenance judge | **LLM, separate context** | grades positions independently of the author |

**Stage 3 opens with an argument-plan sub-step (CAP-1, #440/#434).** Before
filling any slot, compose an explicit **argument plan** from the fact sheet
(including the narrative kinds — `chronology | motivation | cost | reversal`,
#438) and the interview answers, and write it to the run workspace
(`$WS/argument-plan.md`):

- **thesis** — the one claim the article advances; every section must serve it.
- **arc** — the ordered movement across the whole article. For a multi-lesson
  piece this is a **single arc** — shared context → distinct lesson sections →
  one synthesis — **not** the framework's section skeleton repeated verbatim per
  lesson (#434).
- **section intents** — per section, its **content obligation** (what it must
  establish and the evidence type behind it) and the fact-sheet entries (by
  pointer) it will draw on. A framework governs each section's **content
  obligations, not its literal heading structure**.

**Narrative-structure choice — propose 2-3 candidate structures (CAP-4, Story
18.26, #503).** A framework's **narrative structure is owner editorial intent
per artifact, never a hardened tool default**. Before settling the arc, the
sub-step **proposes 2-3 candidate structures** for the selected elements and
lets the owner choose. Get the candidates from the selected elements' evidence
kinds:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py structures <<< '{"elements":[{"id":…,"kinds":["chronology",…],"dominant_incident":false}, …]}'
```

**The owner's free-form message is an input to the candidates (Story 18.45,
CAP-9 2026-07-22 #554 amendment).** When the run carries a
[coverage brief](#owner-coverage-brief-cap-9-aligned-story-1824-505), pass it —
the candidates are then composed for **the story the owner described**, not from
the auto-selected elements alone. This is the **same proposer widened at its
input**: CAP-9's entry generalization adds **no second proposer** and no second gate.

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py structures --brief "<the owner's message or a file path>" <<< '{"elements":[…]}'
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py structures <<< '{"elements":[…],"brief":{"text":"…"}}'   # or carry state.brief through
```

The brief steers **emphasis and shape, never scope**:

- **Emphasis** — elements the brief names lead the sections/beats, and the
  rationales say so ("the brief leads with '<element id>'"). Every selected
  element still survives — **composition, not selection**.
- **Shape** — the owner's own words may ask for a structure the evidence alone
  did not signal ("tell the story of…", "just the retry storm, in depth", "what
  pattern ties these together"). That candidate is offered, composed from the
  **same** selected elements as beats, and marked `grounding:
  "brief-requested"` as against `"evidence-signalled"` — the distinction stays
  auditable, and the brief-cued shape is never the one the 3-candidate cap drops.
- **Never invented evidence** — only element ids the brief actually **matched**
  are named in a candidate, so no candidate can imply evidence absent from the
  fact sheet. A brief item matching no cluster is handled where it already is:
  as a NEEDS-OWNER gap at selection, not as a structure.
- The guarantees are unchanged: still **≥2 distinct candidates**, capped at 3,
  each element-grounded, **sibling-lessons still marked the default**, and the
  proposer still **deterministic**.

With **no** brief, the candidates are **exactly** the element-only ones above —
byte for byte. When the brief carries the owner's selected **Strand set**, the
composed candidates are covered — see [strand-cover.md](strand-cover.md).

For F2 the shapes are **sibling-lessons** (the current default), **chronological
journey**, **single-incident deep thread**, and **thematic braid** — each
returned with a one-line **rationale grounded in the selected elements' evidence
kinds** (chronology-rich clusters suggest the journey; one dominant incident
suggests the deep thread; shared themes suggest the braid). Present them under
the [owner-facing proposal contract](../../owner-facing-proposal-contract.md): the
owner **picks one, or counter-proposes free-form**. **Combining multiple
selected elements into one narrative thread is a supported structure** — the
journey/deep-thread/braid compose the elements as **beats** of one thread rather
than one section each. This is **composition, not selection**: element selection
and its **CAP-9 disclosure are unchanged**, and every selected element survives
as a beat of the chosen thread (the candidates echo the full element set). With
**no choice**, the **default is sibling-lessons** — the run never hardens into a
single shape, but it never blocks on the question either.

**One gate, one record — the widening grows neither (Story 18.46, #559).** The
brief-informed candidates flow through the **existing** presentation above:
**exactly one** confirmation, selectable options **plus** a free-form
counter-proposal, and **no second gate** anywhere in the entry path. The choice
is recorded in the argument plan's **`arc`** and **nowhere else** — in
particular **not** in `editorial_anchor`, which continues to carry the
**claim/angle answer only** (Story 18.41; SPEC-policy-editorial-direction
CAP-2). A second gate or a second store is a contract violation, so assert both
mechanically before reporting completion:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py structure-record --plan <plans/<slug>.md> --journal "$WS/interview-journal.json" [--expect-choice] [--brief-informed]
```

Exit 0 prints the disclosure payload — the structure, that it is recorded in
`arc`, whether **brief-informed**, and (#911) the recorded
`structure_provenance` with its `owner_edited` flag. Exit 1 names the violation.

**The accepted structure carries its provenance (#911).** Every candidate is
marked `provenance: framework:F2` (sibling-lessons) or `bespoke`; the accepted
value is **carried** into the plan's `structure_provenance` (`+owner-edited`
when the owner rewrote it) — recording contract in [complete.md](complete.md);
`structure-record` refuses an absent or re-derived value. When the choice was brief-informed, the **completion summary and the
interview journal say so**, consistent with the existing per-element CAP-9
disclosure. When the owner makes **no** choice the shipped default
(sibling-lessons) still applies and the run **never blocks** on the question —
so `--expect-choice` is passed only when a choice was actually made.

Whichever structure is chosen, record it in the argument plan (`arc`) and
compose Stage 3 from it. **Generation still owns coherence:** the chosen
structure must **pass the existing Stage 3→4 gate** (dim1 narrative arc; the
#434 skeleton-variation rules), and review never reconstructs structure.

Then fill **from the plan** — each section (or beat) realizes its intent,
drawing the named entries — rather than populating slots directly. This is a
**sub-step**, not a new pipeline stage, and **provenance is unchanged**: every
checkable claim is still sourced/derived, synthesis stays legal in connective
tissue. The plan is a **run-workspace intermediate** and is **owner-visible** —
the completion summary names the thesis and arc the draft was composed from
(CAP-2), and at completion the plan-record `plans/<slug>.md` projects them from
this finalized plan (SPEC-article-plan, unchanged). A section whose intent is
under-evidenced (its named entries are thin) is visible **here, before fill**;
the Stage 3→4 gate fails a slot that ships as a single under-evidenced sentence.

**Per-section progress recording (Story 13.84, #388).** Stage 3 is a long
stage: an evidence-heavy fill can exceed one invocation's budget by itself, so
it persists per section, in framework slot order, using the same sub-stage
mechanism as harvest (Story 13.83). The unit is **the section plus its
provenance** — after drafting each section: (1) append the section's prose to
the workspace draft (Read it first on any overwrite — the artifact-write
precondition), (2) append that section's provenance-map lines to the working
sidecar map in `$WS`, (3) only then record the boundary:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py progress --ws "$WS" --stage fill --done <section-slug> [<section-slug> …]
```

A section is never recorded before both writes land — a draft section the map
does not cover must not survive an interrupt. On a resumed run
(`progress.fill.done` present), **reuse the persisted draft and map**: skip
the listed sections, continue with the first unlisted framework slot, and do
not regenerate completed sections' prose or provenance lines. Because sections
append in slot order, earlier sections' `[L<line>]` anchors stay stable; the
stage-end structural validation below (`provenance --map --draft`) remains the
backstop that catches any drift, exactly as for a single-invocation fill. The
downstream contract is unchanged: the quality gate, `verify-provenance`, and
the stage-completion checkpoint (which clears `progress.fill`) all see the
same artifacts as today.

**Applying a skipped input's declared slot effect (Story 10.5).** When the owner
**skipped** the question feeding a slot, read that slot's `[SKIP: <effect>]` tag
(declared in the framework template; see
[`frameworks/CONVENTIONS.md`](../frameworks/CONVENTIONS.md)) and apply exactly it —
the interview engine recorded only the skip disposition, so the **framework
contract decides the consequence**:

- **omit** → drop the slot, leaving no `{…}` or placeholder residue;
- **defer** → leave the slot for a later pass, unfilled but not blocking;
- **accept-later** → adopt the source-grounded recommended answer now, without
  further owner confirmation;
- **verify** → fill from inference and mark the claim `[VERIFY]` for Stage 4;
- **blocker** → raise a publish blocker (every GATE slot's skip effect) — a GATE
  is never silently dropped.

**Frontmatter** is generated from the config `article` schema — never hardcoded —
so a schema change propagates without editing the fill:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/render-frontmatter.py --language <en|ja>
```

**Fill `audience` and `audience_id` here (Stories 13.41 and 13.71 — this is
where both fields are born).** The skeleton carries pipeline-internal
`audience: {audience}` and `audience_id: {audience_id}` slots. Replace
`audience` with the **one named reader** — from the interview's audience answer
(q5) when one was given, from the backlog item's declared audience when
drafting from the backlog, or from the owner's draft-start declaration
otherwise. Replace `audience_id` with the **stable compatibility identifier**
the owner selected with that same audience answer, **chosen from the installed
platform profiles' audience vocabulary** (list the profiles' `audience` values
and have the owner pick the matching id at the audience declaration — e.g.
`en-practitioner`); it never replaces the free-text named reader and is
**never re-inferred at emission**. Never leave either placeholder: the stage
3→4 quality gate fails on both (a stage-progression precondition), and the
variant stage hard-stops as backstop. Both fields are pipeline-internal —
variant packaging strips them, and they never enter the site schema.

**Provenance — every sentence is one of three classes (Story 11.1;
`docs/harness-architecture.md` D1).** Synthesis is legal without abandoning the
zero-unmarked-claims guarantee, because provenance attaches at the **claim**
level while connective reasoning is legal at the **paragraph** level:

1. **sourced** — asserts something traceable to **one** fact-sheet entry or
   interview answer; carries that **pointer** (`path:line@sha` / sha / URL /
   question `id`), kept verbatim;
2. **derived** — a synthesis over **≥2 named sourced claims** that **compresses,
   combines, or restates** them; it **inherits all their pointers**. Introducing
   new **causality, significance, evaluation, comparison, intent, or scope** is
   *not* derivation — that sentence is inferred and takes `[VERIFY]` (or, if it
   is genuinely the owner's judgment, routes to the interview);
3. **narration** — asserts **nothing checkable** (the *falsifiability test*:
   could a reviewer with all sources mark it false? if no, it is narration);
   transitions, signposting, framing. **No pointer, no marker.**

An **inferred** claim — beyond sources, interview, or legal derivation — carries
an inline **`[VERIFY: <reason>]`** marker exactly as before. **Never an unmarked
assertion.**

**Narrative sections source from narrative kinds (#438; Story 18.4).** A
narrative section — a lesson's arc, a journey — is filled from the fact sheet's
**narrative-KIND entries** (`chronology`, `motivation`, `cost`, `reversal`)
exactly as any section is filled from its evidence: each becomes a **`sourced`**
claim carrying the entry's pointer (`path:line@sha` / a span / URL / `den` /
question `id`). The arc maps onto them — the *why* from `motivation`, the
sequence from `chronology`, the price from `cost`, the superseded framing from
`reversal`. Because the fact sheet can now **carry** this material (previously
routed to NEEDS-OWNER), a story-shaped section is **sourced evidence, not
invention or skeleton**: narrative-kind claims count as sourced tissue, so an
arc built from them **satisfies** the stitched-fact-sheet /
`>70%-sourced-with-no-tissue` gate rather than tripping it. The judgment gate is
unchanged — harvest records the narrative evidence and the **interview still
admits it to prose**; making the evidence available never bypasses that gate.

**Owner opinion as attributed prose spans (CAP-3, #439; Story 17.1).** Owner
opinion the interview elicited — thesis, arc, stakes, beliefs and reversals —
may enter the draft as an **owner-attributed prose span**: a whole paragraph of
the owner's judgment, classified **`sourced`** and pointed at the interview
answer that carries it. Record it in the map as a **single paragraph-level
entry** carrying a **paragraph-granularity** question-id pointer —
`P<n>[L<line>]: sourced <- q<id>` (a bare `P<n>`, no `.S<n>`), the anchor being
the paragraph's first line — rather than one pointer per sentence. This is the
prose channel for the owner's story, distinct from flattening it into atomic
sourced claims. The **falsifiability contract is unchanged**: such prose
asserts nothing source-checkable and must not, so it stays compatible with the
narration rule while remaining explicitly attributed to its answer.
`verify-provenance` accepts the paragraph-granularity question-id pointer as
valid `sourced` attribution for the span it covers (Story 17.2). Use it **only
for a genuine owner-opinion paragraph**; a paragraph that mixes owner opinion
with checkable claims stays per-sentence (`P<n>.S<n>`), each claim classed on
its own.

**The sidecar provenance map.** Stage 3 maintains a **sidecar provenance map**
in the run workspace, appended per section as the fill progresses (Story
13.84 above; never inline — the draft body stays clean for variants and
review), one line per sentence keyed by paragraph/sentence position.
**Positions come from the tool, never from hand-counting (Story 19.16,
#755):** the segmentation that defines `P{n}.S{m}` is mechanical — emit the
skeleton and author the map against it, filling in classifications only:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py provenance-segment --draft <draft>
```

After any draft edit, re-run it and re-emit the map's positions/anchors from
the new skeleton — a hand-renumbered map fails the structural validation's
skeleton-conformance check. The judge worklists print each position's **full
reconstructed sentence** from this same segmentation, and the echo check
compares the judge's quote against it byte-for-byte. When Stage 3 completes,
the full map is validated as below:

```
P4.S2[L31]: derived <- fs-12, fs-14
P4.S3[L32]: narration
P4.S4[L33]: sourced <- fs-15
P4.S5[L34]: verify       # sentence carries an inline [VERIFY] in the draft body
```

**Every position carries a line anchor — `[L<line>]` (#304).** It is the
1-based physical line of the draft where that sentence starts. Without it, the
isolated judge has to **re-derive** the `P{n}.S{n}` numbering by applying the
skip rules (frontmatter, headings, blockquotes, mermaid, the pointer block);
three judges did exactly that over one draft and each produced a *different*
numbering, then returned confident verdicts about sentences that were not at
the positions they named. The map is machine-generated and the draft is fixed
at grading time, so make the judge **match**, never derive.

Structurally validate it — pass `--draft` so the anchors are checked against
the draft they claim to describe — and write it to `$WS`:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py provenance --map <map> --draft <draft> \
  && cp <map> "$WS/provenance-map.txt"
```

`sourced` carries ≥1 pointer, `derived` ≥2, `narration`/`verify` none. With
`--draft`, a position with no anchor — or one resolving outside the draft or to
a blank line — is a structural failure: a map a judge cannot locate is not
gradeable.

**Independent verify-provenance (Story 11.2, NFR13).** The map is then graded by
`verify-provenance` — a **standalone** check that does **not** share this
drafting context, so the agent that wrote the text never grades its own
claim/narration boundary. Operationally, this means the semantic judgment runs
in a **fresh judge subagent that never saw the drafting turn** — spawn it with
the harness Task tool, never as an inline continuation of this context:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/verify-provenance.py --map "$WS/provenance-map.txt" \
  --draft <draft> --fact-sheet "$WS/fact-sheet-ids.txt" \
  --judge-findings "$WS/provenance-verdicts.txt"
```

**Hand the judge anchored text, and have it echo what it graded (#304).** Build
the judge's worklist with `--draft` so each position arrives with its anchored
line verbatim — `P4.S3 [L32]: <the sentence>` — and instruct the judge to return
`POS ~ "<the sentence it graded>": <reason>`. The echo is what makes a
*mislocated* verdict detectable from the record alone: a judge that graded the
wrong sentence still returns a confident finding, and `verify-provenance`
discards it with a named `ANCHOR MISMATCH` instead of passing it through as a
real defect. `POS: <reason>` (no echo) still parses; the mismatch check simply
cannot run on it. This costs the judge nothing — it is quoting text it was
already handed.

**The judge's verdicts file opens with a fail-closed attestation (Story 13.67,
#364) — instruct the judge verbatim.** The `--list-narration`/`--list-derived`
hand-off (with `--draft`) begins with the exact header lines the judge must
echo unmodified at the top of `$WS/provenance-verdicts.txt`:

```
attestation: draft-sha256=<hex64>
graded: <the comma-separated positions from the hand-off>
```

(both listings' `graded:` lines are echoed — the tool unions them), followed by
its failure verdicts, or by nothing when it found no violation. The attestation
binds the verdicts to this draft version and this worklist: `verify-provenance`
**fails closed (exit 3, "not judged")** on a comment-only or free-form file, a
graded set that does not cover every narration/derived position, an unknown
position, or a draft-hash mismatch — so an orchestrator-authored "all pass"
note can never substitute for a judge run, and "never judged" is mechanically
distinguishable from "judged clean".

It resolves every `derived` (and `sourced`) pointer against the declared
fact-sheet entries **mechanically**, and consumes the **isolated judge
subagent's** verdicts for the semantic tests — a `narration` sentence that asserts
a checkable proposition **fails the falsifiability test** (a gate failure), and a
`derived` claim adding any of the six forbidden categories is a gate failure.
**Spawn a cheap-tier judge subagent** and hand it *only* the sentences
`--list-narration` / `--list-derived` surface **plus the fact-sheet entries they
cite** — never the drafting rationale, the interview, or your reasons for each
classification. The subagent writes its attestation + verdicts to
`$WS/provenance-verdicts.txt`, which the command consumes. **Every revision
cycle re-spawns the judge**: after any edit to the draft or map, the old
attestation's draft hash no longer matches, so a fresh isolated judge run is
the only way back to PASS — the drafting context never authors or amends the
verdicts file. A clean map passes
with no findings; any finding blocks stage progression. (These judge spawns cost
turns against the pipeline budget — see #118's durability/resume constraint.)

**A revision cycle re-grades only what changed (#738 delta re-grade).** On a
revision cycle, build each listing with the prior cycle's hand-off and verdicts
as the attested basis:

```
python3 /home/tomoya/work/writing-assistant/scripts/verify-provenance.py --map <map> --draft <edited> \
  --list-narration --prior-worklist "$WS/judge-narration.txt" \
  --prior-verdicts "$WS/provenance-verdicts.txt"
```

Sentences unchanged since the attested basis whose positions graded clean carry
forward on a `carried:` header line — the judge echoes it with `attestation:`
and `graded:`, grades **only** the re-graded entries, and the checker counts
carried positions toward worklist coverage. The emission discloses the split on
stderr (`delta re-grade: N carried, M re-graded`) — the run-workspace record
of what each round cost. A basis that does not resolve (missing or mismatched
attestation) falls back to a full re-grade **with the disclosed reason**, never
silently. Isolation is unchanged: the judge receives the smaller worklist,
never prior verdicts. The **two-cycle bound is mechanically enforced**: the
gate refuses `--cycle` past the shared bound with a publish-blocker payload —
a third revision round is unreachable, never merely discouraged.

**Grade `sourced` spans for ATTRIBUTION entailment, not only pointer resolution
(Story 18.97, #672).** A sourced pointer resolving into the fact sheet proves the
*topic* is grounded — it does **not** prove the sentence's **attribution** (which
actor/component acted, and at what scope) is what the pointer supports. A claim
about the wrong actor can cite a real, related line and pass. So add
`--list-sourced` to the judge hand-off and instruct the isolated judge, **for
each sourced span**: *does this pointer SUPPORT this claim AS STATED, including
its attributed actor/scope?* A span whose **topic the pointer supports but whose
attributed actor/scope it contradicts** is a failure the judge reports as
`POS ~ "<the sentence>": contradicted-attribution — <what the source actually
says vs. what the sentence claims>`. `verify-provenance` consumes it as a gate
failure like any other. The check is **scoped to attribution**: a sourced span
making no actor/scope claim, or one the pointer supports, passes silently — so
ordinary grounded claims are unaffected. The judge stays isolated (NFR13): it
sees only the sourced spans `--list-sourced` surfaces and their cited fact-sheet
entries, never the drafting rationale.

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/verify-provenance.py --map "$WS/provenance-map.txt" --draft <draft> --list-sourced
```

The marker format is **exactly `[VERIFY: <reason>]`** (uppercase, colon-space,
non-empty reason) so Stage 4 and the lint (Story 5.1) can find every one. Check
the filled draft with:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py verify-markers <draft>
```

Malformed markers fail; Stage 4 then resolves each `[VERIFY]` until
`verify-markers --count` reports zero.

### Visual-set plan (SPEC-article-visuals CAP-2a, Story 13.58)

**Before any individual visual proposal, propose the article's visual set as a
whole** — one owner-ratifiable item under the
[**owner-facing proposal contract**](../../owner-facing-proposal-contract.md)
(Where/Why/Effect labels; plain-text payload per contract section (g)). The
set-level question is always asked **deliberately**, instead of the effective
zero-or-one outcome the per-slot reactive flow produced. The plan enumerates,
as a whole:

- **how many** visuals — `0..cap`, where the cap is the framework's **declared
  slot + 2 opportunistic extras** (CAP-2's cap stands; the plan proposes
  within it, never raises it). **Zero is a valid plan** — when the article
  needs no visual, the plan says so and **nothing is padded toward the cap**;
- **per member**: its **communicative role** (what part of the argument it
  carries), **required elements** (the nodes/relationships/rows the role
  demands), **format** (the CAP-4 table-vs-diagram rule applied per member),
  **placement** (framework slot or section), and **per-element evidence
  pointers** (commit-pinned or interview-answer ids, per CAP-3). An element
  with no pointer routes to **`[VERIFY]`/NEEDS-OWNER**, exactly as CAP-3
  requires — the set plan never launders an unsourced element in.

Recommend multiple visuals **only when distinct parts of the argument
materially benefit** — the step makes the set deliberate, never larger.

**Author the plan from this scaffold (Story 13.79)** — the ratifiability
invariants are unchanged; the shape below satisfies them by construction, so a
plan authored from it is the natural first output. Every member carries **≥1
`required_elements`**, and `evidence` maps **each** element to a pinned
pointer (`path:line@sha`), an interview-answer id (`q4`), or an explicit
`[VERIFY: reason]` / NEEDS-OWNER marker. **Fact-sheet ids (`fs-11`) are NOT
in the evidence grammar (#410, Tanuki F72)** — the validator refuses them
every time: before emitting the plan, dereference each fact-sheet id to the
entry's own pinned `SOURCE` pointer (`path:line@sha`, carried verbatim in the
fact sheet) and cite that. Authoring with grammar-valid evidence on the first
attempt is the contract; the refusal path is recovery, not the workflow:

```json
{
  "members": [
    {
      "role": "the harvest→draft→review pipeline flow",
      "required_elements": ["harvest", "draft", "review", "gate edge"],
      "format": "diagram",
      "placement": "Section 3 (Architecture) — declared slot",
      "evidence": {
        "harvest":   "skills/harvest/SKILL.md:11@a1b2c3d",
        "draft":     "q4",
        "review":    "skills/review-article/SKILL.md:1@a1b2c3d",
        "gate edge": "[VERIFY: the ordering is argued in prose, unpinned]"
      }
    }
  ]
}
```

Validate the assembled plan — the cap (whose operand is the structure's `visual_slots`, never a framework's; #983) and the zero-plan-no-padding rule — with:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-visual-set.py --plan-record "$WS/plan.json" "$WS/visual-set-plan.json"
```

A refusal names the **exact member/field and its concrete fix** (e.g.
`members[0].evidence['gate edge']: element has no evidence — fix: …`) —
resolve exactly the named fields and resubmit; never rewrite the whole plan
from scratch on a refusal, and never present a plan to the owner before the
validator accepts it.

**The owner ratifies, modifies, or declines the whole plan.** Modification
(remove a member, change a role/format/placement, add one within the cap)
happens **at the plan step without re-litigating approved members**. **Declining
the whole plan degrades to the per-slot flow below** — the individual
proposals run exactly as before. A declined planned member leaves **no
placeholder residue**, and downstream per-visual machinery (source proposal,
fallback ladder, no-rendering) is **unchanged**. When a plan is ratified, the
individual proposals below **follow it** (CAP-2) rather than re-deciding the
set.

### Visual proposals (SPEC-article-visuals CAP-2)

As the framework fills, reach its **declared visual slot** (Story 8.1;
`frameworks/CONVENTIONS.md`) — and identify **up to 2 opportunistic extra
visuals** where one would materially help. When a **ratified visual-set plan**
exists (CAP-2a above), these individual proposals **follow the plan's members**
rather than re-opening the set decision; absent a plan (the owner declined it),
this is the per-slot fallback flow. **Propose** each; never insert one
unasked. Each proposal is **two steps** (SPEC-draft-article-ux CAP-3, Story
13.29) — the intent decision comes before any finished source, because the
fallback ladder's table-vs-diagram choice depends on it. Both steps follow the
shared
[**owner-facing proposal contract**](../../owner-facing-proposal-contract.md)
(`${CLAUDE_PLUGIN_ROOT}/skills/owner-facing-proposal-contract.md`):

**Step 1 — intent.** Ask "what should a visual in {section} communicate?" with
**draft-grounded options** derived from what that section actually argues —
e.g. *pipeline flow* / *comparison* / *timeline* / *none needed* — never a
fixed menu. The **table-vs-diagram** decision of the fallback ladder is made
here (comparative content → table; topological → diagram). **Declining at
step 1 skips step 2 entirely** and omits the slot with no `[Figure: …]`
residue (unchanged decline semantics).

**Step 2 — source.** For the chosen intent, propose the concrete visual:

- **where** it lands in the outline (the framework slot, or the section an
  opportunistic visual would sit in);
- **why** it is proposed (the rationale, now anchored to the approved intent);
- a **preview** — a **plain-text structural sketch** (elements, relations,
  emphasis — figure-spec style; contract (g), Story 13.48), never raw Mermaid
  or fenced source in the payload. Write the concrete **Mermaid/table source**
  the owner is approving to the **run workspace** (`$WS/visuals/<slot>.mmd` or
  `.md`) first, and show that **path** in the payload so the owner can open it
  rendered;
- **choices whose labels state their concrete effect** — *approve* → "insert
  the source at the shown workspace path, exactly as written", *modify* →
  "revise the source, then insert" (a *modify* re-writes the same workspace
  path — Read it first, per the artifact-write precondition), *decline* →
  "omit the visual; the slot
  leaves no `[Figure: …]` residue".

**On approval, stage 3 inserts the workspace file's content exactly as
written** — the sketch is presentation-only and is never re-derived into the
draft; what the owner approved (the file at the shown path) is what lands.
Visual-proposal payloads pass the contract-(e) validator **without
exemption** — the plain-text marker gate (Story 13.47) applies to this surface
like every other; the workspace path is what keeps fenced source out of the
payload.

**Insert nothing without explicit owner approval.** Opportunistic suggestions are
**capped at 2 per draft** — the declared slot plus at most two extras, never
more — and follow the **same two-step** flow. A declined proposal (either step)
leaves the slot **omitted entirely** (Story 8.1), with no placeholder residue.
Element-level sourcing (CAP-3 below) is unchanged.

### Sourced visuals (SPEC-article-visuals CAP-3)

A diagram is a claim, so a visual is sourced **exactly like prose** — the same
provenance rule as the framework fill above, applied **per element**. For every
element of a proposed visual (each node, edge, row, or label):

1. it is **source-pointed** like a fact-sheet entry (`path:line@sha` / sha / URL),
   **or**
2. the proposal carries a **`[VERIFY: <reason>]`** marker naming why that element
   is unverified.

**Never an unmarked structural claim.** A structural claim the pipeline **cannot
source** — a relationship, ordering, or grouping with no artifact behind it —
routes to **NEEDS-OWNER**, the **same partition rule as prose** (Story 3.1 / stage
1): it never becomes an unmarked diagram element. Auditing any approved diagram
element must lead to a source pointer, an interview answer, or a `[VERIFY]` marker
— no exceptions.

### Visual fallback ladder (SPEC-article-visuals CAP-4)

When no existing repo visual fits a slot, produce **visual source** — never a bare
`[Figure: …]` placeholder — following this **strict order**, stopping at the first
rung that fits:

1. **reuse a repo visual** — an existing diagram/image already in the sources;
2. **Mermaid** source (Mermaid only; no PlantUML);
3. **Vega-Lite spec** for a **quantitative** role — data rows are the pinned measurements (#983);
4. **figure spec** — elements, relations, emphasis, and a caption;
5. a **copy-paste-ready image-generation prompt** from the figure spec, with **"no embedded text"** and an **aspect ratio**;
6. **ASCII** — **simple structures only**.

Prefer a **markdown table over a diagram** whenever the content is comparative
rather than topological. Every non-reused visual in a draft is therefore one of:
Mermaid source, a Vega-Lite spec, a figure spec, an image-generation prompt
block, or ASCII — **never a bare `[Figure: …]` placeholder**.

**No rendering (NFR9).** This step produces **source only**: it never invokes
`mermaid-cli`, any image tooling, or an image-generation API — rendering is the
owner's tooling. The plugin bundles no such tools.


---

**Stage 3 exit → the quality gate.** Read [`gate.md`](gate.md) and run:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py quality-gate --draft … --map … --judge …
```

Stage 3 does not complete until that gate passes — it is a stage-progression
precondition, not an advisory review.
