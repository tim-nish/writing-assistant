---
id: SPEC-policy-fork-consultation
companions:
  - ../spec-policy-source-seam/SPEC.md         # adopted: the served-seam plumbing this skill consumes (gateway client, pin, consulted receipts, staging emitter)
  - ../spec-policy-divergence-detector/SPEC.md # sibling emitter into the same upstream intake (opposite trigger family); gate/disposition conventions mirrored
sources:
  # Authoritative external contract — owner decision record 2026-07-20 (consumer
  # fork-gate consult-first), held in the owner's private policy hub, retrievable
  # by date + title (read-only). Generalizes the owner decision record 2026-07-18
  # (interview consult-first triage) to all fork-presenting gates, under the
  # standing consult-first contract (owner decision record 2026-07-16).
  # Tracking issue: #480.
---

> **Ratified 2026-07-20 (#480).** Owner-ratified as authored hub-side; the design
> forks (consult-per-fork → covered-FYI / uncovered-gate / miss-feedback) were
> resolved in the decision record, not inline. The one external dependency — the
> hub §3.1 staging-file intake shape CAP-4 emits into — is **settled**: this spec
> is the **second emitter** SPEC-policy-divergence-detector (#436) anticipates and
> cites the **same hub §3.1 authority and declared precedence** (ratified this
> sitting). **Do not implement yet** — implementation follows owner scheduling,
> per the #436 precedent (ratify ≠ implement).

> **Canonical contract.** This SPEC is the complete, preservation-validated
> contract for what to build, test, and validate. Source documents listed in
> frontmatter are for traceability only.

# Fork-Gate Consult-First (#480)

## Why

Every spec run and triage re-offer raises owner gates as fork tables — and a
recent sitting resolved nine of nine fork decisions from already-ratified
upstream policy lines, each relayed by hand between consoles. The standing
consult-first contract already requires querying the served policy surface
*before* raising a human gate on policy, architecture, or prior-decision
questions; the interview already applies it (covered questions auto-answered
with pin, demoted to FYI; true tensions escalated with pinned candidates).
This spec applies the same contract to every fork-presenting stop point, so
covered forks stop consuming owner gates and only genuinely new positions
reach the human. Fixed points restated from the decision record: a covered
fork is resolved as an **application of an existing owner position, never a
machine invention**; resolution is always **visible and overrideable**;
uncovered forks are **never machine-final**; every miss feeds the upstream
intake as a **proposal only**.

## Capabilities

- **CAP-1** — consult per fork, before presenting
  - **intent:** At any stop point that presents policy, architecture, or
    prior-decision forks (spec-run fork tables, triage spec-lane re-offers),
    form each fork's discriminating question from the fork's option text and
    query the served policy surface through the existing seam client
    (owner-realm grant, pinned bounded read, consult-first `policy_lookup`).
    Purely mechanical/product-engineering forks (no policy, architecture, or
    prior-decision content) are out of scope and skip consultation. No new
    consult surface is added — only new call sites at fork gates.
  - **success:** A run's receipts show one gateway hit per in-scope fork,
    each preceding the stop point; a fork table with zero in-scope forks adds
    zero gateway reads.
- **CAP-2** — covered fork → overrideable FYI with source receipts
  - **intent:** A fork whose discriminating question is answered by a served
    line is resolved machine-side and moved to a distinct **FYI section** of
    the stop report: chosen option + the verbatim served quote +
    `file:line@commit` at the run's pin. The owner may override any FYI
    inline; an override reopens the fork as a CAP-3 gate (and is a natural
    divergence signal for the sibling detector). Coverage is strict: the
    quote must actually discriminate between the fork's options — a quote
    that is merely topical does not cover, and the fork stays a gate.
    Resolution is never silent: an FYI is always shown, never skipped.
  - **success:** A fixture fork covered by a served line presents as one FYI
    (option + quote + pin) and no gate; overriding it re-presents the fork as
    a gate in the same sitting; a fixture with a topical-but-non-discriminating
    quote presents as a gate, not an FYI.
- **CAP-3** — uncovered fork → owner gate with pinned candidates
  - **intent:** A fork not covered stays an owner gate, presented with 1–3
    machine-proposed candidate answers — each carrying its partial grounding
    (pinned quotes where any exist) — ordered by recontextualizing power (the
    candidate that most reframes the remaining forks first). Candidate
    drafting is sanctioned; candidate *finality* is not: no default is
    pre-selected, and the gate never times out into a choice.
  - **success:** An uncovered fixture fork presents ≤3 ordered candidates
    with their grounding, no pre-selected default; the run cannot proceed
    past the gate without an owner choice.
- **CAP-4** — miss feedback into the upstream intake (proposal-only)
  - **intent:** Every uncovered in-scope fork is a consult **miss**: recorded
    as a distill-bug signal in the run receipts, and — at the owner's gate
    disposition, mirroring the detector's "report upstream" choice — emitted
    as a staging-schema block in the run workspace, **conforming to the hub
    staging-file schema** (product-lab `specs/knowledge-architecture.md`
    §3.1, the authority — the hub schema wins on any mismatch, and a mismatch
    is a defect of THIS spec). This spec owns only the fork-specific payload
    inside that envelope: the fork as asked, the options, the owner's answer,
    and the candidates considered. This skill is the **second emitter** into
    that intake beside the divergence detector (#436), which already assumes
    it is not sole; the manual copy into the upstream intake stays an
    explicitly approved owner act.
  - **success:** Answering an uncovered fixture fork and choosing "report
    upstream" yields a schema-valid staging block in the run workspace and
    zero upstream changes; declining yields only the receipts-line signal.

## Constraints

- Never machine-final on an uncovered fork; never a silent resolution of a
  covered one — visibility and overrideability are the contract, not
  presentation choices.
- No consultation cache: every run re-queries at a fresh pin (the upstream
  cache decline applies unchanged); FYIs quote the current run's pin only.
- The upstream hub is never written; emission is proposal-only via the seam
  staging emitter; the copy step is never automated.
- Auditability: run receipts carry pin + consulted lines per fork; the
  server-side access log is the canonical record — an in-scope fork gate
  with no preceding gateway hit is a lintable defect.
- Degradation: if the gateway is unavailable or the grant is absent, every
  in-scope fork presents as a CAP-3 gate (without candidates' served
  grounding) with one logged line; the skill never blocks or fails a run.
- Bounded reads per fork per the seam contract; candidate count capped at 3;
  forks cut by no cap — every in-scope fork is either FYI or gate, counted.
- Not a new command: behavior folds into the existing stop points that
  already present fork tables; carrier check applies (each fork-presenting
  site resolves to an invocation of this skill or a declared exemption).
- Publication boundary: FYIs, gates, and staging payloads carry only the
  served pointer grammar already public in this repo.

## Non-goals

- Resolving genuinely new owner positions machine-side — coverage means an
  existing ratified line discriminates the fork, nothing weaker.
- Changing the gateway, its grants, or its surfaces; adding a new consult
  surface or a cross-repo question-forwarding channel (declined upstream).
- Replacing or overlapping the divergence detector: the detector compares
  decisions *already taken* against served lines; this skill triages
  decisions *being asked*. Same intake, opposite trigger family.
- Consulting on out-of-scope (purely mechanical) forks, or scoring/ranking
  fork options by anything other than served-line coverage.

## Success signal

A spec run whose fork table contains one fork covered by a served line and
one uncovered fork presents exactly one FYI (option + verbatim quote +
`file:line@commit`, overrideable) and exactly one owner gate (≤3 pinned
candidates, no default); the run receipts show gateway hits preceding the
stop point; the owner's uncovered-fork answer can be dispositioned into a
§3.1-conformant staging block with zero upstream changes; and the same run
with `policy_source` absent presents both forks as gates with one logged
line.

## Assumptions

- Fork-discriminating questions can be formed mechanically from the fork
  table's option text plus the stop report's framing. If option text proves
  too thin in practice, extending the fork-table format (a `discriminant:`
  line per fork) is in scope for the implementing epic — adding a new
  consult surface is not.
- The stop points that present forks are enumerable in this repo's skills
  (spec-run fork tables, triage re-offers); the carrier check in Constraints
  makes that enumeration verifiable rather than assumed.
