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
