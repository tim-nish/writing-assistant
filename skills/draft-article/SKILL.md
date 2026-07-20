---
name: draft-article
description: >
  Draft a technical article from a repository's own material. Invoke as
  "draft article <article-type> from <sources>" to run the pipeline: harvest →
  gap interview → framework fill → verification → completion (variants are a
  separate post-review invocation — see variants.md). Article
  types are intent labels — "introduce the project", "share engineering
  lessons", "explain the evaluation methodology", "survey a research area",
  "write a working note" (F1-F5 remain the internal/expert alias); sources
  are paths, globs, or commit ranges.
---

# Draft article

One invocation kicks off the whole harvest-to-variant flow:

```
draft article <article-type> from <sources>
```

- **article-type** — an **intent label**: "introduce the project", "share
  engineering lessons", "explain the evaluation methodology", "survey a
  research area", or "write a working note" (the lightweight slim-profile
  entry — see "Working-note slim profile" below). The framework ids
  `F1`–`F5` keep working as the internal/expert alias (see
  `${CLAUDE_PLUGIN_ROOT}/skills/draft-article/frameworks/`); both forms
  resolve through `resolve_framework` in the pipeline helper — a closed
  mapping, never fuzzy-matched.
- **sources** — any mix of paths, globs (`src/**/*.py`), and commit ranges
  (`HEAD~20..HEAD`).

**No article type given?** Ask by intent, in-conversation (proposal contract):
offer the five intent labels with a **repo-grounded recommendation** — e.g. a
tagged release exists → "introduce the project" is viable; no release → its
own entry precondition already redirects to "share engineering lessons", so
recommend that. Draft the recommendation from repo state you can check
(tags, docs, eval assets), never from guesswork.

**Policy-informed recommendation (SPEC-policy-editorial-direction CAP-1,
Story 13.37).** When the host repo declares a `policy_source`, the
recommendation may additionally draw on the owner's recorded positions — read
the base surface (`read-policy-source.py read --only GLOSSARY.md LESSONS.md`;
topics are not selected yet at this point) and let a recorded stance on what
the owner's channel should emit shape which type is recommended. The three
invariants are hard lines: the policy **proposes** (a recommendation the owner
ratifies or overrides — never a silent decision); it supplies **no facts**
(the seed shapes the recommendation, never grounds a claim); and the influence
is **audited** — quote the seed verbatim with its `file:line@commit` pointer
in the question's **Why**, and record it in the journal's `consulted:` line
via `journal --seed-extra '<pointer>=article-type'`. An owner override is a
**recorded decline** (the presented-payload log keeps the recommendation and
the selection; declines are the recall surface's raw material — proposal-only,
staging-candidate path unchanged). Without a `policy_source`, the
recommendation is repo-grounded only, with zero policy interaction.

**Vocabulary boundary (SPEC-draft-article-ux CAP-1, Story 13.27):** framework
ids (`F1`–`F4`), GATE slot markers, and stage names are internal contract
vocabulary. They stay in specs, filenames, run state, and the journal — they
**never appear in an owner-facing question, proposal, or summary**. When
talking to the owner, always use the intent label ("introduce the project"),
never the id.

Every `draft-pipeline.py` subcommand and its flags are tabled in
[Pipeline command reference](#pipeline-command-reference-draft-pipelinepy) at the
end of this skill — consult it instead of running `--help` or reading the script
source mid-run.

## Owner-facing proposals

Every point in this pipeline where the owner approves, modifies, or declines
something — the **Stage 2** gap interview and the **Stage 4** verification pass —
follows the shared
[**owner-facing proposal contract**](../owner-facing-proposal-contract.md)
(`${CLAUDE_PLUGIN_ROOT}/skills/owner-facing-proposal-contract.md`): show **where**
the item lands (outline/section context, with a preview of current content when
one exists), **why** it is asked, and **choices whose labels state their concrete
effect** on the article — never a shorthand label the owner must decode. This
skill references that one convention rather than restating its own wording.

## Stage 0 — start the run (one call)

**Stage 0 is a single invocation (Story 13.13)** — configuration validation
(CAP-5), the framework check, and workspace **autostart** (Story 13.12) fold into
one command so the run spends one turn here, not three:

```
S0=$(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py stage0 <framework> <sources...> --root <host-repo>)
WS=$(printf '%s' "$S0" | python3 -c "import json,sys; print(json.load(sys.stdin)['ws'])")
```

(`--root` — accepted by every plugin script that resolves the host repo —
defaults to the git top-level of the current directory and errors if cwd is not
inside a git repo; pass it explicitly whenever the session's working directory
might not be the host repo.)

**Say which repository you are operating on, first (#309).** `stage0` returns the
resolved `target`; make it the run's **first owner-visible line** — before any
scope read, workspace mint, or LLM spend:

```
Operating on host repo: <target>
```

An operation against the wrong repository is otherwise undetectable until the
work is already paid for, and with a `policy_source` declared a wrong target
seeds the interview from the wrong repo's recorded positions. If an explicit
`--root` disagrees with the session's cwd, the resolver prints a one-line notice
naming both — relay it; `--root` still wins.

It does, in order, halting on the first problem so nothing starts on a bad
config or framework:

- **Configuration validation (CAP-5).** Halts on any unresolved example
  placeholder, malformed URL (e.g. a double-slash `canonical_url`), or missing
  required key, printing a **per-key report** naming the file
  (`user-config.yaml` / `writing-sources.yaml`) and the fix — the report is
  `validate-config.py`'s verbatim. A clean config is silent. Relay any report and
  stop.
  - **A missing `writing-sources.yaml` is a hard stop, not a self-service fix
    (Story 13.11; placement amended by #211).** Do **not** proceed on a config
    you invented. The file lives in the **machine-global per-repo config —
    never in the host repo** (a host repo may be public, and this file can
    carry private pointers); resolve the exact destination with
    `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py sources-file --root <host-repo>`.
    Relay the error, then **offer to scaffold** a starter `writing-sources.yaml`
    at that resolved machine-global path as an explicit, owner-confirmed step;
    on consent create it from the example and show the owner the **path and
    contents** before re-running Stage 0; without consent, stop.
    Never scaffold silently, and never create the file inside the host repo.
- **Article-type check** against the **closed set** of intent labels and their
  `F1`–`F5` aliases (`resolve_framework`) — an invalid name exits non-zero and
  **nothing starts** (no workspace minted). Relay and stop. **An unmapped
  intent gets a reason and a nearest fit, never a bare label list (Story
  13.81):** the error states *why* there is no framework (the category set is
  ratified and closed — the four categories plus the working-note profile,
  all five enterable), names the
  closest sanctioned fit for the intent, and for a tutorial/how-to intent
  references the deliberate AP-10 exclusion (SPEC-article-frameworks) so the
  writer sees a decision, not a bug. Relay that hint verbatim — never
  fuzzy-select a framework on the writer's behalf; a mapped intent resolves
  exactly as before.
- **Workspace autostart** — resumption is **automatic, not opt-in**. It resumes
  the **newest in-progress run** (a workspace whose checkpoint records a
  `next_stage` other than `done`) when one exists, returning `"resumed": true`
  and the `next_stage` to continue from — **skip straight to that stage**, reusing
  the persisted intermediates. Otherwise it mints a fresh workspace with
  `"resumed": false` and `next_stage: harvest` (the no-false-resume path). A large
  multi-source draft completing across several invocations is the **normal
  model** — a turn-ceiling casualty simply continues next invocation.

On success `stage0` prints one JSON: `{"config_ok": true, "run_state": {…framework,
framework_file, sources…}, "resumed": …, "ws": …, "next_stage": …}`. Carry
`run_state` into the next stage unchanged and write every intermediate under `ws`.
(The underlying `validate-config`, `start`, and `autostart` commands still exist
for standalone use; `stage0` composes them.)

`$WS` is a fresh per-run workspace directory **outside the host repo**
(`docs/storage-architecture.md` D2), resolved by the path resolver — never a
path you compose yourself, and never the host working tree. Its internal layout
is resolver-internal; always ask the resolver, never spell it out. The harvest fact
sheet and NEEDS-OWNER list, interview answers, the provenance map, quality-gate
output, and any scratch all live under `$WS/`; there is no state-vs-cache split.
The **only** files this pipeline writes into the host repo are the declared
products at `output.drafts` (the `complete` gate). Pass `$WS` to Stage 1 so harvest writes
there rather than minting its own workspace.

**Artifact-write precondition (Story 13.78).** The harness Write tool refuses
to overwrite a file that has not been Read in the current session (`File has
not been read yet`). Two situations make a pipeline target already-exist:
**re-writes** (the Stage 3 revision loop, a regenerated provenance map, a
visual *modify*, re-entry after a policy block) and **resumed runs**, where
every artifact persisted by a prior invocation exists but nothing in this
session has Read it. So before every Write to a `$WS` path (or any path this
run may have written before): **Read the target first if it exists; only a
path minted fresh this turn may be written blind.** On a resume, treat every
existing workspace artifact as unread. Writes routed through the pipeline
scripts (`stage0`/checkpoints, `journal`, `complete`,
`write-article-plan.py`) are exempt — the precondition applies only to the
Write tool, and burning retry turns on it is a known budget leak (#388).

### Story-element selection — the model and its disclosure (CAP-9, #428)

A lesson-based article covers **story elements**. A **story element** is a
general **evidence cluster** — a set of fact-sheet entries grouped by a
**declared, deterministic membership rule** (a shared `## Journey` lesson unit,
a shared framework slot, a co-pointed evidence set); an F2 lesson is **one
case** of a cluster, not the only one. Membership is **reproducible from the
declared rule** — the same fact sheet yields the same clusters — and **never a
taste judgment**.

Each element carries a **stable id**. The relation is explicit: the **id is
identity** (two elements are the same iff their ids match), the
**evidence-pointer set is derived payload** *under* the id, and **pointer drift
on re-harvest never changes identity** — a moved pin or a re-pointed entry
updates what the element points at, not what the element *is*. Anything keyed on
the id (consumption, CAP-3) survives re-harvest.

Selection chooses which elements the article covers, **upstream of the argument
plan** (CAP-3/#440 composes *from* the selected elements). The **selection rule
is #428 disclosure-only**: surfacing it changes **nothing** about what gets
selected — with the same fact sheet, two runs select the same elements. What
CAP-9 adds is that the rule is **stated, not implicit**:

- the **interview journal** records, **per selected element, the rule that
  selected it** (id + the declared reason — e.g. "Journey-bearing cluster,
  unconsumed, matched framework slot X"); and
- the **completion summary** repeats the per-element selection reasons in its
  informational bucket, so the owner sees *why each element is in the article*
  without opening a run artifact ([`completion-summary.md`](../completion-summary.md)).

An element the run selected but whose reason cannot be stated is a defect, not a
silent omission — disclosure is required wherever selection ran.

**Consumption exclusion — default to unconsumed (CAP-9, #430).** Lesson-based
selection **defaults to the elements no prior draft has consumed**, so drafting
repeatedly from one repo does not reselect covered material by chance:

- A completed draft **records the story-element ids it consumed** in **its
  article plan** (`plans/<slug>.md`, the `consumed:` frontmatter key —
  SPEC-article-plan). This is the **only** consumption record: **no new store**.
- Selection computes "already consumed" from the **`consumed_index`** the plan
  consultation returns (`write-article-plan.py consult` — see below) — a view
  **regenerated from every `plans/*.md` on each call**, never a hand-maintained
  ledger. An element whose id appears there is excluded from the default
  selection.
- Because consumption is keyed by **element id** (identity, 18.8), it **survives
  re-harvest**: a moved pin or re-pointed entry changes the payload, not the id,
  so a consumed element stays consumed.
- The exclusion is an **owner-overridable default**, never a hard filter: the
  owner may **re-cover** a consumed element (surface it as a proposal under the
  [proposal contract](../owner-facing-proposal-contract.md); a re-cover is the
  owner's to ratify). With **no plans**, nothing is excluded and selection is
  exactly as today.

### Depth/scope directive (CAP-8, #432)

Article depth is **owner intent, never a tool default**. If the owner's
invocation names a depth or scope — a level (`deep-dive` | `standard` | `note`)
or a one-line scope statement ("just the retry bug, deeply") — pass it to
stage 0 so the run records it:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py stage0 <framework> <sources...> --depth "<level or scope>" --root <host-repo>
```

The run-state then carries `depth: {"level": …}` or `depth: {"scope": …}`. If
the owner gave **no** directive, do not invent one — **offer it once as a
Stage-2 interview item** ("How deep — a quick note, a standard piece, or a
deep-dive? Or name a scope.") under the proposal contract, and record the
answer; absent an answer, the run proceeds exactly as before.

**At Stage 3, fill consumes the directive** (`state.depth`): it governs **how
much each slot elaborates and how many story elements the draft carries** — not
a word count or reading-time target. A **deep-dive** keeps material a
framework's split hint (e.g. F2's ">3 lessons") would otherwise cut in **one**
article; a **note** stays tight. When a framework's count/length split hint
would fire, surface it as an **owner choice** ("~N lessons — one deep-dive, or
split?"), **never an automatic split** (the hint is a declinable suggestion per
CAP-8). With **no directive**, fill behaves exactly as before, and the
reading-time estimate stays informational — it drives no split.

### Plan consultation at draft start (SPEC-article-plan CAP-3, Story 13.57)

After Stage 0, before the interview, **consult existing article plans** in the
articles repository — serial engineering-lessons articles should build on prior
decisions instead of repeating them. The read is **read-only through the repo's
schema** — nothing under the articles repository is created or modified by
consultation, and plan content **never enters the harvest evidence stream**
(Story 13.56's fences apply):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/write-article-plan.py consult --root <host-repo>
```

It returns each prior plan's discovery surface (slug, intent, claim, status,
pin, relates, **consumed**) plus a **`consumed_index`** — every story-element id
any plan records as consumed, mapped to the plans that consumed it. The
`consumed_index` is the **consumption-exclusion input** (CAP-9/#430): it is a
**view regenerated from `plans/*.md` on each call**, so lesson-based selection
defaults to the elements **absent** from it (see "Story-element selection"
above). From this surface you **may surface plan-grounded proposals** — each
under the [owner-facing proposal contract](../owner-facing-proposal-contract.md),
**none auto-applied**:

- "article Y already covered X — link to it instead of re-explaining";
- "lesson Z has new evidence since `<pin sha>` — update it?";
- a **continue / fill / update / new** recommendation for how this article
  relates to the prior plans (recorded as `relates` on the plan this run
  eventually emits).

**The tool never applies a prior plan.** Every proposal is the owner's to ratify
or decline. A **declined** proposal leaves **zero friction and no residue** —
the run proceeds exactly as if the proposal had never been surfaced (the
presented-payload log keeps the decline, like every other proposal). A
repository with **no plans, or a schema-less destination, degrades silently**:
`consult` returns an empty list with a reason, and the run behaves exactly as it
does today — never a failure, and never a prompt about missing plans.

### Continuation mode — build on a named prior article (Story 13.95, #429)

The plan consultation above **discovers** how this run relates to prior work;
**continuation mode** is the owner **directing** it. When the invocation carries
a `continuing <prior-slug>` modifier —

```
draft article <type> from <sources> continuing <prior-slug>
```

— the owner has pinned the relation, so this run does not re-discover it:

1. **Read the named prior canonical** at the resolved `output.drafts`
   (`resolve-writing-sources.py draft-location`) and select its plan entry from
   `write-article-plan.py consult` (which returns every prior plan's discovery
   surface — pick the `<prior-slug>` row) — **frontmatter and `summary` only**,
   read-only through the repo schema. The prior draft's
   **body never enters the harvest evidence stream** (Story 13.56's fences hold
   exactly as for plan consultation); it is *framing context*, not a source.
2. **Constrain the lede at Stage 3** to **build on** the prior article rather
   than restate it: the opening assumes the prior claim/summary as given and
   advances from it, instead of re-explaining shared context. This is a directed
   emphasis on the drafting agent, not new evidence and not a new provenance
   class — every checkable claim stays sourced/derived as always.
3. **Record the relation in the emitted draft's frontmatter** —
   `related.articles: [<prior-slug>]` — and as `relates: continue <prior-slug>`
   on the plan this run emits, so the chain is machine-legible for the next run's
   consultation.

If `<prior-slug>` resolves to **no canonical or plan**, surface it under the
[owner-facing proposal contract](../owner-facing-proposal-contract.md) —
"no article `<prior-slug>` found; draft standalone, or correct the slug?" —
never a hard failure. Continuation is an **enhancer**: with no modifier the run
behaves exactly as today (auto plan-consultation only).

### Durability — checkpoint each stage, resume from the last completed one (Story 13.5)

Wall-clock is unconstrained but the **turn/compute budget is a real ceiling**, so
the pipeline is resumable: **after each stage command emits its output state,
checkpoint it** so a re-invocation continues from where it stopped instead of
restarting (a turn-ceiling casualty is recoverable, not a total loss). The stage
state already carries `next_stage`; persist it:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py checkpoint --ws "$WS" <stage-state.json>
```

The write is atomic and idempotent — checkpointing the same stage twice is a
no-op, and because the checkpoint records `next_stage`, resuming
**never re-runs a completed stage**. Stage 0's `autostart` (above) already picks
the right workspace and `next_stage` automatically; `resume --ws "$WS"` inspects a
specific workspace's checkpoint directly when you need it:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py resume --ws "$WS"
```

**Sub-stage progress inside long stages (Story 13.83, #388).** The stage-level
checkpoint alone is not enough for the long stages: an evidence-heavy run that
dies *mid-stage* would replay the whole stage every invocation and never
converge. So the long stages also record **sub-stage progress** — one call per
completed unit of work (batchable):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py progress --ws "$WS" --stage harvest --done <source> [<source> …]
```

The upsert merges `progress.<stage>.done` into the existing checkpoint
(preserving `run_state` and stage state), is idempotent per unit, and refuses
a stage the run has already completed. **Record a unit only after its
artifacts are durably written** — the recording IS the boundary, so a
half-written unit is never marked done. On resume, `autostart`/`resume` return
the `progress` object with the rest of the state: **skip the units it lists**
and continue from the first unrecorded one. A stage's normal completion
checkpoint overwrites the file, clearing its sub-stage progress. Stage 1
records per pinned-source batch (the harvest skill states the exact contract
at its write site).

**Mark the run done on completion — through the completion gate (Story 13.68).**
When the pipeline finishes, run the `complete` subcommand. It is the **only
sanctioned way to finish a draft run** — never hand-write the final
`next_stage: done` checkpoint:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py complete \
  --draft "$WS/<draft>.md" --slug <slug> --root <host-repo> --ws "$WS"
```

The run's declared products are **two** (SPEC-article-draft-pipeline,
2026-07-18 amendment; SPEC-platform-variants CAP-1): the canonical draft at
`<output.drafts>/<slug>.md` and the article plan at `plans/<slug>.md` — **both
must be durably persisted before completion may be reported**. `complete`
persists the canonical (with the emission trailer carrying its content hash,
the same convention the variants stage records), verifies the plan exists at
its resolved destination (the schema-less **user-scoped fallback counts** as a
successful plan write), and only after BOTH products verify writes the final
`next_stage: done` checkpoint so `autostart` treats the run as complete. A
failed write of either product is a **hard error naming the product and path**:
the run never reports "complete", and the checkpoint never records
`next_stage: done` over a workspace-only canonical. The gate applies whenever
`complete` runs, so a resumed run checkpointed before this contract is never
grandfathered. On success the JSON names **both persisted absolute paths** —
relay them in the completion summary's informational notes. Re-running
`complete` over already-persisted products re-verifies and succeeds
(idempotent).

Checkpoint state lives under `$WS` with the other intermediates
(`docs/storage-architecture.md` D2), never in the host tree.

**Resumed-run audience recheck (Story 13.41 — stage 0's half of the presence
rule).** When `stage0`/`autostart` resumes a run (`"resumed": true`) whose
`next_stage` is `verify` (or `variants`, from a checkpoint written before Story
13.69 made variant emission post-review) — i.e. a filled draft already exists among
the intermediates — confirm that draft carries a **resolved `audience`** before
continuing (a run checkpointed before the audience precondition existed may lack
it). If it is missing or still `{audience}` (or `audience_id` is missing or
still `{audience_id}` — Story 13.71), fill both per the Stage-3 rule and
re-run the quality gate; the variant stage's hard stop remains the mechanical
backstop either way.

## Stage 1 — harvest and consume its output

Hand the run to the `harvest` skill to produce its output document at
`$WS/fact-sheet.md` (the source-pointed fact sheet **and** the NEEDS-OWNER
list) — give harvest the `$WS` from Stage 0 so it writes there. The stage-0 sources are
a **selection**, not a scope widener: harvest enumerates the
writing-sources-declared files (`resolve-writing-sources.py files`) and
**intersects** this selection with them, so a path passed on the command line can
only narrow what is read — never add an undeclared repo. Reconciliation against
`writing-sources.yaml` happens there.

**Fact-sheet entries are emitted, never guessed (validator convergence, #206).**
Harvest builds every file-pointer entry through
`pin-source.py --emit-entry` (its §3) — copied from tool output — and runs
`validate-fact-sheet.py` as a **single confirmation pass**. Repair after a
REJECT is **bounded at two validator passes**: entries still rejected after the
second pass move to the NEEDS-OWNER list with their REJECT reason and the stage
surfaces its **budget-triage signal** (Story 13.7 — the existing per-stage
signal, not a new channel) instead of looping again. This stage never instructs
free-hand entry writing followed by validate-loop repair — that
reject → guess → re-run cycle is what exhausted the turn budget across all
three frameworks (#206). Entries rerouted by the bound are listed in the
completion summary's **informational notes** (they reach the owner as interview
material, not as a silent loss).

Then consume that output into pipeline state:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py consume <harvest-doc>
```

This carries harvest's output forward **without re-reading any source** — it only
reads the harvest document, so there is no second read path that could bypass the
Story 3.1 scope boundary. It:

- holds **both** the fact sheet and the NEEDS-OWNER list, parsed against harvest's
  exact contract (a schema change surfaces here rather than being absorbed);
- preserves every entry's **source pointer verbatim** (`path:line@sha` / sha /
  URL) for later traceability — no re-normalization;
- **threads the NEEDS-OWNER list into the gap interview** (`next_stage:
  interview`, Story 4.3), so unsourced gaps are not dropped;
- advances on a valid-but-empty result (empty fact sheet and/or NEEDS-OWNER) —
  the stage contract is total.

**Working-note runs:** pass the article type — `consume <harvest-doc>
--framework working-note` — so consume routes `next_stage: fill` (the slim
profile has no interview stage; see "Working-note slim profile" below).

## Working-note slim profile (F5 — Story 13.89, #412)

The ratified working-note category (SPEC-article-frameworks, working-note
ratification 2026-07-16) runs a **slim pipeline profile**, because its
contract is "assembly <1hr" and the full pipeline's attention budget is
mis-sized for it. Differences from the full flow — everything not listed
here runs exactly as the full pipeline does:

- **Sources are constrained (ratified, binding):** the active repos' recent
  activity **plus the owner's policy recall surface via the policy-source
  seam — read-only, pinned, lessons first**; the policy hub's **Q&A history
  archive is never a harvest source**; **published text carries public
  repository links only**. State these bounds to the owner at Stage 0.
- **The one-lesson block is told as a narrative arc (Story 13.93, #425;
  SPEC-article-frameworks "Fill — narrative-arc sourcing").** At fill, select
  the lesson from a recall-surface `## Journey` section (original framing →
  actual question → what moved it), a topic-thread Declined line, or a
  struck-through superseded decision, and map the arc onto the block:
  misconception (original/superseded framing) → turning point ("what moved
  it") → evidence (the lesson's **public** Evidence pointers only) →
  abstraction (the lesson one-liner). A Journey may be hub-native or
  `origin: reconstructed <date>`; both are valid, but **surface the origin
  marker to the owner at selection**. No usable Journey/reversal record →
  a plain one-lesson claim, arc not invented. F5's own template carries the
  full contract.
- **No Stage 2 interview:** `consume --framework working-note` emits
  `next_stage: fill` (`interview` rejects F5 with a named error). NEEDS-OWNER
  entries still ride the state — at fill they become `[VERIFY]` markers or
  publish blockers, never questions.
- **Lighter quality gate:** run `quality-gate --profile slim` — the dim1–2
  rubric judge is waived by contract (do not spawn a judge subagent);
  mechanical dims 3–4 and the audience precondition run in full. The
  per-section evidence-type check (Story 13.90) also runs in full — slim
  never bypasses it: F5's one-lesson and one-number blocks carry
  `[EVIDENCE: …]` declarations like any GATE slot.
- **No visual proposal:** F5 declares no visual slot — never offer one.
- **Framework:** `frameworks/F5-working-note.md` — four fixed blocks (one
  lesson / one number / published-links / what-I'm-building); no entry gate.
- **Variants:** the email + web-archive renderings come from the working-note
  slim packaging profile (SPEC-platform-variants) at the separate post-review
  variants invocation, as with any draft.

## Stage 2 — bounded gap interview

### Owner thesis, arc, and stakes as first-class items (Story 17.1, #439)

The gap interview is not only a hole-filler for what the sources cannot answer;
it is **the owner-input channel for the article's story**. Alongside the
NEEDS-OWNER gaps, the interview **explicitly elicits the owner's thesis, arc,
and stakes** — the one claim the piece exists to make, the misconception→turn
it narrates, and why it matters — as **first-class items**, not only when a
NEEDS-OWNER entry happens to name them. These items ride the **same ≤5 question
budget** and the same journal/disposition machinery as every other question;
they are owner judgment (opinion), so they are **`open`** items (owner-only
knowledge, [`SPEC-policy-source-seam CAP-2`](../../specs/spec-policy-source-seam/SPEC.md)),
never a source-pointed recommendation. Their answers come back as **owner
opinion** and reach the draft as **attributed prose spans** (Stage 3 below),
not as atomic sourced claims — this is the prose-shaped channel the owner's
story needs. When the fact sheet already carries the thesis as a sourced claim,
the item is suppressed like any covered question; when it does not, the owner's
answer is the article's spine.

### The gap interview is *the* owner-input channel (Story 13.98, #435)

Beyond the thesis/arc/stakes items above, the interview **explicitly invites the
owner's free-form requirements and material** — a constraint to honor, a
paragraph the owner wants included, an emphasis, a correction — as **first-class
interview items**, not only answers to source-gap questions. This is the
**designed channel for owner input into the draft**: an owner requirement enters
here and reaches the draft as an **owner-attributed prose span** (opinion,
thesis, arc — Story 17.1) or a **sourced/derived claim** (a checkable
requirement), never through post-hoc hand-editing outside the pipeline. Free-form
material rides the same ≤5 budget and journal machinery; a requirement beyond a
single run's budget is recorded as a NEEDS-OWNER-style item for the next
invocation, never dropped. **Make the channel visible:** when opening the
interview, say that free-form owner requirements are welcome *here*, so the owner
does not assume manual insertion afterward is the intended workflow (the
dogfooding surprise this closes).

### Policy-seeded tension questions (Story 14.4)

Before selecting questions, probe the host repo's optional `policy_source`
(SPEC-policy-source-seam) — the owner's policy repo, read-only and bounded
**in code** to GLOSSARY.md, LESSONS.md, and ≤2 `topics/*.md`. Which two topic
files is a **per-article decision made now, not a per-repo config**
(SPEC-policy-topic-at-draft CAP-2, Story 13.35), in two steps:

1. **List** the available topics — names only, no content read:

   ```
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/read-policy-source.py --root "$HOST" list-topics
   ```

   If this exits **13** (`gateway cannot enumerate topics` — a named
   tool-surface gap, Story 13.72), ask the owner for the topic names under
   the proposal contract instead; the ≤2 cap is unchanged.

2. **Propose ≤2 topics for THIS article** under the proposal contract: draft
   the recommendation from the chosen article intent and the host repo (e.g.
   an evaluation-methodology article from a benchmark repo → the
   benchmark-engineering topic), the owner approves or overrides. Declining
   is valid: the read proceeds with GLOSSARY + LESSONS only — still
   policy-seeded, recorded as track-less. Then read with the approved
   selection:

   ```
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/read-policy-source.py --root "$HOST" read --topics <a.md> [<b.md>] > "$WS/policy-surface.txt"
   ```

   (No approved topics → plain `read`: GLOSSARY + LESSONS only. The per-repo
   `track`/`topics` config keys were **removed** — Story 13.36,
   SPEC-policy-topic-at-draft CAP-3; a leftover key is a named stage-0
   configuration error, never silently applied. The ≤2 cap and the
   code-enforced whitelist are unchanged; `--topics` builds the whitelist,
   unlike `--only`, which filters within it.)

When `policy_source` is unset this whole step is skipped silently — zero new
interaction in generic mode (seam CAP-6).

Branch on its exit code — **the policy source is an enhancer, never a
dependency; no exit code here may abort the run**:

- **0** — the output leads with the run's pin (`pin: <policy-source>@<commit>`)
  and each file's content line-numbered. Author **tension items** from it:
  questions whose `gap_type` is `contradiction`, `ambiguity`,
  `missing-rationale`, or `reversal-candidate`, each carrying its seed
  `{quote, pointer: file:line@commit}` quoted **verbatim** from the surface at
  the pinned commit. The policy source supplies **questions only** — never an
  answer, never a recommendation (SPEC-policy-source-seam CAP-2: triage and recommendations stay a
  view over harvest output). A question that merely restates its seed will be
  rejected (R4) — ask the tension, not the quote.

  **Author against the consulted surface as a whole, never a single line
  (#299).** Before characterizing a quoted line as a tension, read the *rest of
  what the reader returned* for a **companion line that already resolves it** —
  the same batch that records a rejection often records the discriminator right
  beside it. If a companion resolves the apparent conflict, either **do not
  raise the item at all**, or raise it **with the resolving line** in the seed's
  `companion` field, so the owner arbitrates the real residual question instead
  of re-deciding settled ground. A tension the surface already answers is a
  manufactured tension: it spends an owner-gate slot on nothing, and an answer
  to it contributes a "resolution" to a conflict that never existed.

  **Stale seed, not a live tension (#306).** Before raising a conflict, compare
  *when the seed was recorded* against *the material it appears to contradict*.
  The inputs are already in hand — the surface's `updated:` dates and `state:`
  lines, and the run's pin. When the seed **predates** the material (a glossary
  entry updated before the behavior it describes matured), the honest reading is
  a **stale recorded position**, not a live contradiction: route it to
  `gap_type: reversal-candidate` and ask the owner to **confirm or update the
  recorded position** — never ask them to adjudicate a conflict as if it were
  live. Nothing else about the seam changes: same bounded read, same pin, same
  proposal-only contribute-back. Manufactured tension is self-reinforcing — an
  owner who answers a stale-seed question as though it were live contributes a
  "resolution" to a conflict that was an artifact of staleness, so the routing
  decision is what keeps the recall surface honest.

  **The line the discriminator usually turns on:** *harvest is evidence
  assembly; the interview is the judgment gate.* Assembling many source-pointed
  facts is not the same act as generating prose from them — the owner's answers
  are what turn evidence into an argument. Do not seed a tension that treats
  evidence assembly as if it were unattended generation without first checking
  whether the surface itself draws that line. Write the items to
  `"$WS/policy-items.json"` (seam-formats.md §2) and pass them via `--items`
  below; they are schema-validated **before** triage.
- **10** (`policy_source` toggle absent or `enabled` falsy) — generic
  interview, **silently**: no items, no log line, behavior identical to a
  repo without the seam.
- **11** (toggle present, gateway unavailable — unreachable, transport error,
  or timeout; the retired exit 12 collapses here) — the reader printed
  exactly one `policy_source unavailable: <reason>` line;
  **relay that one line once** and continue with the generic interview. Do
  not retry, do not warn again — one line, then generic mode. Keep the
  reason: the journal's `consulted:` line records it (`--policy-note`).
- **13** (named gateway tool-surface gap — Story 13.72) — treat exactly like
  11: the reader printed one `policy tool-surface gap: <reason>` line;
  relay it once, continue generic, record it via `--policy-note`.
- **4** (malformed block) — a stage-0 configuration error slipped through;
  halt and report it like any CAP-5 finding (this cannot happen after a clean
  `stage0`).

### Policy-result classification — CAP-7, before any owner question (Story 13.75)

After authoring the policy items and **before** running `interview`, classify
the served policy result against the authoritative user config
(SPEC-policy-source-seam CAP-7, added 2026-07-18, #365). This is a
**mechanical pre-step** — a deterministic pass over a declarative
comparable-subjects table, never an LLM judgment:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py classify-policy \
  --surface "$WS/policy-surface.txt" --root "$HOST" \
  --items "$WS/policy-items.json" > "$WS/policy-classified.json"
```

Every candidate subject lands in exactly one of CAP-7's four classes —
`determined` / `constrained` / `open` / `conflict` (the first two are
structurally present in the output and empty until the subject table grows;
the shipped detector covers the EN-topology regression as `conflict`). Pass
the output's `interview_items` array (reconciliation items first, then the
open pass-throughs) as the `--items` file below, and carry its
`journal_records` into the run record. Three contracts hold:

- **A conflict subject is presented ONLY as the emitted reconciliation
  question** — a `gap_type: reconciliation` item whose `positions` array
  carries every disagreeing side (`{quote, pointer, authority ∈
  policy|config|repo}`; seam-formats.md §2) — **never as an ordinary
  content-preference question whose candidates smuggle the conflict in**. The
  classifier marks the original tension item `superseded_by_reconciliation`
  and drops it from the pass-through; do not re-add it. (This is the
  2026-07-18 regression: a policy-incompatible records-only answer was
  offered as an ordinary candidate, selected, and shipped unreconciled
  against `syndication.policy` EN-canonical config.)
- **Owner judgment is never pre-decided — the structural exemption.** An item
  whose gap_type is a judgment class (`opinion`, `significance`, `surprise`,
  `tradeoff`, `warning`, `audience`, `motivation`, `retrospective`) always
  classifies `open` and passes through untouched, even when its text matches
  a conflict subject: for judgment questions the "questions only" rule stands
  whole and no class other than open/conflict may apply.
- **An owner answer that reverses a served ratified line is a proposed policy
  change, not policy.** It routes to the staging-candidate emitter (below) as
  a config↔policy reconciliation decision, and is **never treated as current
  policy by later stages of the same run** — the plan-side conformance gate
  that enforces this at draft time is Story 13.76's, not this step's.

Then select the interview questions from the stage-1 state (with policy items
when the probe produced them):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py interview --framework <F> \
  [--items "$WS/policy-classified-items.json"] <state>
```

(where `policy-classified-items.json` is the classifier output's
`interview_items` array; on a run with no policy items at all, skip
`classify-policy` and `--items` alike)

**Three-outcome triage over the harvest output (Story 10.2).** Every candidate
question is triaged against the harvest output **only** — the fact sheet and the
NEEDS-OWNER list, reading **no source material** beyond them (it may read the
framework contract, config, and run-state metadata needed to run the interview).
The `triage` array classifies **each** bank question into exactly one outcome:

- **suppressed** — a fact-sheet entry already covers the question's information
  need (matched semantically via a synonym set, not literal text), and no
  NEEDS-OWNER gap re-raises it. **The owner never sees it** (`covered_by` names
  the covering entries, for the journal in Story 10.4);
- **recommended** — a NEEDS-OWNER entry re-raises the topic → **always
  recommended** (confirm/deny the claim), grounded on that entry;
- **open** — neither → genuinely owner-only knowledge, answered as a bullet.

Where a question triaged **open** is in fact groundable from a fact-sheet
**owner-judgment** entry (a dev-log note of what surprised them *is* a sourced
owner statement), present it as **recommended** instead — this recommendation
pass is a **view over the harvest output**, introducing no new unsourced material.

**Issue- and Den-sourced facts follow the same rule, stated here so it is never
left to inference (Stories 13.50 / 13.51):** a fact harvested from a
`github-issues` or `tanuki-den` source that carries an **owner disposition**
(accepted/dismissed) is eligible grounding for a recommended answer **exactly
like any harvest fact** — the disposition is a sourced owner statement. Open or
deferred findings never reach the fact sheet (harvest routes them to
NEEDS-OWNER), so they surface as confirmed gaps here, not as grounding. A
finding's **recurrence count is data the recommendation may quote, never a
reason the pipeline treats it as more significant** — significance is the
owner's call, asked, not inferred from a count.

Validated policy items join the candidate set as **asked** questions
(`outcome: open`, `rationale: policy-seed`, their `seed` carried through): a
tension between the material and a recorded position is owner-only by nature,
so suppression does not apply — and there is never a recommended answer for
one (SPEC-policy-source-seam CAP-2).

The surviving (non-suppressed) questions are returned as `questions`, and are:

- drawn from the fixed question bank, **prioritized by the framework's GATE
  slots** (not bank order), so the same fact sheet yields a stable interview;
- **confirmed NEEDS-OWNER gaps first**, then **policy-seeded tension
  questions**, then generic open questions, using the GATE-slot order as the
  deterministic tie-break when more than five could apply — the ≤5 cap holds
  even when the NEEDS-OWNER list is longer or policy items are in play;
- **one slot reserved for policy tension (#302).** When at least one valid
  policy-seeded tension item exists, the **highest-priority one is guaranteed a
  slot**: it displaces the lowest-priority survivor rather than extending the
  budget. Priority order alone starves seeds on any repo whose harvest yields
  five or more confirmed gaps — precisely the fact-rich repos the seam exists
  for — and the loss is silent: the editorial anchor falls back to a routine
  slot answer (`policy_seeded: false`) and contribute-back emits an empty file.
  With no valid tension item, selection is exactly as before — no slot is held
  open and nothing is padded. A **reconciliation item counts as a
  tension-priority item** here (Story 13.75): it ranks at least as high as a
  policy-seeded tension question for both the priority order and the reserved
  slot, and its `positions` ride into the journal like a seed does;
- **at most 5**, and **zero** when harvest already covers everything — never
  padded to five.

Present a policy-seeded question under the same proposal contract as every
other: its **Why** context is the seed — the verbatim quote plus its
`file:line@commit` pointer — so the owner sees exactly which recorded position
the question probes. The quote is presented under the contract's **section-(g)
plain-text conventions** (quoting by indentation, no fencing or emphasis
markers; Story 13.48), keeping its `file:line@commit` pointer. Its primary
input is bullet free-text, like any open question.

**Presentation order is contract, not discretion (SPEC-draft-article-ux CAP-4,
Story 13.30).** Ask the surviving questions in the pinned order the `interview`
command already emits (`presentation_order`): **claim/angle first** (the
policy-seeded tension question when one exists — it reframes every later
answer; else the opinion/claim question), **audience second**, then
**headline/significance**, then **color** (surprise, tradeoff, warning,
retrospective). Batching within that order is free — grouping several
questions into one ask is fine — but never reorder across it. The journal
echoes the order, so a mis-ordered run is attributable. Selection priority
(the bullets above) is unchanged; this governs presentation only. When harvest
yields **no `number`/`result` fact**, the bank's conditional evidence-fallback
question ("what result or worked example would convince a skeptical reader?")
joins the candidates automatically (CAP-5) — the evidence GATE's interview
fallback, surfacing the gap here instead of failing late at Stage 3.

Present each surviving question under the
[owner-facing proposal contract](../owner-facing-proposal-contract.md): show
**where** the section it concerns sits in the article outline and a **short
preview of the current section** (when one already exists), **why** the question
is asked, and **choices whose labels state their concrete effect** — never a
shorthand the owner must decode. A first-time owner answers from **repository
knowledge alone**. Assemble the prompt payload and **validate it before showing
it** (contract (e)): `validate-proposal-payload.py` blocks a missing Effect line
or a truncated field. Pass `--ws "$WS" --surface <name>` on that same call so
the presentable payload is **captured verbatim** to
`$WS/presented-payloads.jsonl` at ask time, and record the owner's selection +
free text against the returned `ask_id` with `--answer` (contract (f), Story
13.28) — every owner-facing ask in this pipeline (interview, visual proposals,
Stage-4 verification) captures this way.

### Recommended answers with dispositions (Story 10.3)

A **recommended** question arrives with its **source-pointed candidate answer as
the default choice**, and dispositions **labeled by concrete effect**:

- **Approve** → "adopt this answer as written" — the recommendation becomes the
  interview answer **verbatim** and **keeps its source pointers**, grounding
  sourced claims in stage 3 exactly like a fact-sheet entry;
- **Modify** → "edit this answer, then use it" — the owner's edit is their
  contribution on top of the grounding; the answer is **interview-sourced**;
- **Replace** → "discard this and use my own" — the owner's bullet; also
  **interview-sourced**;
- **Skip** → the question goes unanswered; **only the skip is recorded** — what
  it *means* is the target framework slot's declared effect (Story 10.5),
  resolved at stage 3, never by the interview engine. The skip choice's label
  states that slot's declared effect.

An **open** question carries **bullet free-text** as its primary input (no
recommendation to approve).

Record each answer — with the disposition that fixes its provenance class — via:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py answer --id <qid> \
  --disposition <approved|modified|replaced|answered|skipped> [--text <answer>] [--pointer <p> ...]
```

It enforces the D2 rules — an **approved** answer must inherit ≥1 pointer;
**modified/replaced/answered** carry owner text and **no** pointers (owner
judgment); a **skip** carries neither. The recorded answer text is kept
**verbatim**, keyed by question `id`, for stage-3 traceability.

### Recommended defaults for editorial-judgment gaps (SPEC-policy-editorial-direction CAP-6, Story 13.60)

When a confirmed NEEDS-OWNER gap is an **editorial-judgment** class — `opinion`,
`significance`, `surprise`, `tradeoff`, `warning`, `audience` — and the policy
surface already holds a relevant recorded position, present it as a **proposed
default** the owner ratifies, instead of a bare open question. This is the
propose-ratify invariant applied to the *shape* of the answer: it saves the
owner seconds per question, and is **no substitute for #302's reserved slot**
(the cap fills on count, not time).

- **Item shape (Story 13.59; multi-candidate Story 13.92).** Carry the recalled
  position on the interview item as `recommended_default {default, quote,
  pointer}`, with `owner_answer` structurally empty at generation. When more
  than one recalled position fits the gap, carry **1–3 candidates ordered by
  recontextualizing power** (the one that most reframes the others first)
  instead: `recommended_default {candidates: [{default, quote, pointer}, …]}`
  — 1–3 entries, each auditable, the owner ratifying **exactly one**
  (approve/modify/replace/skip); the machine is never final. A single position
  (no `candidates` key) is the N=1 case, unchanged.
  `validate-interview-items.py` refuses a default on an ineligible class
  (**R6**) or a tension item (**R7**), a recalled position that is not
  auditable (**R3**, per candidate), and a `candidates` list outside 1–3
  (**R10**) — so a bad default never reaches the owner.
- **Presentation.** Present the default under the owner-facing proposal
  contract like every other ask (Where/Why/Effect, plain-text payload per
  section (g); the seed quote + `file:line@commit` pointer is the **Why**),
  and **capture it** via `validate-proposal-payload.py --ws --surface interview`.
  **Every presented default counts toward the ≤5 interview cap** — never a
  pre-interview side batch that moves the decision outside the owner-attention
  bound.
- **Ratification — four effect-stating choices, owner judgment throughout:**
  - **Ratify** → "use this recalled position as written" — record with
    `--disposition ratified`: the default text becomes the interview answer as
    **owner judgment** (`interview` provenance), **never** the pointer-inheriting
    `approved` class. The recalled policy pointer is **not** a SOURCE.
  - **Modify** → "edit it, then use it" — `--disposition modified` (owner text,
    no pointers).
  - **Replace** → "discard it, use my own" — `--disposition replaced`.
  - **Skip** → the gap stays an **unresolved NEEDS-OWNER item**, exactly as if
    no default had been offered; only the skip is recorded.
- **Audit (invariant 3).** The recalled position appears only in the `seed<-`/
  `consulted:` records — record it with `journal --seed-extra
  '<pointer>=<gap_type>'`. A factual claim grounded only in a policy line still
  fails the provenance gate or stays `[VERIFY]`; a policy pointer is never a
  SOURCE.
- **Gating (#299 / #306).** Recall a default only under the
  whole-consulted-surface authoring rule (a same-surface companion line
  accompanies or suppresses the recall) and staleness protection (a seed
  predating the material it addresses routes to reversal-candidate handling,
  never a confident default). Consultation uses only the existing pinned,
  bounded, read-only policy reader — no new access path.

**Validate the answers in one batch, not one round-trip per answer (Story 13.6).**
When you have the owner's answers to the surviving questions, pass them all at
once as a JSON list of answer specs and get **one consolidated report of every
rejection** — instead of a reject-and-retry cycle per bad answer, which burns
turns against the pipeline budget (#118):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py answer --batch <answers.json>
```

Each list entry is `{"id", "disposition", "text"?, "pointers"?}` — the same
fields and the **same D2 rules** as the single form. A clean batch emits the
records as a JSON list; any rejection names the offending `id` and the fix, and
the whole batch is a hard gate (non-zero exit) so a malformed answer never
reaches stage 3.

### Interview journal — the boundary diagnostic (Story 10.4)

When Stage 2 finishes, write an **interview journal** to the run workspace, one
entry per **candidate** question, so a mis-asked or mis-suppressed question is
attributable from run state — never discovered by the owner mid-interview:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py journal \
  --interview <interview.json> --answers <answers.json> \
  [--policy-note "policy_source unavailable: <reason>"] > "$WS/interview-journal.json"
```

Each **asked** question records its **survival rationale** (`topic-absent` /
`needs-owner-reraise` / `owner-judgment` / `policy-seed`), the recommendation's
**grounding pointers** (when recommended), the **seed pointers** (when
policy-seeded — the `seed` field, parallel to the grounding), and the owner's
**disposition**; each **suppressed** question records its **covering fact-sheet
entries**. A question asked that the declared sources could in fact answer is
then attributable from the journal — harvest scope gap vs. de-dup miss vs.
triage error — without owner intervention. The command **fails closed** if an
asked question has no recorded disposition, so an unattributable interview
never ships.

**Story-element selection is disclosed in the journal (CAP-9, #428).** For a
lesson-based run, the journal also records, **per selected story element, the
rule that selected it** — the element **id** and its declared reason (e.g.
"Journey-bearing cluster, unconsumed, matched framework slot X"). This is the
audit trail that makes selection reproducible: the same fact sheet selects the
same elements with the same stated reasons. Disclosure only — recording the
reason never changes which elements were selected. A run that selected an
element without a recordable reason fails the same way an undisposed question
does; the completion summary then repeats these reasons for the owner.

**Editorial anchor (SPEC-policy-editorial-direction CAP-2, Story 13.38).** The
journal also records the run's **editorial anchor** — the claim/angle answer:
the first *presented* question whose disposition carries owner text, with
`policy_seeded: true` when a policy tension seeded it (this is what the QSB
run's p1 did by accident, made first-class). The anchor is carried into review
as the **claim intent anchor** (SPEC-review-ux / SPEC-policy-editorial-direction
CAP-3 consume it from the journal). It shapes the article's argument and what
reviewers weight — it **never grounds a factual claim** (no-facts invariant):
its provenance stays exactly what the disposition rules assigned, and it adds
no source pointer. A run whose slot-1 question was skipped simply has no
anchor — nothing is invented.

**The journal ends with the `consulted:` line (Story 14.4, CAP-5).** Its last
key maps every seed to the question it seeded, under the run's pin —
`consulted: <policy-source>@<commit> — LESSONS.md:41 → t1; …` — the /ask-style
audit trail of which policy lines drove which questions. A run that was not
policy-seeded records `consulted: none (policy_source unset)`, or, when the
probe degraded, `consulted: none (policy_source unavailable: <reason>)` via
`--policy-note` — every interview run states its policy provenance, including
the generic ones. Surface the line in the completion summary's informational
notes when it names a pin.

**On request — the policy-influence report.** When the owner asks what the
policy changed in a run, produce the
[policy-influence report](../policy-influence-report.md)
(`${CLAUDE_PLUGIN_ROOT}/skills/policy-influence-report.md`): a view over the
journal + presented payloads + `consulted:` lines — never a second draft or
A/B run, and never emitted unasked (Story 13.40).

### Staging candidates — proposal-only contribute-back (Story 14.5)

After the journal, emit staging-candidate blocks for the policy-seeded tension
questions the owner actually answered (dispositions
`answered`/`modified`/`replaced` — a skip proposes nothing):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py staging-candidates \
  --interview <interview.json> --answers <answers.json> \
  --source-repo <host repo name> --created <run date YYYY-MM-DD> \
  [--tag <track>] > "$WS/staging-candidates.md"
```

Each block mirrors the policy hub's staging-area frontmatter (`slug, created,
source_repo, perishable, tags`) followed by the question and the owner's
decision in full sentences (seam-formats.md §3).

**An answered reconciliation question emits a config↔policy reconciliation
block (Story 13.75, CAP-7).** When the owner answered a `reconciliation` item
(dispositions `answered`/`modified`/`replaced`), the emitter frames its block
as the **config↔policy reconciliation decision**, citing every position it
decided between (the served line at the pin, the config key at its
configVersion). The owner's answer is a **proposed policy change** for
whichever record lost — it is never treated as current policy by this run's
later stages (the plan-gate enforcement is Story 13.76's).

**A staleness-routed item proposes an update, not a resolution (#306).** When
the answered item was a `reversal-candidate` raised because its seed predated
the material (above), the block's question and decision are framed as a
**policy-update proposal for the stale line** — "this recorded position is out
of date; here is what now holds" — never as the resolution of a live tension.
The distinction matters downstream: the owner is being handed a candidate
*correction* to a recorded position, and a block that framed it as a resolved
conflict would record a dispute that never existed. **This is where the tool
stops**: the blocks land in the run workspace only — the owner copies accepted
ones into the hub's staging area by hand, and nothing is ever written into
the policy hub (the consumer holds no hub path at all — Story 13.73; the
gateway serves read-only). A run with no answered tension questions emits
nothing —
never an empty block. When candidates were emitted, the completion summary's
**informational notes** must name the file (`$WS/staging-candidates.md`) and
the block count, so a proposal is never silently buried in run output.

### Stage 2→3 policy-block gate — draft generation blocks on a conflict/stale plan (Story 13.77)

**After the answers are recorded (and staging candidates emitted), before any
Stage 3 fill**, run the stage-progression precondition
(SPEC-article-draft-pipeline, 2026-07-18 amendment: draft generation blocks on
a conflict or stale plan — like the quality gate, never silently proceeded
past). It is mechanical (no LLM):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py policy-block-check \
  --classification "$WS/policy-classified.json" --answers <answers.json> \
  > "$WS/policy-block.json"
```

**Resumed-run half (autostart):** when a resumed run already has an emitted
article plan (a prior invocation reached plan emission), the plan's recorded
CAP-4 conformance status **re-validates before Stage 3+ continues** — pass the
plan, and the fresh surface so the status is **recomputed at the current pin**
through the 13.76 `conformance` machinery (read-only — same table, same rules,
one implementation):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py policy-block-check \
  --plan <plans/<slug>.md> --surface "$WS/policy-surface.txt" \
  --root <host-repo> [--staging "$WS/staging-candidates.md"]
```

Branch on the JSON:

- **`blocked: false`** (`conformant` / `open` / answered reconciliation) —
  proceed to Stage 3 unchanged.
- **`blocked: true`** (`action: publish-blocker`) — **surface the
  `publish_blocker` payload in-conversation** (it names the conflicting
  positions with their pointers, or the moved pin/configVersion — never a bare
  status), **write the block checkpoint, and STOP the run**: checkpoint the
  output's suggested `checkpoint` object —
  `{"stage": "policy-block", "next_stage": "interview"}` — via
  `checkpoint --ws "$WS"`, so the run resumes **at the block** and the
  reconciliation question **re-presents on resume**; never checkpoint before
  Stage 2, and never `next_stage: fill` (that would resume past the gate).
  The completion summary's **publish-blockers bucket** carries the payload
  (positions/pin delta included) and the resume path.
- **In-run repair** — the block is repairable in the same invocation:
  - **conflict** → if the owner answers the reconciliation question now
    (CAP-7), record it via `answer` and **re-run the check** — any recorded
    decision unblocks, **including a reversal**, which proceeds as a proposed
    policy change through its staging-candidate block (never as current
    policy);
  - **stale** → **re-consult at the current pin**: re-run the policy reader
    (`read-policy-source.py read`), `classify-policy`, and the conformance
    recompute against the fresh surface, then re-run the check — it proceeds
    or re-blocks per the new status (a recorded `stale` whose referenced
    lines still hold at the new pin clears to `conformant`).
- **Generic mode never touches the gate**: with no `policy_source` toggle (or
  reader exit 10) there is no classification and no policy-seeded plan, and
  the check returns `{blocked: false, reason: "generic-mode"}` — behavior
  identical to a repo without the seam.

This gate is a **separate precondition at the same boundary** as the quality
gate: it changes nothing about the quality gate or `[VERIFY]` markers.

## Stage 3 — fill the framework (with `[VERIFY]` markers)

Fill the chosen framework's slots from the fact sheet and the interview answers.

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

Then fill **from the plan** — each section realizes its intent, drawing the
named entries — rather than populating slots directly. This is a **sub-step**,
not a new pipeline stage, and **provenance is unchanged**: every checkable claim
is still sourced/derived, synthesis stays legal in connective tissue. The plan
is a **run-workspace intermediate** and is **owner-visible** — the completion
summary names the thesis and arc the draft was composed from (CAP-2), and at
completion the plan-record `plans/<slug>.md` projects them from this finalized
plan (SPEC-article-plan, unchanged). A section whose intent is under-evidenced
(its named entries are thin) is visible **here, before fill**; the Stage 3→4
gate fails a slot that ships as a single under-evidenced sentence.

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
[`frameworks/CONVENTIONS.md`](frameworks/CONVENTIONS.md)) and apply exactly it —
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
review), one line per sentence keyed by paragraph/sentence position; when
Stage 3 completes, the full map is validated as below:

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
[**owner-facing proposal contract**](../owner-facing-proposal-contract.md)
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

Validate the assembled plan (the cap + the zero-plan-no-padding rule) with:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-visual-set.py --slot-count <n> "$WS/visual-set-plan.json"
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
[**owner-facing proposal contract**](../owner-facing-proposal-contract.md)
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
3. **figure spec** — elements, relations, emphasis, and a caption;
4. a **copy-paste-ready image-generation prompt** derived from the figure spec,
   including **"no embedded text"** guidance and an **aspect ratio**;
5. **ASCII** — **simple structures only**.

Prefer a **markdown table over a diagram** whenever the content is comparative
rather than topological. Every non-reused visual in a draft is therefore one of:
Mermaid source, a figure spec, an image-generation prompt block, or ASCII —
**never a bare `[Figure: …]` placeholder**.

**No rendering (NFR9).** This step produces **source only**: it never invokes
`mermaid-cli`, any image tooling, or an image-generation API — rendering is the
owner's tooling. The plugin bundles no such tools.

## Stage 3→4 — mandatory quality gate (Story 11.4)

Before the draft reaches the owner's verification pass, it must **pass the
article-quality gate** ([`quality-rubric.md`](quality-rubric.md)). This is a
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
skeleton/stitched checks), [`quality-rubric.md`](quality-rubric.md) (the dim1
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
  KINDs anchored into that section. A section filled without its declared
  type is a **missing-input finding** — the gate output's
  `evidence_types.missing_input[]` carries a ready-made `upstream` line;
  route it through `repair-hop` (below), **never** backfill the section with
  unrelated factual material and never report success past it. An unrepaired
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
  ([`quality-rubric.md`](quality-rubric.md)) and is what lets the second-cycle
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
  --upstream "re-harvest bench/results.md"   # or: "ask <one bounded question>"
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

- `re-harvest <target>` → re-enter **harvest** narrowed to that scoped target;
  the new facts are pinned exactly like any Stage-1 fact (declared-scope
  boundary and pin rules unchanged), and a policy line never becomes a SOURCE.
- `ask <question>` → re-enter the **interview** with exactly one owner-facing
  question under the proposal contract; the answer records as owner judgment
  (interview provenance), never a SOURCE.

This is the **only** backward edge to harvest/interview beyond the rewrite
route above, and it counts against the **same two-cycle bound** as
rewrites/gate revisions. Pass the cycles already spent on this draft as
`--cycle N`; when the cap is reached the command emits a **publish blocker**
(`action: publish-blocker`, `publishable: false`) instead of a third hop — the
unrepaired missing-input gap routes to the completion summary's
publish-blocker bucket (CAP-6), exactly as an unresolved rubric/config blocker
forces "not publishable":

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py repair-hop \
  --upstream "re-harvest bench/results.md" --cycle 2   # -> publish-blocker, no third hop
```

A within-budget hop returns the incremented `cycle` so the next stage carries
it forward. A hop interrupted at the turn ceiling resumes from the checkpoint
like any stage.

A **fact-sheet-stitched draft fails** this gate (dimension 4) and does **not**
reach Stage 4 unrevised.

## Stage 4 — owner verification pass

A bounded pass where the owner resolves the draft's `[VERIFY]` markers within a
**≤4 minute** owner-attention budget. Exit criterion: **zero `[VERIFY]` markers remain**.
Build the owner's worklist:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py verify <draft>
```

This lists every well-formed marker with its **line and reason** (a malformed
marker blocks the pass — Stage 3 must have produced canonical `[VERIFY: <reason>]`
forms). Present each marker to the owner under the
[owner-facing proposal contract](../owner-facing-proposal-contract.md): **where**
the claim sits in the article (its section, with the surrounding sentence as a
preview), **why** it is flagged (the marker's reason), and choices whose labels
state their **concrete effect on the article** — never a shorthand. A first-time
owner answers from **repository knowledge alone**. Resolve **each** marker to
exactly one of:

1. **replace the claim with its source** — the claim was verifiable after all;
   swap the marker for the source pointer (`path:line@sha` / sha / URL);
2. **keep the claim, marked as an unmeasured estimate** — the owner vouches for
   it; drop the marker;
3. **remove the claim from the article** — it cannot be supported; delete it.

The pass is done when the Stage-3 gate reports zero:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py verify-markers --count <draft>   # -> 0
```

**More than one rewrite routes back to a question, never open-ended editing.**
A section gets **one** rewrite in this pass. If the owner asks for a further
change, do not keep editing — reroute it into a new, bounded interview question:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py reroute --section <id> --rewrites <n>
```

With `n` = rewrites already applied to that section, this returns `decision:
edit` while a rewrite remains, or `decision: reroute` (with `next_stage:
interview` and a bounded question) once the budget is spent. Ask the rerouted
question, capture the bullet answer verbatim as in Stage 2, and apply it — the
draft never drifts into unbounded editing.

Stage 4 exit: zero unmarked invented claims, zero `[VERIFY]` markers — the draft
is ready for the article plan and the `complete` gate. Variant emission is
**not** part of this flow (see the pointer section below).

## Emit the article plan (SPEC-article-plan CAP-1/CAP-2, Story 13.55)

At run completion — after the verified draft exists — emit the run's editorial
decisions as an **article plan** at `plans/<slug>.md` in the articles
repository, so they survive the disposable workspace and a later run can
consult them (Story 13.57). The plan is a **deterministic projection** of
artifacts this run already produced (journal, editorial anchor, dispositioned
answers, visual decisions, unresolved items) — **no new owner interaction**,
and regenerating it from the same artifacts is byte-identical.

Assemble the plan text from run state and hand it to the sanctioned writer,
which validates fail-closed and places it. **Every source pointer in the plan
body must be pinned — `path:line@sha`, never bare `path:line` (#410, Tanuki
F81): the writer's schema refuses unpinned pointers every time.** Carry
pointers verbatim from the artifacts the plan projects (fact sheet, journal,
visual-set plan — all already pinned); never re-derive or hand-type a pointer
at assembly. First-attempt validity is the contract; the refusal is recovery:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/write-article-plan.py write \
  --slug <slug> --root <host-repo> "$WS/article-plan.md"
```

### Policy-conformance gate (SPEC-article-plan CAP-4, Story 13.76)

When the run consulted the policy seam (Stage 2 wrote `$WS/policy-surface.txt`),
run the conformance gate on the assembled plan **before** handing it to
`write` — a policy-seeded plan without conformance data is refused by the
writer:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/write-article-plan.py conformance \
  --plan "$WS/article-plan.md" --surface "$WS/policy-surface.txt" \
  --root <host-repo> [--staging "$WS/staging-candidates.md"] --write
```

- The gate validates every policy-seeded decision the plan records against
  the **same pinned policy result** the run consulted and the authoritative
  user config, then `--write` records `policy_pin`, `policy_config_version`,
  and `policy_conformance` (∈ `conformant`/`open`/`conflict`/`stale`) into
  the plan's frontmatter through the writer's fail-closed validation. The
  recorded status **rides the plan**.
- At plan emission a `conflict` or `stale` status is **recorded, not blocking**
  — the stage-progression block fired earlier, at the Stage 2→3 boundary
  (`policy-block-check`, Story 13.77), and the recorded status is what that
  gate **re-validates on the next resumed run** before Stage 3+ continues.
  Relay the status (and the findings' positions/pointers) in the completion
  summary's informational bucket.
- Pass `--staging` when the run emitted staging candidates: a plan decision
  that **reverses a served ratified line** is conformant **only as a proposed
  policy change** (its staging-candidate block exists →
  `reversal_as_proposal: true`); without the block it stays `conflict`. The
  reversal is never treated as current policy.
- The gate writes **nothing to any policy hub** — with `--write` it touches
  exactly one file: the plan.

- The frontmatter is the closed schema (SPEC-article-plan CAP-2): `kind:
  article-plan` (constant, the machine marker that keeps a plan **out of the
  evidence stream**), `slug` (equal to the filename stem), `intent`, `claim`,
  `status` (`outlined`/`drafted`/`superseded`), `run_id`, `pin`
  (`<source-repo>@<commit>`); optional `audience`, `policy_seeded`+`seed`,
  `relates`, and the CAP-4 conformance trio `policy_pin` /
  `policy_config_version` / `policy_conformance` (all three **required** when
  `policy_seeded: true` — the conformance gate below records them). Everything the draft or its variants own (title, summary, topics,
  language, …), machine state (journal/checkpoint/provenance map), and
  free-text `evidence:` are **forbidden** — the writer refuses them with
  per-key diagnostics. Every evidence reference in the **body** is a
  commit-pinned pointer or an interview-answer id, never prose.
- **Only the plan file is emitted.** No journal, checkpoint, or
  provenance-map data lands in the articles repository, and **nothing is
  written to the host source repo** — the footprint invariant is untouched.
- **Schema-less destination fallback.** If `output.drafts` points somewhere
  without the articles-repo schema, the writer lands the plan in user-scoped
  state (keyed by repo + slug, draft association intact) and creates **no**
  `plans/` directory in that destination. The write succeeds either way;
  check `dest --slug <slug>` first if you need to tell the owner where it went.

## Completion summary

End every run with the shared
[**completion summary**](../completion-summary.md)
(`${CLAUDE_PLUGIN_ROOT}/skills/completion-summary.md`): the three labelled buckets
— **informational notes**, **publish blockers**, **optional cleanup** — followed
by an explicit **next step presented as an in-conversation choice** (here: "run
review-article on the draft / stop here" — interaction contract, CAP-6/#226:
paths are reference information, never a required navigation step). Because
this run produces an **article body**, the informational bucket includes a
**reading-time estimate**:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/reading-time.py --language <en|ja> <draft>
```

The informational bucket also names **both persisted product paths** —
`drafts/<slug>.md` and `plans/<slug>.md`, copy-pasteable, taken verbatim from
the `complete` subcommand's JSON (the dual-product completion gate, Story
13.68). A run whose `complete` invocation failed has no completion to
summarize: surface the gate's hard error instead.

Any unresolved `[VERIFY]` marker or unrendered figure is a **publish blocker**,
listed under that bucket and nowhere else. A run stopped by the Stage 2→3
policy-block gate (Story 13.77) lists its block there too: the bucket carries
the `publish_blocker` payload — the conflicting **positions with pointers**, or
the moved pin/configVersion — plus the **resume path** (the block checkpoint;
resume re-presents the reconciliation question).

**Partial progress and the turn budget — the signal is an orderly stop, not an
advisory (Story 13.7; hardened by Story 13.85, #388).** The turn/compute
budget is a real ceiling. When a stage's budget-triage signal fires (a bounded
repair loop breached, or the invocation is visibly near its ceiling), do not
push on to hard failure — **stop in order**:

1. **Finish only the unit in progress** — never start a new source, section,
   or repair pass after the signal;
2. **persist at that boundary** — the sub-stage recording (Stories
   13.83/13.84) or, at a stage edge, the normal stage checkpoint — passing
   the partial-progress note on the final recording:

   ```
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py progress --ws "$WS" --stage <stage> --done <unit> \
     --stop-note "stopped at <boundary>; remaining: <what's left>"
   ```

3. **exit clean** — end the invocation with a short message naming the
   boundary reached and the resume path (autostart continues the run). A
   clean stop is a **normal end of an invocation**, distinguishable from
   failure; `error_max_turns` or a wall-timeout is a defect of this stop
   mechanism, never the expected end of an over-budget run.

On resume, `autostart`/`resume` return the recorded `budget_stop` note —
relay it in the completion summary's **informational notes** (last completed
boundary + resume path, per the shared completion-summary contract); the next
recording without a stop-note clears it. A partial run is recoverable, never
a silent loss.

## Platform variants — a separate post-review invocation

Variant emission is **not a stage of this flow** (SPEC-article-draft-pipeline
CAP-4; SPEC-platform-variants CAP-3, 2026-07-18 amendments). The draft flow
ends at the `complete` gate, with next step **review-article** — no platform
decision is presented during a draft run. Variants are emitted later, post-
review, by a standalone invocation that consumes the **persisted canonical**
at `<output.drafts>/<slug>.md` (SPEC-platform-variants CAP-1) — never a
workspace copy:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py variants --slug <slug> --root <host-repo>
```

The full contract — platform listing, the owner's explicit emission choice,
the lede re-targeting proposal, per-platform visual rendering, the platform
lint, the stale-variant check, the post-publish site record, and those
subcommands' flag reference — lives in [`variants.md`](variants.md)
(`${CLAUDE_SKILL_DIR}/variants.md`). A canonical that exists only in a run
workspace is refused there with a pointed error naming the expected persisted
path — run `complete` first.

## Pipeline command reference (`draft-pipeline.py`)

Every draft-flow subcommand of `${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py`, in
pipeline order. This is the authoritative flag list — consult it instead of
`--help` or the script source. Positional args are shown in `<angle brackets>`;
`-` means "read from stdin". The variant-emission subcommands (`variants`,
`variant-staleness`, `site-record`) are post-review, not part of this flow —
their reference lives in [`variants.md`](variants.md).

| Subcommand | Stage | Purpose | Args / flags |
|---|---|---|---|
| `stage0` | 0 | Config validation (CAP-5) + framework check + workspace autostart in one call (Story 13.13) | `<framework> <sources…>` `--root` |
| `start` | 0 | Framework check + run-state only, no workspace (granular alternative to `stage0`) | `<framework> <sources…>` `--root` |
| `autostart` | 0 | Resume the newest in-progress run, else mint a fresh workspace (Story 13.12) | `--root` |
| `checkpoint` | durability | Persist a completed stage's state to `<ws>/checkpoint.json` (Story 13.5) | `--ws` (req) `<state\|->` |
| `resume` | durability | Report where to resume a run from its workspace checkpoint | `--ws` (req) |
| `progress` | durability | Record sub-stage progress (completed units inside a long stage) into the checkpoint (Story 13.83); with `--stop-note`, records an orderly budget stop (Story 13.85) | `--ws` (req) `--stage` (req) `--done` (req, 1+) `--stop-note` |
| `consume` | 1 | Ingest the harvest fact-sheet document into pipeline state | `<harvest-doc\|->` |
| `interview` | 2 | Build the bounded gap-interview question set for the framework | `--framework` (req) `<state\|->` |
| `answer` | 2 | Record one owner answer (single form), or validate a batch | `--id` `--disposition` `--text` `--pointer` (repeatable) `--batch` |
| `journal` | 2 | Write the interview journal (triage record, Story 10.4) | `--interview` (req) `--answers` |
| `policy-block-check` | 2→3 | Stage-progression precondition (Story 13.77): blocks Stage 3 fill on an unresolved config↔policy conflict or a `conflict`/`stale` plan, emitting the publish-blocker payload + block checkpoint; `conformant`/`open` and generic mode proceed | `--classification` `--answers` `--plan` `--surface` `--config-json` `--root` `--config-version` `--staging` |
| `provenance` | 3 | Parse + structurally validate the sidecar provenance map | `--map` `--count` `--draft` |
| `quality-gate` | 3→4 | The mandatory quality gate; non-zero exit blocks Stage 4 (Story 11.4) | `--draft` `--map` `--judge` `--framework-file` `--state` `--profile` |
| `verify-markers` | 3/4 | Validate `[VERIFY: reason]` markers; `--count` prints the count (drive to 0) | `<draft\|->` `--count` |
| `verify` | 4 | Build the owner verification worklist, one entry per marker | `<draft\|->` |
| `reroute` | 4 | Reroute an over-budget section into a new bounded interview question (Story 4.5) | `--rewrites` (req) `--section` |
| `complete` | completion | The dual-product completion gate (Story 13.68): persist the canonical to `<output.drafts>/<slug>.md`, verify `plans/<slug>.md`, then (and only then) write the `next_stage: done` checkpoint; the only sanctioned way to finish a run | `--draft` (req) `--slug` (req) `--root` `--ws` |
