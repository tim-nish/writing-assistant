---
name: policy-divergence-detector
description: >
  Flag when this tool has moved past an upstream policy line it once consulted
  — the consumer-side counterpart to the seam's staleness machinery. A flag is
  a divergence candidate, never a determination; emission is proposal-only and
  the upstream hub is never written (spec-policy-divergence-detector, #436).
---

# Policy-divergence detector (consumer-side)

Flag when **this tool has moved past** an upstream policy line it once consulted
— the opposite direction from the seam's staleness machinery (which catches the
upstream moving under us). A flag is a **divergence *candidate*, never a
determination**; emission is **proposal-only** and the upstream hub is never
written. Contract: `specs/spec-policy-divergence-detector/SPEC.md` (#436,
ratified 2026-07-20) + companion `detector-formats.md`.

This skill is the runtime wiring; the mechanics live in two scripts it drives:

- `scripts/validate-divergence-candidate.py` — the record/ledger schema, the
  CAP-5 direction guard, the CAP-4 dedup key (the foundation).
- `scripts/detect-policy-divergence.py` — the CAP-1 pass and the CAP-3/CAP-4
  disposition emit side (invokes the foundation).

## When it runs (CAP-1) — the three consult points, applied lines only

The pass runs **after** a run has recorded which served policy lines it
**applied**, at the points the tool already consults the surface — it adds
**zero** gateway reads:

- **`review:policy-consistency`** — after the policy-consistency review pass
  records the served lines it weighed.
- **`interview:seeding`** — after Stage-2 interview seeding records which policy
  lines seeded questions (the journal `consulted:` line).
- **`session:consult-first`** — after an agent session's consult-first step
  records "which served lines you applied".

At each point, the classification step (LLM-assisted, but its output is only ever
a candidate) proposes, per applied line, whether the decision actually taken is a
**contradiction** or an **outgrowing** of that line — and hands the driver a
**raw flag** carrying `consult_point`, `direction`, `rationale`,
`decision{statement, evidence}`, `policy{quote, pointer, pin}`, and the
`current_line` (the served line at the run's **current** pin). Everything after
that is mechanical:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/detect-policy-divergence.py run \
  --input "$WS/divergence-flags.json" \
  --ledger config/policy-divergence-ledger.json --detected <date>
```

The driver applies the **CAP-5 direction guard** (a changed `current_line` means
the *upstream* moved — routed to the seam's stale/reconcile machinery, never a
candidate), **validates** each record fail-closed, **dedups** against the ledger,
and **caps at ≤3** (highest-leverage first; the overflow is counted, never
silently dropped). Its output is the candidate list — nothing is emitted yet.

## The owner gate (CAP-3) — proposal-only, three choices

Each surviving candidate enters the run's **existing owner gate under the
[proposal contract](../owner-facing-proposal-contract.md)** (selective prompts,
Where/Why/Effect, a journal entry per disposition — `detector-formats.md` §3):

- **Where:** the consult point and the decision's evidence pointer.
- **Why:** the quote-vs-quote pair (decision statement against the pinned
  upstream line) plus the one-sentence rationale.
- **Effect — the three choices:**
  - **report upstream** — emit the proposal: a **tracker issue in this repo**
    carrying the record, or a **staging-schema block** in the run workspace. The
    staging block is a **conformance copy of the hub §3.1 schema** (the
    configured policy hub's §3.1 schema is the authority; hub wins on any
    mismatch, `detector-formats.md` §4); the owner **copies it by hand**. The
    upstream hub is untouched.
  - **fix here** — the divergence is a consumer defect: route to this repo's
    tracker as an ordinary issue; no upstream proposal.
  - **dismiss** — not a divergence; a one-line reason, remembered.

Nothing is emitted without the owner's choice, and **no path touches the
upstream hub**. Record the disposition to the ledger:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/detect-policy-divergence.py disposition \
  --ledger config/policy-divergence-ledger.json \
  --key "<pointer|direction|evidence>" --disposition <reported|fix-here|dismissed> \
  --pin "<policy-source>@<commit>" [--reason "<one line, required if dismissed>"] \
  [--ref "#NNN | run-workspace path"]
```

## Dedup and expiry (CAP-4)

The ledger (`config/policy-divergence-ledger.json`) remembers every disposition,
keyed by (**pointer sans commit**, direction, decision evidence). A subsequent
run's same divergence is **deduped** — the entry's occurrence count bumps, no
second prompt — until the entry **expires**: the run's pin has advanced past an
upstream change touching the quoted line, so the comparison is live again.

## Invariants (from the spec)

- **Never machine-final.** No auto-filed upstream proposal, no auto-applied
  change, no sync pipeline — every emission sits behind the owner's choice.
- **Never blocks a run.** Any detector-internal error skips the pass with one
  logged line (the seam's degradation discipline); `policy_source` absent →
  the pass is skipped entirely.
- **Not the only §3.1 emitter.** A hub-side fork-triage skill emits into the
  same intake under the same authority — shared envelope, distinct payloads.
