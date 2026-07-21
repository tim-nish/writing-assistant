---
id: SPEC-policy-divergence-detector
companions:
  - detector-formats.md
  - ../spec-policy-source-seam/SPEC.md         # adopted: the served-seam plumbing this detector consumes (gateway client, pin, consulted receipts, staging emitter)
  - ../spec-policy-consistency-pass/SPEC.md    # adopted: the arbitration contract mirrored here; its "no third consumer" non-goal is superseded (see amendment there)
sources:
  # Authoritative external contract — owner decision record 2026-07-20 (consumer-triggered
  # policy feedback), held in the owner's private policy hub, retrievable by date + title
  # (read-only). Tracking issue: #436, companion to #422 — same staleness-detection family,
  # opposite direction.
---

> **Ratified 2026-07-20 (#436).** Owner-ratified against the hub decision record
> (2026-07-20, consumer-triggered policy feedback) once the hub-side intake shape
> was settled. Ratification supersedes the "no third consumer of the seam" non-goal
> of SPEC-policy-consistency-pass (amendment recorded there); nothing else in the
> two ratified seam consumers changes. **Ratification condition (CAP-3):** the
> staging block is a **conformance copy** of the hub staging-file schema
> (the configured policy hub's §3.1) with declared precedence —
> the hub schema is the authority, it wins on any mismatch, and a mismatch is a
> defect of this spec; this spec owns only the detector-specific divergence
> payload, and never assumes it is the sole emitter into that intake (see CAP-3,
> the emission-formats constraint, and `detector-formats.md` §4).

> **Canonical contract.** This SPEC and the files in `companions:` are the complete,
> preservation-validated contract for what to build, test, and validate. Source documents
> listed in frontmatter are for traceability only.

# Consumer-Side Policy-Divergence Detector (#436)

## Why

Upstream policy was consulted to build this tool, and every consult is receipted
(pin `<policy-source>@<commit>`, `file:line@commit` quotes, `consulted:` lines).
As the tool evolves it accumulates implementation-level decisions, and some
upstream lines it once consulted become contradicted or outgrown — yet nothing
feeds that divergence back upstream to initiate a policy update. The existing
staleness machinery all points the other way: seam CAP-3 staleness routing and
CAP-7 conflict reconciliation (and #422 as an instance) catch the *upstream
surface moving under this tool*. This detector catches *this tool moving past
the upstream surface*: same staleness-detection family, opposite direction.
Sanctioned by the owner decision record 2026-07-20 as the seam plumbing's third
consumer. The contract's fixed points, restated from that record: the detector's
output is a **divergence candidate, never an authoritative determination**;
emission is **proposal-only** (a tracker issue here, or a staging-schema block
offered for manual copy into the upstream intake); the tool **never writes the
upstream hub**; the copy step stays a manual, explicitly approved owner act; the
policy update itself happens only at the upstream ratification gate. No sync
pipeline, nothing machine-final.

## Capabilities

- **CAP-1** — detection at existing consult points, over applied lines only
  - **intent:** At the places this tool already consults the served policy
    surface — the seam reads inside the draft/review pipelines (interview
    seeding, policy-consistency pass) and agent-session consult-first
    `policy_lookup` calls — after the run records which served lines it
    applied, classify the relation between the decision actually taken and each
    applied line. Exactly two flaggable directions: **contradiction** (the
    decision taken conflicts with the quoted line) and **outgrown** (the quoted
    line prescribes a mechanism or assumption this tool no longer has).
    Anchoring is mechanical — the pin and quotes are already in the run
    artifact; the classification pass may be LLM-assisted, but its output is
    only ever a candidate (CAP-2). The detector consumes only lines the run
    already fetched: it adds **zero** gateway reads and no new consult surface.
  - **success:** A run whose consult applies a line prescribing a
    since-retired mechanism yields exactly one divergence candidate carrying
    both sides; a run whose applied lines all match current behavior yields
    none; instrumentation shows no additional gateway calls attributable to the
    detector.
- **CAP-2** — divergence-candidate record (never a determination)
  - **intent:** Each flag is one schema-validated record (companion
    `detector-formats.md`): the consumer-side decision (statement + repo
    evidence `path:line` or run-artifact pointer), the upstream side (verbatim
    quote + `file:line@commit` at the run's pin), the direction, a one-sentence
    rationale, `status: candidate`. The schema has **no verdict field** — there
    is no way to express "the policy is wrong" or "must update", only "these
    two disagree and here is where". A validator rejects a record missing
    either quote, either pointer, or the pin.
  - **success:** Each rejection class has a seeded fixture the validator fails;
    a valid record passes; validation runs before any candidate reaches the
    owner gate.
- **CAP-3** — owner gate with proposal-only emission
  - **intent:** Candidates enter the run's existing owner gate under the
    proposal contract (selective prompts, Where/Why/Effect, journal entries),
    with three effect-stating choices mirroring the consistency pass's
    arbitration: **report upstream** (emit the proposal — a tracker issue in
    this repo carrying the record, or a staging-schema block in the run
    workspace **conforming to the hub staging-file schema** (the
    configured policy hub's §3.1, the authority — precedence and
    payload split in `detector-formats.md` §4), offered for manual copy into the
    upstream intake), **fix here** (the divergence is a
    consumer defect — route to this repo's tracker as an ordinary issue; no
    upstream proposal), **dismiss** (not a divergence; one-line reason,
    remembered per CAP-4). Nothing is emitted without the owner's choice; no
    emission path touches the upstream hub.
  - **success:** Choosing "report upstream" produces a schema-valid staging
    block in the run workspace or an issue in this repo and changes nothing
    upstream; choosing "dismiss" produces no external artifact; the journal
    records every disposition.
- **CAP-4** — disposition ledger and dedup
  - **intent:** Every disposed candidate (reported, fix-here, dismissed) is
    appended to a small repo-tracked ledger (companion format;
    `config/policy-divergence-ledger.json`) keyed by (policy pointer sans
    commit, direction, decision evidence). Subsequent consults dedupe against
    the ledger — the same divergence is not re-flagged every run — but the
    decision is remembered without suppressing evidence: a deduped hit
    increments the entry's occurrence count silently. An entry **expires**
    (drops out of dedup) when the run's pin has advanced past an upstream
    change touching the quoted line — the upstream may have absorbed or
    overtaken the proposal, and the comparison is live again.
  - **success:** Re-running the CAP-1 fixture after a "dismiss" yields no
    second gate prompt and an incremented count; the same fixture after the
    pinned line changes upstream yields a fresh candidate.
- **CAP-5** — direction guard
  - **intent:** Before flagging, the detector decides which side moved, from
    inputs the run already holds (the pin, the served line, the decision's
    evidence). If the served line at the current pin differs from the line the
    decision originally consulted, the *upstream* moved — that event belongs to
    the seam's existing stale-direction machinery (CAP-3 staleness routing /
    CAP-7 conflict reconciliation) and is routed there, never emitted as a
    divergence candidate. A divergence candidate asserts exactly: the surface
    is current at the pin, and this tool moved past it.
  - **success:** A fixture where the upstream line changed between the
    decision's consult and the current run produces a reconciliation-path
    event and zero divergence candidates.

## Constraints

- Never machine-final: no auto-filed upstream proposal, no auto-applied policy
  or repo change, no sync pipeline — every emission sits behind the CAP-3
  owner choice.
- The upstream hub is never written, and the manual-copy step is never
  automated (the seam's standing "manual until it proves to be real friction"
  line applies unchanged).
- Bounded: ≤3 candidates per run, ranked highest-leverage first; candidates
  cut by the cap are counted in the run output, never silently dropped.
- The detector never blocks or fails a run: any detector-internal error skips
  the pass with one logged line (the seam's degradation discipline).
- Emission formats are **conformed, not invented**: the staging-schema block is a
  **conformance copy of the hub staging-file schema** — the
  configured policy hub's §3.1, the authority. **The hub schema wins on
  any mismatch, and a mismatch is a defect of THIS spec (or its seam carrier),
  never of the hub.** This spec defines only the **detector-specific divergence
  payload** carried inside that envelope; the seam CAP-4 staging emitter is the
  in-repo carrier and must itself conform to §3.1. This detector is **not the only
  emitter** into that intake — a hub-side fork-triage skill cites the same §3.1
  authority — so nothing here assumes a single emitter. Quotes and pointers use
  the existing `file:line@commit` grammar at the run's pin.
- Publication boundary: records, issues, and the ledger carry only the served
  pointer grammar already public in this repo — no upstream-internal paths or
  identifiers beyond it.
- Scripts are stdlib-only Python / POSIX shell in `scripts/` with `check-*.sh`
  harnesses (repo convention).

## Non-goals

- Whole-repo policy-realignment sweeps — the standing detector is
  consult-point-local over applied lines; full spec-tree reviews stay
  owner-invoked (the SPEC-policy-realignment pattern).
- Machine adjudication of which side is right: direction classification
  (CAP-1/CAP-5) locates a disagreement; it never resolves one.
- Automated upstream writes, PR automation against the upstream hub, or any
  helper that copies into the upstream intake.
- Generalizing the plumbing further: this is the third and last contracted
  consumer of the seam; a fourth requires its own owner decision.
- Semantic drift search over the whole policy surface (embeddings, similarity
  scans) — detection is anchored to lines a run actually applied.

## Success signal

A pipeline run (or consult-first session) that applies a policy line this
tool's current behavior has outgrown surfaces exactly one divergence candidate
quoting both the decision's evidence and the pinned upstream line; the owner
marks it "report upstream" and a schema-valid staging block appears in the run
workspace (or an issue in this repo) while the upstream hub shows zero changes;
re-running yields no duplicate prompt; and the same run with `policy_source`
absent completes identically with the detector skipped on one logged line.

## Assumptions

- The run artifacts' applied-line records (seam `consulted:` receipts; the
  consult-first rule's "which served lines you applied") are complete enough to
  anchor detection. If agent-session receipts prove too thin in practice,
  extending that receipt format is in scope for the implementing epic — adding
  a new consult surface is not.
- A repo-tracked ledger file is acceptable as the one new durable artifact this
  spec introduces (run workspaces are ephemeral, so dedup memory cannot live
  there). Its growth is bounded by the per-run cap and pin-expiry.
