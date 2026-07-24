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

## Step 4 — write the derived canonical

Only after that answer, and only when it was **approve** or **modify**. Author
the target-language prose from the approved plan, then hand it to the writer —
never hand-write the file, and never place it yourself: the path, the
frontmatter, the ancestry pin and the trailer are all the writer's.

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/adapt-canonical.py write \
  --slug <slug> --target <target> --root <host-repo> \
  --fill <plan.json> --body <derived-body.md> --ws "$WS"
```

`--body` carries **only the article body** — the frontmatter is composed for
you. What comes out is an ordinary canonical at
`<output.drafts>/<slug>.<language>.md`: its own `slug` (`<slug>.<language>`),
`mode: canonical`, the target's `language` and reader, every other declared
schema field carried from the source verbatim, its own `canonical-sha256`
trailer, and the ancestry pin

```
adapted_from: <source slug>@<source hash>
```

spelled to reuse the articles-repo plans' existing `pin: <repo>@<sha>` idiom
(ratified 2026-07-23). The source hash is the **same convention the variant
trailer uses** (sha256 over content without the trailer) — there is one hash
convention in this pipeline, not two.

`write` re-reads the gate's recorded answer from `$WS` and refuses without one,
so the CAP-3 ordering is mechanical rather than remembered: a `stop` answer, a
missing answer, and an unanswered gate each write nothing.

## Step 5 — the two conformance checks

**Claims conformance (CAP-2).** Adaptation re-decides the telling, never the
truth. The check compares the two artifacts' provenance-map **pointer sets** —
language-independent claim identity — so it reports an added claim and a
silently dropped one, and says nothing whatever about structure, section order,
payoff position, framing, register or title, all of which CAP-2 leaves free:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/adapt-canonical.py claims-check \
  --source-map <source.map> --derived-map <derived.map> --fill <plan.json>
```

A deliberately dropped claim is declared in the plan's `omissions` entry with
its `pointers`; anything else absent is a defect. There was **no existing
claim-set comparison to reuse** — `verify-provenance.py` grades one map against
one fact sheet, and map positions are per-artifact — so this comparison is new,
built on the shipped map parser rather than a second map format.

**Ancestry lint (CAP-4).** A pin that does not resolve is named, never
swallowed:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/adapt-canonical.py lint-ancestry \
  --derived <output.drafts>/<slug>.<language>.md --root <host-repo>
```

It names a malformed pin, a `slug` that resolves to no canonical, and a
recorded hash that matches no source content (reported with the hash pair).

## Step 6 — the staleness chain

An edit to the **source** canonical does not stop at the derivation: it reaches
everything published downstream of it. The chain is

```
EN canonical edit  ->  JA canonical stale  ->  its Zenn variant stale
```

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/adapt-canonical.py staleness \
  --root <host-repo>
```

With no `--derived`, it covers every derivation at the resolved
`output.drafts`. Anything not fresh lands in the **publish blocker** bucket with
the **hash pair** (recorded vs current) — never a warning, never silent:

- `stale-derivation` — the recorded source hash no longer matches the source
  canonical's current hash;
- `stale-by-inheritance` — a variant of a stale derivation, carrying the
  upstream link. It is stale **even when its own recorded hash still matches**,
  because the content it was emitted from is superseded. That is exactly the
  failure the chain exists to prevent: a fix applied upstream leaving a
  published Japanese article stating the superseded version.

The derivation's own variants are graded by the **shipped** `variant-staleness`
mechanism against the derivation, unchanged — this adds an upstream link, it
does not replace that check.

Clearing a stale derivation is **a fresh owner decision** through this
invocation: run it again from Step 1, so the owner re-approves a plan against
the changed source. It is never an implicit re-run, and never an in-place edit
of the derived canonical — the staleness check itself writes nothing.

## What downstream does with it — nothing special

The derived canonical is a canonical, so every downstream stage consumes it
through its existing path with **zero special-casing**:

- `emit variants --slug <slug>.<language>` resolves it exactly like an authored
  canonical — no branch anywhere distinguishes the two;
- review runs over it as a canonical. Claim **verification does not re-run**:
  the claims are inherited under CAP-2, so review's scope over a derivation is
  language and framing quality plus the claims-conformance check above.

## Boundaries

- **The derived canonical is written by `write`, never by hand.** Do not create
  a `<slug>.<language>.md` yourself, and do not edit one in place: a change to
  the telling is a fresh adaptation, and a change to the claims routes to the
  source canonical first.
- **The staleness chain from the source canonical through the derivation to its
  variants is a separate contract** (SPEC-canonical-adaptation CAP-5) with its
  own story.
- **Never a draft-flow stage, never an emission side effect.** If a flow seems
  to need adaptation, it needs the owner to invoke this skill, not a call from
  that flow.
- **No per-language code path.** The target reader, language, register and
  terminology come from declaration data. A new target is a profile file.
- **Never edit the source canonical here.** Adaptation derives; a change to the
  claims routes to the source canonical and a fresh adaptation.
