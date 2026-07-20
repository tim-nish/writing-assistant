---
id: SPEC-spec-sitting
companions: []
sources:
  # Authoritative external contract — owner decision record 2026-07-20 (consumer
  # fork-gate consult-first) + the standing same-sitting gate discipline.
  # Tracking issue: #483. Depends on #480 (fork-gate consult-first, implemented
  # in #485) for the covered-FYI / uncovered-gate triage of step 2's design forks.
---

> **Draft 2026-07-20 (#483), awaiting owner ratification as written.**
> Hand-authored from the issue's already-settled contract (transcription, not new
> design). **Implementation schedules at the arrival of the next `triage:spec`
> issue after ratification** — the first manual sitting this command would
> replace is both the demand trigger and the first dogfood. Ratify ≠ implement.

> **Canonical contract.** This SPEC is the complete, preservation-validated
> contract for what to build, test, and validate. Source documents listed in
> frontmatter are for traceability only.

# Single-command spec-lane sitting (`/spec-sitting`)

## Why

A full spec-lane cycle currently costs many conversational confirmations —
proceed-to-ratify, proceed-to-decompose, which story lineage, proceed-to-implement
— even when every decision is either already policy-covered or purely sequential.
A recent sitting resolved nine of nine fork decisions from already-ratified
upstream policy lines, each relayed by hand. The owner wants **one typed command
per issue or coupled cluster, with at most one pause**: invocation is the
approval for the whole pipeline, and only genuinely new positions (uncovered
forks) stop the run.

## Capabilities

- **CAP-1** (invocation is the whole-pipeline approval)
  - **intent:** `/spec-sitting <issue> [<issue>…]` runs the full spec-lane
    sitting for the issue or coupled cluster end to end — **analyze → spec →
    ratify → decompose → implement** — and **never asks "shall I proceed"
    between steps**. Typing the command is the approval for every step.
  - **success:** A run over an issue whose forks are all policy-covered
    completes with **zero** mid-run confirmations; the only possible pause is
    CAP-3.
- **CAP-2** (analyze + spec, forks triaged via #480)
  - **intent:** Step 1 does the spec-lane analysis (governing text, coupling,
    dependency/ripeness). Step 2 runs bmad-spec create/update in the BMAD
    workspace; its **design forks are triaged through
    `SPEC-policy-fork-consultation` (#480)** — covered forks resolve as
    overrideable **FYIs** (pin + verbatim quote), uncovered forks are held.
  - **success:** A fork covered by a served line appears as an FYI, not a
    prompt; the run's receipts show a gateway hit per in-scope fork.
- **CAP-3** (the single pause — one batched uncovered-fork prompt)
  - **intent:** All **uncovered** design forks across the run are batched into
    **one owner prompt** — ≤3 pinned candidates each, ordered by
    recontextualizing power, **no default pre-selected**. This is the **only**
    mid-run pause.
  - **success:** A run with two uncovered forks pauses **once**, presenting both
    with their candidates; the run cannot proceed past it without owner answers.
- **CAP-4** (ratify + decompose)
  - **intent:** Step 3 applies the fork answers, re-validates (coherence +
    preservation), flips/promotes the canonical spec, and **commits** — tracker
    comments post **only after the commit lands, citing the sha**. Step 4
    decomposes into **triage-convention stories** (`umbrella: <issue>`, current
    triage epic) per the **story-lineage routing rule** (README "Issue triage",
    #483 — the authority; cited, not restated here); placeholder stories are
    **superseded with pointers, never deleted**.
  - **success:** The canonical spec change is one reviewable commit; stories
    carry `umbrella: <issue>`; no bmad-epics delta is produced for issue-routed
    work.
- **CAP-5** (implement + same-sitting exit)
  - **intent:** Step 5 runs `/implement-story` over the new stories → branch(es)
    → PR(s) → `Closes #N`, with board + label reconciliation. The
    **same-sitting exit rule** holds: any deferred remainder **gets a bound
    story before the run ends**.
  - **success:** The sitting ends with merged-ready PRs and zero un-tracked
    remainder; a deferred piece is a bound story, never a silent gap.

## Constraints

- **Marker discipline (unchanged).** A **spec-only resolution** (no
  implementation planned) uses the spec-only marker; a **ratify-now /
  implement-later** outcome uses a **condition-bound hold** — never the marker.
  (This spec is itself the second case.)
- **Uncovered forks are never machine-final** — no default pre-selected, the
  gate never times out into a choice.
- **Story-lineage routing (cited, not owned here).** Issue-routed work
  decomposes as triage-convention stories; bmad-epics deltas are for
  spec-corpus planning only — the authority is the README "Issue triage" line
  (#483), which binds `/triage-gh` and the BMAD workflows too.
- **Destructive / outward-irreversible acts still confirm** — force-push,
  deletes, and publishing beyond the tracker keep their own confirmation, never
  folded into the single invocation approval.
- **Degradation:** gateway absent ⇒ **all** in-scope forks pause as owner gates
  in the one batched prompt; the run continues after answers, never blocks.
- Not a new spec engine or a change to bmad-spec / `/triage-gh` /
  `/implement-story` internals — it **composes** them under one approval.

## Non-goals

- Auto-answering uncovered forks, or pre-selecting a default at the single pause.
- Replacing bmad-spec, `/triage-gh`, or `/implement-story` — it orchestrates
  them; each keeps its own contract.
- Folding destructive-act confirmations into the single invocation approval.
- A bmad-epics path for issue-routed work (the routing rule forbids it).

## Success signal

The owner types `/spec-sitting <issue>` for an issue whose forks are all covered
by ratified policy lines and the sitting runs analyze → spec → ratify (one
commit) → decompose (triage stories) → implement (PR `Closes #N`) with **zero**
mid-run confirmations; an issue with two uncovered forks pauses **exactly once**
(both forks, ≤3 pinned candidates each, no default) and then completes; and a
run with the gateway absent presents all in-scope forks in that single batched
pause and still completes after answers.
