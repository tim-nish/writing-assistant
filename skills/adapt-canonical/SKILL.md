---
name: adapt-canonical
description: >
  Derive a target-language canonical from a reviewed canonical. Invoke as
  "adapt canonical <slug> for <target>" to run the standalone post-review
  adaptation invocation (never a stage of the draft flow, never fired by
  emission): preconditions, then ONE gate carrying the adaptation plan, then
  the owner's recorded answer. The contract it fronts is
  SPEC-canonical-adaptation CAP-1/CAP-3; this skill re-implements nothing.
---

# Adapt canonical

The front door for the **standalone post-review adaptation invocation**
(SPEC-canonical-adaptation CAP-1/CAP-3). Adaptation derives a **second
canonical** for a reader who differs in language, so that variant emission can
stay what it is — pure packaging. The draft flow runs once and owns the claims;
this invocation re-decides only *how the story is told*.

```
adapt canonical <slug> for <target> [<host-repo>]
```

Adaptation is **never a stage of the draft flow**, which ends at the `complete`
gate with next step review-article, and it is **never fired implicitly by
emission**: `emit variants` neither calls it nor suggests it. Whether an article
gets a derived canonical at all is a per-article owner decision, taken at this
invocation's one gate — there is no standing "always adapt" rule, and an article
the owner never chose to adapt has no derived canonical anywhere.

Run it **after review**, over the persisted canonical that `complete` wrote.

**Name the target repository first (#309).** Before reading anything else,
print the resolved target as the flow's first owner-visible line:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py target --root <host-repo>
```

Relay it as `Operating on host repo: <path>`.

## Where the adaptation target is declared (spec OQ1, settled)

`<target>` is the **id of an existing platform profile** — a pointer, not a new
declaration type. The profile already declares the one named reader
(`audience`) and that reader's `language`; the adaptation invocation reads
exactly those two fields from it.

What a profile does **not** carry is how prose is *told* in that language:
register and terminology are properties of the language, shared by every target
that speaks it, and a profile is packaging-scoped by the ratified
intent/packaging boundary. They are declared as data in
`config/language-conventions.yaml` (overridable per repo at
`<repo-config-dir>/language-conventions.yaml`), keyed by language code.

So **adding a second adaptation target is declaration, not stage code**
(CAP-6): one platform profile file, plus one `languages.<code>` entry only when
that reader speaks a language not yet declared. No language is branched on in
the implementation — `ja` is a key in data, never a case in code.

## Preconditions — re-stated, never re-implemented

The invocation itself enforces all of these with the **variant stage's own
predicates** and fails pointedly when one is unmet. State them; do not re-check
them here, and do not write a second copy of any of them:

- the **persisted canonical** exists at `<output.drafts>/<slug>.md` — a
  run-workspace copy is refused, with `complete` named as the remedy;
- the draft carries **zero `[VERIFY]` markers** (Stage 4 finished, review done);
- the draft declares a resolved **`audience`**, **`audience_id`** and
  **`language`**;
- the target profile resolves, and its reader/language actually differ from the
  source's — a same-reader target is packaging, so it routes to `emit variants`.

If one of these aborts the invocation, relay the error verbatim — it already
names the remedy.

## Step 1 — read the plan skeleton

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/adapt-canonical.py plan \
  --slug <slug> --target <target> --root <host-repo>
```

Exit non-zero is a precondition refusal: relay it and stop. Exit 0 returns the
skeleton — the resolved source facts, the resolved target reader/language, the
declared `register` and `terminology` for that language, and the source's
**section inventory**. Nothing is written by this call.

## Step 2 — author the plan

You author exactly four slots, as JSON, against that skeleton. Everything else
in the plan is declared data and is not yours to propose:

- `refounded_opening` — what context the target reader lacks or already has, and
  what the opening therefore establishes first;
- `structural_mapping` — one row per source section, `{source_section,
  disposition, note}`, disposition one of `keep | move | merge | split | drop`,
  the note saying why it moves, merges or stays **for this reader** (e.g.
  payoff-first for JA tech-article norms vs an EN incident-led narrative);
- `recomposed_title` — the title re-composed for the target reader, not
  translated;
- `omissions` — `{section, what, reason}` for every deliberate omission.

Adaptation depth varies per article: a how-to may map nearly 1:1, an incident
narrative may restructure. Propose the plan fresh each time.

Three mechanical rules apply and the script enforces them, so a defective plan
never reaches the owner: **every source section is accounted for exactly once**;
**a `drop` requires a declared omission naming that section and its reason** —
never an implicit loss; and **`register`/`terminology` in your fill are
rejected** — they are declared invariants, not per-article proposals. The
claims invariant (no claim added, none dropped silently — CAP-2) is checked by
story 18.57's conformance pass; state omissions honestly here regardless.

## Step 3 — one gate, then the recorded answer

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/adapt-canonical.py payload \
  --slug <slug> --target <target> --root <host-repo> --fill <plan.json> \
  > "$WS/adaptation-plan.payload.json"
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-proposal-payload.py \
  --ws "$WS" --surface adaptation-plan "$WS/adaptation-plan.payload.json"
```

Present the result **in-conversation** under the
[owner-facing proposal contract](../owner-facing-proposal-contract.md) — **one
screen**, machine-proposed plan plus free-form response, never a path or
artifact for the owner to open, and never a second confirmation after they
answer. The payload is **plain text**: no `**bold**`, no backticks, no headings,
no Markdown links (contract (g)). A non-zero exit means the payload is not
presentable — fix the named field and re-validate; **a blocked payload is never
shown**.

The gate's options are **approve / modify / stop**, each stating its concrete
effect on the artifact:

- **approve** — the derived canonical `<slug>.<language>.md` is written at the
  resolved `output.drafts` from this plan; the source canonical is untouched;
- **modify** — the plan is revised from the owner's answer, then the derived
  canonical is written from the revised plan;
- **stop** — nothing is written; the article stays single-canonical and no
  derived canonical exists anywhere. "Stop" is a first-class outcome, not a
  failure.

Record the answer against the returned `ask_id`:

```
printf '%s' '<answer JSON>' | python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-proposal-payload.py \
  --ws "$WS" --answer <ask_id>
```

**Nothing is written before that answer** — not the derived canonical, not a
draft of it, not a scratch copy in the host tree. This invocation's mechanical
core writes to `output.drafts` at no point; the answer, and the payload that
preceded it, live in the run workspace.

## Boundaries

- **This story stops at the recorded answer.** Persisting the derived canonical
  with its ancestry block, and the staleness chain from the source canonical
  through the derived one to its variants, are separate contracts
  (SPEC-canonical-adaptation CAP-4/CAP-5) with their own stories. Do not
  hand-write a `<slug>.<language>.md` here.
- **Never a draft-flow stage, never an emission side effect.** If a flow seems
  to need adaptation, it needs the owner to invoke this skill, not a call from
  that flow.
- **No per-language code path.** The target reader, language, register and
  terminology come from declaration data. A new target is a profile file.
- **Never edit the source canonical here.** Adaptation derives; a change to the
  claims routes to the source canonical and a fresh adaptation.
