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
