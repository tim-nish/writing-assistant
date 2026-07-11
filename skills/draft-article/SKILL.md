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

## Stage 0 — start the run

**Configuration validation (CAP-5) runs first — before any generation.** Validate
the resolved configuration:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-config.py
```

It **halts** on any unresolved example placeholder, malformed URL (e.g. a
double-slash `canonical_url`), or missing required key, printing a
**per-key report** naming the file (`user-config.yaml` / `writing-sources.yaml`)
and the fix — before any generation work. A clean, fully resolved config passes **silently**,
so no configuration finding appears anywhere later in the run. Relay any report
and stop.

Then validate the framework and record the run with:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py start <framework> <sources...>
```

- The framework is checked against the **closed set {F1, F2, F3, F4}**. An
  invalid name is rejected — the command reports the valid set, exits non-zero,
  and **nothing starts** (no harvest, no partial run state). Relay that and stop.
- On success it prints the **run-state** JSON — the chosen framework, its
  framework file, and the **raw sources verbatim** plus their classification
  (path / glob / commit-range). Carry this record into the next stage unchanged.

### Resolve the run workspace (all intermediates land here)

Mint this run's workspace once, and write **every** intermediate under it:

```
WS=$(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py new-run)
```

`$WS` is a fresh per-run workspace directory **outside the host repo**
(`docs/storage-architecture.md` D2), resolved by the path resolver — never a
path you compose yourself, and never the host working tree. Its internal layout
is resolver-internal; always ask the resolver, never spell it out. The harvest fact
sheet and NEEDS-OWNER list, interview answers, the provenance map, quality-gate
output, and any scratch all live under `$WS/`; there is no state-vs-cache split.
The **only** files this pipeline writes into the host repo are the declared
products at `output.drafts` (Stage 5). Pass `$WS` to Stage 1 so harvest writes
there rather than minting its own workspace.

## Stage 1 — harvest and consume its output

Hand the run to the `harvest` skill to produce its output document at
`$WS/fact-sheet.md` (the source-pointed fact sheet **and** the NEEDS-OWNER
list) — give harvest the `$WS` from Stage 0 so it writes there. The stage-0 sources are
a **selection**, not a scope widener: harvest enumerates the
writing-sources-declared files (`resolve-writing-sources.py files`) and
**intersects** this selection with them, so a path passed on the command line can
only narrow what is read — never add an undeclared repo. Reconciliation against
`writing-sources.yaml` happens there.

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

Select the interview questions from the stage-1 state:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py interview --framework <F> <state>
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

The surviving (non-suppressed) questions are returned as `questions`, and are:

- drawn from the fixed question bank, **prioritized by the framework's GATE
  slots** (not bank order), so the same fact sheet yields a stable interview;
- **confirmed NEEDS-OWNER gaps first**, using the GATE-slot order as the
  deterministic tie-break when more than five could apply — the ≤5 cap holds even
  when the NEEDS-OWNER list is longer;
- **at most 5**, and **zero** when harvest already covers everything — never
  padded to five.

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

**Provenance — every claim traces to exactly one of three things:**

1. a **source pointer** carried from the fact sheet (kept verbatim and traceable
   — `path:line@sha` / sha / URL, not paraphrased away);
2. an **interview answer**, referenced by its question `id`;
3. an inline **`[VERIFY: <reason>]`** marker naming why it is unverified.

**Never an unmarked assertion.** A claim that is neither source-pointed nor
interview-sourced carries a `[VERIFY]` marker. So does a claim only *partially*
supported by a source but **extended by inference** — the source pointer does not
wave the inferred part through. When in doubt, mark it.

**Copy facts, don't summarize them into new claims.** Summarizing source content
can silently introduce an assertion the sources don't make — if a rewrite adds
anything beyond the source, that addition is inferred and takes a `[VERIFY]`.

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
