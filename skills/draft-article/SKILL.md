---
name: draft-article
description: >
  Draft a technical article from a repository's own material. Invoke as
  "draft article <F1-F4> from <sources>" to run the pipeline: harvest → gap
  interview → framework fill → verification → platform variants. Frameworks are
  F1 (project intro), F2 (engineering lessons), F3 (evaluation methodology),
  F4 (research survey); sources are paths, globs, or commit ranges.
---

# Draft article

One invocation kicks off the whole harvest-to-variant flow:

```
draft article <framework> from <sources>
```

- **framework** — one of `F1`, `F2`, `F3`, `F4` (see
  `${CLAUDE_PLUGIN_ROOT}/skills/draft-article/frameworks/`).
- **sources** — any mix of paths, globs (`src/**/*.py`), and commit ranges
  (`HEAD~20..HEAD`).

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

It does, in order, halting on the first problem so nothing starts on a bad
config or framework:

- **Configuration validation (CAP-5).** Halts on any unresolved example
  placeholder, malformed URL (e.g. a double-slash `canonical_url`), or missing
  required key, printing a **per-key report** naming the file
  (`user-config.yaml` / `writing-sources.yaml`) and the fix — the report is
  `validate-config.py`'s verbatim. A clean config is silent. Relay any report and
  stop.
  - **A missing `writing-sources.yaml` is a hard stop, not a self-service fix
    (Story 13.11).** Do **not** proceed on a config you invented. Relay the error
    (it names the example's full path and that the file must live at the
    **host-repo root**), then **offer to scaffold** a starter `writing-sources.yaml`
    at the host-repo root as an explicit, owner-confirmed step; on consent create
    it from the example and **show the owner the path and contents** before
    re-running Stage 0; without consent, stop. Never scaffold silently.
- **Framework check** against the **closed set {F1, F2, F3, F4}** — an invalid
  name exits non-zero and **nothing starts** (no workspace minted). Relay and stop.
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
**in code** to GLOSSARY.md, LESSONS.md, and ≤2 track-matched `topics/*.md`:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/read-policy-source.py --root "$HOST" read > "$WS/policy-surface.txt"
```

Branch on its exit code — **the policy source is an enhancer, never a
dependency; no exit code here may abort the run**:

- **0** — the output leads with the run's pin (`pin: product-lab@<commit>`)
  and each file's content line-numbered. Author **tension items** from it:
  questions whose `gap_type` is `contradiction`, `ambiguity`,
  `missing-rationale`, or `reversal-candidate`, each carrying its seed
  `{quote, pointer: file:line@commit}` quoted **verbatim** from the surface at
  the pinned commit. The policy source supplies **questions only** — never an
  answer, never a recommendation (NFR15: triage and recommendations stay a
  view over harvest output). A question that merely restates its seed will be
  rejected (R4) — ask the tension, not the quote. Write the items to
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
- **at most 5**, and **zero** when harvest already covers everything — never
  padded to five.

Present a policy-seeded question under the same proposal contract as every
other: its **Why** context is the seed — the verbatim quote plus its
`file:line@commit` pointer — so the owner sees exactly which recorded position
the question probes. Its primary input is bullet free-text, like any open
question.

Present each surviving question under the
[owner-facing proposal contract](../owner-facing-proposal-contract.md): show
**where** the section it concerns sits in the article outline and a **short
preview of the current section** (when one already exists), **why** the question
is asked, and **choices whose labels state their concrete effect** — never a
shorthand the owner must decode. A first-time owner answers from **repository
knowledge alone**. Assemble the prompt payload and **validate it before showing
it** (contract (e)): `validate-proposal-payload.py` blocks a missing Effect line
or a truncated field.

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

**The journal ends with the `consulted:` line (Story 14.4, CAP-5).** Its last
key maps every seed to the question it seeded, under the run's pin —
`consulted: product-lab@<commit> — LESSONS.md:41 → t1; …` — the /ask-style
audit trail of which policy lines drove which questions. A run that was not
policy-seeded records `consulted: none (policy_source unset)`, or, when the
probe degraded, `consulted: none (policy_source unavailable: <reason>)` via
`--policy-note` — every interview run states its policy provenance, including
the generic ones. Surface the line in the completion summary's informational
notes when it names a pin.

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

Each block mirrors product-lab's `q_a/staging/` frontmatter (`slug, created,
source_repo, perishable, tags`) followed by the question and the owner's
decision in full sentences (seam-formats.md §3). **This is where the tool
stops**: the blocks land in the run workspace only — the owner copies accepted
ones into `q_a/staging/` by hand, and nothing is ever written under
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
P4.S2: derived <- fs-12, fs-14
P4.S3: narration
P4.S4: sourced <- fs-15
P4.S5: verify            # sentence carries an inline [VERIFY] in the draft body
```

Structurally validate it (each class's pointer contract) and write it to `$WS`:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py provenance --map <map> && cp <map> "$WS/provenance-map.txt"
```

`sourced` carries ≥1 pointer, `derived` ≥2, `narration`/`verify` none.

**Independent verify-provenance (Story 11.2, NFR13).** The map is then graded by
`verify-provenance` — a **standalone** check that does **not** share this
drafting context, so the agent that wrote the text never grades its own
claim/narration boundary. Operationally, this means the semantic judgment runs
in a **fresh judge subagent that never saw the drafting turn** — spawn it with
the harness Task tool, never as an inline continuation of this context:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/verify-provenance.py --map "$WS/provenance-map.txt" \
  --fact-sheet "$WS/fact-sheet-ids.txt" --judge-findings "$WS/provenance-verdicts.txt"
```

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

### Visual proposals (SPEC-article-visuals CAP-2)

As the framework fills, reach its **declared visual slot** (Story 8.1;
`frameworks/CONVENTIONS.md`) — and identify **up to 2 opportunistic extra
visuals** where one would materially help. **Propose** each; never insert one
unasked. Each proposal follows the shared
[**owner-facing proposal contract**](../owner-facing-proposal-contract.md)
(`${CLAUDE_PLUGIN_ROOT}/skills/owner-facing-proposal-contract.md`):

- **where** it lands in the outline (the framework slot, or the section an
  opportunistic visual would sit in);
- **why** it is proposed (the rationale);
- a **preview** — the actual **Mermaid source**, **table**, or **figure spec** the
  owner is approving;
- **choices whose labels state their concrete effect** — *approve* → "insert this
  visual", *modify* → "revise the source, then insert", *decline* → "omit the
  visual; the slot leaves no `[Figure: …]` residue".

**Insert nothing without explicit owner approval.** Opportunistic suggestions are
**capped at 2 per draft** — the declared slot plus at most two extras, never more.
A declined proposal leaves the slot **omitted entirely** (Story 8.1), with no
placeholder residue.

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
- **Dimensions 1–3** are judged by **one single-pass cheap-tier rubric judge**
  emitting **pass/fail per dimension + failing locations, no rewritten text**;
  its verdicts feed `--judge`. Like `verify-provenance` (NFR13), this judge runs
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
2. **At most 2 revision cycles.** If the gate still fails after two, the failure
   is surfaced as a **publish blocker** in the completion summary (FR20 bucket)
   naming the **failing dimensions and locations** — never silently retried,
   never waived.
3. A revision **never silently alters or drops owner-approved content** (approved
   interview answers used as sourced claims, approved visuals) (NFR12); a change
   that would touch it surfaces to the owner instead (same principle as
   ">1 rewrite → new interview question").

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

Emit platform-ready copies of the **verified** draft. Which platforms, and each
one's canonical policy, come from user config (`syndication.policy` /
`syndication.variants`) keyed by the draft's `language` — **never a hardcoded
mapping**:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py variants <draft>
```

- **Precondition:** the draft carries **zero `[VERIFY]` markers** — Stage 4 must
  be complete. Any unresolved marker aborts the stage.
- **EN / `mode: canonical`** → a **dev.to** copy: the full article text with a
  dev.to frontmatter whose `canonical_url` is a placeholder
  (`{canonical_url_base}/{slug}`) pointing back at the site page.
- **JA / `mode: external`** → a **Zenn** repo-sync copy: Zenn frontmatter
  (`emoji`/`type`/`topics`, `published: false`) with the full body — Zenn is
  canonical via repo-sync.
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

## Completion summary

End every run with the shared
[**completion summary**](../completion-summary.md)
(`${CLAUDE_PLUGIN_ROOT}/skills/completion-summary.md`): the three labelled buckets
— **informational notes**, **publish blockers**, **optional cleanup** — followed
by an explicit **next step** (here: "run review-article on the draft"). Because
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
| `provenance` | 3 | Parse + structurally validate the sidecar provenance map | `--map` `--count` |
| `quality-gate` | 3→4 | The mandatory quality gate; non-zero exit blocks Stage 4 (Story 11.4) | `--draft` `--map` `--judge` |
| `verify-markers` | 3/4 | Validate `[VERIFY: reason]` markers; `--count` prints the count (drive to 0) | `<draft\|->` `--count` |
| `verify` | 4 | Build the owner verification worklist, one entry per marker | `<draft\|->` |
| `reroute` | 4 | Reroute an over-budget section into a new bounded interview question (Story 4.5) | `--rewrites` (req) `--section` |
| `variants` | 5 | Emit platform-ready variants keyed by the draft's `language` | `<draft>` `--config-json` `--root` `--global-config` `--repo-config` `--out` `--dry-run` |
