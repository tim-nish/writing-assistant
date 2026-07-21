# Owner-facing proposal contract

The single, shared convention for **every** prompt in this plugin that asks the
article owner to approve, modify, or decline something — gap-interview questions,
owner-verification items, review-arbitration findings, visual proposals, and any
future proposal surface. It is defined **once, here**; the skills reference this
file and never restate their own wording (SPEC-writing-assistant, engine-wide
contract).

## Every owner-facing proposal must show three things

1. **Where** it lands in the artifact — the outline / section context, plus a
   short **preview of the current content** when one already exists. The owner
   sees *what the decision changes*, not an abstract reference to it.
2. **Why** it is being asked — the rationale for the proposal, in one line.
3. **Choices whose labels state their concrete effect on the artifact** — each
   option names what it does to the article (e.g. "keep the claim, marked as an
   unmeasured estimate" / "remove the claim from the article"), never a shorthand
   label that forces the owner to infer the generation logic.

## The test: repository knowledge alone

A **first-time owner** must be able to answer every prompt from **repository
knowledge alone** — without already understanding the generated draft or the
pipeline's internals. If answering requires knowing *how* the draft was produced,
the prompt violates this contract and must be reworded to carry its own context.

## No shorthand labels

A choice labelled only with an internal token — "option A", "regen", "mode 2",
"approve / modify / delete" with no effect spelled out — is **non-conforming**.
Every label states its concrete effect on the article so the meaning is legible
without inferring the generation logic behind it.

## (d) Selective presentation is the primary interaction model

Every proposal surface presents **choice-based selective prompts** — the owner
decides by picking an effect-stating option, not by composing prose. **Free-form
text entry appears only** as the input mode for **owner-only knowledge**: the
*open* interview outcome and the *modify* / *replace* paths on a recommended
answer. Collecting answers as free-form text where choices are mandated (e.g. a
blank `q1: <answer>` prompt for a question the repo could ground) is a **contract
violation**, not a presentation preference.

## (e) Payloads are validated before the owner sees them

A proposal's payload is validated **mechanically before presentation**, the way
`verify-markers` gates stage progression: every item must carry its **Where**,
**Why**, and **Effect** fields, each **present, non-empty, and untruncated**. A
payload with a missing Effect line or a field cut off mid-sentence **blocks
presentation** — the damaged prompt never ships.

Content that would exceed a field's display budget is **re-written shorter by
authorship, never clipped**: a field is made to fit by saying less, not by
truncating mid-word. Validate an assembled payload with:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-proposal-payload.py <payload.json>
```

A non-zero exit means the payload is not presentable — fix the named field and
re-validate. This gate is **engine-wide**: the gap interview, review arbitration,
Stage-4 verification, and visual proposals all inherit it by referencing this
convention, with no restated wording.

## (f) Presented payloads are captured verbatim (Story 13.28)

Every ask that passes gate (e) inside a run is **persisted exactly as shown**,
at ask time, by the same invocation — pass the run workspace to the validator:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-proposal-payload.py --ws "$WS" --surface <interview|visual-proposal|verification|arbitration> <payload.json>
```

On a presentable payload this appends the full payload verbatim — question set,
option labels, descriptions, previews, recommended answers — to
`$WS/presented-payloads.jsonl` (append-only; one record per ask; no
normalization or summarization; never the host tree) and prints the ask's
`ask_id`. A blocked payload is never captured. When the owner answers, record
the selection and any free text against the same ask:

```
printf '%s' '<answer JSON>' | python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-proposal-payload.py --ws "$WS" --answer <ask_id>
```

This log is the meta-analysis substrate (SPEC-draft-article-ux CAP-2): a later
"review the interview itself" pass reads payloads + journal + answers and needs
nothing from the drafting context. The capture is the deliverable — no analysis
tooling exists; the analysis is a prompt over run state. Resumed runs keep
appending; nothing is overwritten or de-duplicated.

## (g) Payloads are plain text (added 2026-07-17, #300/#307)

The selection surface renders **no Markdown**. Formatting the surface cannot
render is a lintable defect class at this boundary — the presentation-side
sibling of the internal-vocabulary rule — because raw markers degrade exactly
the context the contract exists to provide, and worst on the richest asks.

**Allowed conventions** (survive a plain-text surface): indentation, `-` list
dashes, quoting by indentation, CAPITALIZED words for emphasis, blank-line
separation.

**Forbidden markers** (never reach the owner): `**bold**` / `__underline__`,
backtick code fences, `#` headings, Markdown links. Emphasis is carried by
wording or capitalization; a link is written as a bare path or URL.

**Visual previews:** a visual proposal's preview is a **plain-text structural
sketch** (elements, relations, emphasis — figure-spec style), never raw Mermaid
or fenced source in the payload. The concrete Mermaid/table source is written
to the run workspace and the payload shows its **path**, so the owner can open
it rendered. Policy-seed quotes are presented under the same plain-text
conventions, keeping their `file:line@commit` pointer.

Enforcement lives at gate (e) — the validator rejects forbidden markers like a
missing Effect line — never in prompt wording alone.
