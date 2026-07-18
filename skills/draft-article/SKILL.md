---
name: draft-article
description: >
  Draft a technical article from a repository's own material. Invoke as
  "draft article <article-type> from <sources>" to run the pipeline: harvest →
  gap interview → framework fill → verification → platform variants. Article
  types are intent labels — "introduce the project", "share engineering
  lessons", "explain the evaluation methodology", "survey a research area"
  (F1-F4 remain the internal/expert alias); sources are paths, globs, or
  commit ranges.
---

# Draft article

One invocation kicks off the whole harvest-to-variant flow:

```
draft article <article-type> from <sources>
```

- **article-type** — an **intent label**: "introduce the project", "share
  engineering lessons", "explain the evaluation methodology", or "survey a
  research area". The framework ids `F1`–`F4` keep working as the
  internal/expert alias (see
  `${CLAUDE_PLUGIN_ROOT}/skills/draft-article/frameworks/`); both forms
  resolve through `resolve_framework` in the pipeline helper — a closed
  mapping, never fuzzy-matched.
- **sources** — any mix of paths, globs (`src/**/*.py`), and commit ranges
  (`HEAD~20..HEAD`).

**No article type given?** Ask by intent, in-conversation (proposal contract):
offer the four intent labels with a **repo-grounded recommendation** — e.g. a
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
  `F1`–`F4` aliases (`resolve_framework`) — an invalid name exits non-zero and
  **nothing starts** (no workspace minted). Relay and stop; the error names the
  valid intent labels.
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
products at `output.drafts` (Stage 5). Pass `$WS` to Stage 1 so harvest writes
there rather than minting its own workspace.

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
pin, relates). From these you **may surface plan-grounded proposals** — each
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

**Mark the run done on completion.** When the pipeline finishes (Stage 5
variants emitted), write a final checkpoint with `next_stage: done` so
`autostart` treats the run as complete and starts fresh next time rather than
re-resuming it:

```
printf '{"stage":"variants","next_stage":"done"}' | \
  python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py checkpoint --ws "$WS" -
```

Checkpoint state lives under `$WS` with the other intermediates
(`docs/storage-architecture.md` D2), never in the host tree.

**Resumed-run audience recheck (Story 13.41 — stage 0's half of the presence
rule).** When `stage0`/`autostart` resumes a run (`"resumed": true`) whose
`next_stage` is `verify` or `variants` — i.e. a filled draft already exists among
the intermediates — confirm that draft carries a **resolved `audience`** before
continuing (a run checkpointed before the audience precondition existed may lack
it). If it is missing or still `{audience}`, fill it per the Stage-3 rule and
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

## Stage 2 — bounded gap interview

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
  answer, never a recommendation (NFR15: triage and recommendations stay a
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
- **10** (`policy_source` unset) — generic interview, **silently**: no items,
  no log line, behavior identical to a repo without the seam.
- **11 / 12** (path missing / not a git repo) — the reader printed exactly one
  `policy_source unavailable: <reason>` line; **relay that one line once** and
  continue with the generic interview. Do not retry, do not warn again — one
  line, then generic mode. Keep the reason: the journal's `consulted:` line
  records it (`--policy-note`).
- **4** (malformed block) — a stage-0 configuration error slipped through;
  halt and report it like any CAP-5 finding (this cannot happen after a clean
  `stage0`).

Then select the interview questions from the stage-1 state (with policy items
when the probe produced them):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py interview --framework <F> \
  [--items "$WS/policy-items.json"] <state>
```

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
one (NFR15).

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
  open and nothing is padded;
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

- **Item shape (Story 13.59).** Carry the recalled position on the interview
  item as `recommended_default {default, quote, pointer}`, with `owner_answer`
  structurally empty at generation. `validate-interview-items.py` refuses a
  default on an ineligible class (**R6**) or a tension item (**R7**), and one
  whose recalled position is not auditable (**R3**) — so a bad default never
  reaches the owner.
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

**A staleness-routed item proposes an update, not a resolution (#306).** When
the answered item was a `reversal-candidate` raised because its seed predated
the material (above), the block's question and decision are framed as a
**policy-update proposal for the stale line** — "this recorded position is out
of date; here is what now holds" — never as the resolution of a live tension.
The distinction matters downstream: the owner is being handed a candidate
*correction* to a recorded position, and a block that framed it as a resolved
conflict would record a dispute that never existed. **This is where the tool
stops**: the blocks land in the run workspace only — the owner copies accepted
ones into the hub's staging area by hand, and nothing is ever written under
`policy_source.path`. A run with no answered tension questions emits nothing —
never an empty block. When candidates were emitted, the completion summary's
**informational notes** must name the file (`$WS/staging-candidates.md`) and
the block count, so a proposal is never silently buried in run output.

## Stage 3 — fill the framework (with `[VERIFY]` markers)

Fill the chosen framework's slots from the fact sheet and the interview answers.

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

**Fill `audience` here (Story 13.41 — this is where the field is born).** The
skeleton carries a pipeline-internal `audience: {audience}` slot: replace it with
the **one named reader** — from the interview's audience answer (q5) when one was
given, from the backlog item's declared audience when drafting from the backlog,
or from the owner's draft-start declaration otherwise. Never leave the `{audience}`
placeholder: the stage 3→4 quality gate fails on it (a stage-progression
precondition), and the variant stage hard-stops as backstop. The field is
pipeline-internal — variant packaging strips it, and it never enters the site
schema.

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

**The sidecar provenance map.** When Stage 3 completes, write a **sidecar
provenance map** to the run workspace (never inline — the draft body stays clean
for variants and review), one line per sentence keyed by paragraph/sentence
position:

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

It resolves every `derived` (and `sourced`) pointer against the declared
fact-sheet entries **mechanically**, and consumes the **isolated judge
subagent's** verdicts for the semantic tests — a `narration` sentence that asserts
a checkable proposition **fails the falsifiability test** (a gate failure), and a
`derived` claim adding any of the six forbidden categories is a gate failure.
**Spawn a cheap-tier judge subagent** and hand it *only* the sentences
`--list-narration` / `--list-derived` surface **plus the fact-sheet entries they
cite** — never the drafting rationale, the interview, or your reasons for each
classification. The subagent writes its pass/fail verdicts to
`$WS/provenance-verdicts.txt`, which the command consumes. A clean map passes
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
Validate the assembled plan (the cap + the zero-plan-no-padding rule) with:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-visual-set.py --slot-count <n> "$WS/visual-set-plan.json"
```

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
  "revise the source, then insert", *decline* → "omit the visual; the slot
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

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py quality-gate \
  --draft <draft> --map "$WS/provenance-map.txt" --judge "$WS/rubric-verdicts.txt"
```

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

1. Stage 3 **revises against the named failing dimensions only**, then re-runs
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
is ready for platform variants.

## Stage 5 — platform-ready variants

Emit platform-ready copies of the **verified** draft as **projections** of the
canonical draft. Which platforms, and each one's canonical policy, come from user
config (`syndication.policy` / `syndication.variants`) keyed by the draft's
`language` — **never a hardcoded mapping**; **how** each variant is packaged
(frontmatter fields, tag cap, `canonical_url` format, diagram-`visuals`
treatment) comes entirely from that platform's **profile** (a machine-global
declaration, SPEC-platform-variants CAP-2), so there is no per-platform code path
and adding a platform is one profile file.

**Emission is the owner's explicit publish decision (CAP-6/#226) — the pipeline
never auto-emits every configured platform.** First read the choices, then
present them **in-conversation** as a selection (never a path to open):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py variants <draft> --list-platforms
```

Offer the owner: *emit each `available` platform / both / stop here.* Then emit
exactly their choice (a comma-separated subset, or `all`):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py variants <draft> --platforms <chosen>
```

The **completion summary records the choice and its outcome** — which platforms
were offered, which the owner emitted, and where each file landed (an owner who
picks only one platform leaves no file for the others, anywhere).

- **Precondition:** the draft carries **zero `[VERIFY]` markers** — Stage 4 must
  be complete. Any unresolved marker aborts the stage. The draft must also
  declare a resolved `audience` (the named reader) — an unfilled one is a hard
  stop.
- **Lede re-targeting proposal (Story 16.5), the variant's only owner
  touchpoint.** For each emitted variant the pipeline fires a **deterministic
  trigger** — it compares the draft's declared `audience`/`language` against the
  profile's. When they **differ** (e.g. a Zenn/JA profile for an EN draft) the
  variant carries `lede_retarget: true` and a `lede_proposals` entry. Perform
  **exactly one** judgment step for it: re-target the lede and framing to the
  profile's named reader (です/ます register for `ja`) **without introducing any
  claim absent from the canonical draft**, and present it under the
  [owner-facing proposal contract](../owner-facing-proposal-contract.md)
  (approve / modify / replace). When audience and language **match**, emission is
  pure packaging — **no proposal, no touchpoint**. The trigger is never your
  judgment over content; there is no `lede_retarget` profile field.
- **Emission metadata:** each emitted variant carries the canonical draft's
  content hash (a trailing `canonical-sha256` comment) so a later run can flag a
  variant whose source draft has since changed (Story 16.7).
- **Projection, not rewrite:** the body carries over unchanged (claims, evidence,
  provenance, section structure); only frontmatter/packaging and the profile's
  declared visual treatment differ from the canonical draft.
- **EN / `mode: canonical`** (dev.to-style profile) → the full article text with
  the profile's frontmatter, whose `canonical_url` is composed from the owner's
  base value and the profile's format, pointing back at the site page.
- **JA / `mode: external`** (Zenn-style profile) → a repo-sync copy with the
  profile's frontmatter and the full body — the platform is canonical via
  repo-sync, so its profile declares `canonical_url: {policy: none}`. A profile
  whose `packaging.visuals` cannot render Mermaid HTML-comments each diagram and
  raises a render publish blocker (reported as `render_blockers`).
- Each variant is written to the **resolved `output.drafts`** location (Story
  1.3; `--out <dir>` overrides). Files are named `{slug}.{platform}.md`.
- **`output.drafts` may live outside the host repo — and should (#213):** the
  recommended destination is a directory in the owner's **private articles
  repository** (`~`/absolute paths supported; a relative value keeps resolving
  against the host root). When `output.drafts` is **undeclared**, ask the owner
  once, recommending that external default and saying why — articles are private
  assets and a host repo may be public — then record the answer with
  `resolve-writing-sources.py set-draft-location <path>` (it writes to the
  machine-global config, never into the host repo). When the resolved external
  directory **does not exist**, the stage stops and names it: confirm the
  location with the owner, then re-run with `--create-out` (or create it by
  hand) — the pipeline never silently creates directory trees outside the host.

### Visual rendering per platform (SPEC-article-visuals CAP-5)

The two platforms render diagrams differently, so each variant handles a
Mermaid/figure-spec visual its own way:

- **Zenn variant** — **embeds the Mermaid source directly** (a ` ```mermaid ` code
  block). Zenn renders it natively, so the diagram appears with **zero manual
  work**.
- **dev.to variant** — dev.to does **not** render Mermaid, so the variant carries
  the **Mermaid/figure-spec inside an HTML comment** (`<!-- … -->`, invisible until
  rendered) and lists **each unrendered figure as a publish blocker** ("render to
  image before publishing") in the **completion summary's publish-blocker bucket**
  (Story 7.5 / CAP-6). The owner renders it to an image before publishing.

A **figure-spec** visual (no Mermaid) is handled the same way per platform: shown
where the platform can render it, otherwise carried in a comment and blocker-listed.

Each variant is publishable on its platform with **no manual reformatting beyond
filling the canonical URL**. The draft then exits this pipeline into
SPEC-article-review (`next_stage: review`).

### Platform lint — every emitted variant gets it (Story 13.41, CAP-5)

Immediately after emitting each variant, run the **profile-parameterized
mechanical lint** on it (zero LLM tokens; each defect reported `path:line`):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/lint-platform-variant <variant-file> \
  --root <host-repo> --ws "$WS" [--dest-repo <output.drafts repo root>]
```

Pass `--dest-repo` when the profile declares a target directory layout so the
existence check runs against the **`output.drafts` destination repo**. A lint
defect is a **publish blocker** for that variant (CAP-6 bucket) — relay each
finding; never re-run a structure/prose/cold-read pass on a variant.

### Stale-variant check — before any publish handoff (Story 13.41, FR60)

On a **resumed run** that already emitted variants, and always **before handing
variants to the owner for publishing**, verify no variant's canonical draft has
moved since emission:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py variant-staleness <draft> --root <host-repo>
```

Any `publish_blockers` entry (`stale-variant` / `unrecorded-canonical-hash`)
goes to the completion summary's blocker bucket. The remedy is structural: route
the change to the canonical draft, **re-emit** the variant (which records the
new hash), never edit the variant in place.

### Post-publish next step — the site's external record (Story 13.41, FR62)

For a variant whose language maps to `mode: external` in `syndication.policy`
(the site holds a record, not the body), the completion summary's next-step
choice includes — **after the owner publishes** — "confirm the published URL →
generate the site record". This runs **outside** the per-article attention
budget (post-publish), and the offer is **re-presentable on any later
invocation** until the owner confirms; it is never silently dropped:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py site-record <draft> \
  --url <final published URL> [--date <real publication date>] --ws "$WS"
```

The output is a **ready-to-paste proposal** (≤ line budget, body forbidden)
written to `$WS` only — applying it to the site tree is the owner's act; the
pipeline never writes the site tree. Without `--url` it reports the offer as
pending — re-offer it next invocation.

## Emit the article plan (SPEC-article-plan CAP-1/CAP-2, Story 13.55)

At run completion — after the verified draft exists — emit the run's editorial
decisions as an **article plan** at `plans/<slug>.md` in the articles
repository, so they survive the disposable workspace and a later run can
consult them (Story 13.57). The plan is a **deterministic projection** of
artifacts this run already produced (journal, editorial anchor, dispositioned
answers, visual decisions, unresolved items) — **no new owner interaction**,
and regenerating it from the same artifacts is byte-identical.

Assemble the plan text from run state and hand it to the sanctioned writer,
which validates fail-closed and places it:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/write-article-plan.py write \
  --slug <slug> --root <host-repo> "$WS/article-plan.md"
```

- The frontmatter is the closed schema (SPEC-article-plan CAP-2): `kind:
  article-plan` (constant, the machine marker that keeps a plan **out of the
  evidence stream**), `slug` (equal to the filename stem), `intent`, `claim`,
  `status` (`outlined`/`drafted`/`superseded`), `run_id`, `pin`
  (`<source-repo>@<commit>`); optional `audience`, `policy_seeded`+`seed`,
  `relates`. Everything the draft or its variants own (title, summary, topics,
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

Any unresolved `[VERIFY]` marker or unrendered figure is a **publish blocker**,
listed under that bucket and nowhere else.

**Partial progress and the turn budget (Story 13.7).** The turn/compute budget is
a real ceiling. As a stage nears it,
**surface a budget-triage signal before hard failure** so the run can be
checkpointed (Story 13.5) and resumed rather than lost at `error_max_turns`.
When a run stops short or is resumed, the
completion summary reports the **last completed stage and the resume path** under
informational notes — read from `draft-pipeline.py resume --ws "$WS"` — per the
shared completion-summary contract; a partial run is recoverable, never a silent
loss.

## Pipeline command reference (`draft-pipeline.py`)

Every subcommand of `${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py`, in
pipeline order. This is the authoritative flag list — consult it instead of
`--help` or the script source. Positional args are shown in `<angle brackets>`;
`-` means "read from stdin".

| Subcommand | Stage | Purpose | Args / flags |
|---|---|---|---|
| `stage0` | 0 | Config validation (CAP-5) + framework check + workspace autostart in one call (Story 13.13) | `<framework> <sources…>` `--root` |
| `start` | 0 | Framework check + run-state only, no workspace (granular alternative to `stage0`) | `<framework> <sources…>` `--root` |
| `autostart` | 0 | Resume the newest in-progress run, else mint a fresh workspace (Story 13.12) | `--root` |
| `checkpoint` | durability | Persist a completed stage's state to `<ws>/checkpoint.json` (Story 13.5) | `--ws` (req) `<state\|->` |
| `resume` | durability | Report where to resume a run from its workspace checkpoint | `--ws` (req) |
| `consume` | 1 | Ingest the harvest fact-sheet document into pipeline state | `<harvest-doc\|->` |
| `interview` | 2 | Build the bounded gap-interview question set for the framework | `--framework` (req) `<state\|->` |
| `answer` | 2 | Record one owner answer (single form), or validate a batch | `--id` `--disposition` `--text` `--pointer` (repeatable) `--batch` |
| `journal` | 2 | Write the interview journal (triage record, Story 10.4) | `--interview` (req) `--answers` |
| `provenance` | 3 | Parse + structurally validate the sidecar provenance map | `--map` `--count` `--draft` |
| `quality-gate` | 3→4 | The mandatory quality gate; non-zero exit blocks Stage 4 (Story 11.4) | `--draft` `--map` `--judge` |
| `verify-markers` | 3/4 | Validate `[VERIFY: reason]` markers; `--count` prints the count (drive to 0) | `<draft\|->` `--count` |
| `verify` | 4 | Build the owner verification worklist, one entry per marker | `<draft\|->` |
| `reroute` | 4 | Reroute an over-budget section into a new bounded interview question (Story 4.5) | `--rewrites` (req) `--section` |
| `variants` | 5 | Emit platform-ready variants as profile-driven projections; emission is the owner's explicit choice — no `--platforms` reports options and emits nothing | `<draft>` `--platforms <ids\|all>` `--list-platforms` `--config-json` `--root` `--global-config` `--repo-config` `--out` `--create-out` `--ws` `--dry-run` |
| `variant-staleness` | 5/post | Compare each variant's recorded canonical hash against the current draft; mismatches are publish blockers (Story 16.7) | `<draft\|->` `--variants <files…>` `--out` `--root` |
| `site-record` | post-publish | Propose the site's `mode: external` record after the owner confirms the published URL (Story 16.9); proposal lands in `$WS` only | `<draft\|->` `--url` `--date` `--config-json` `--root` `--global-config` `--repo-config` `--ws` |
