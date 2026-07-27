# Review article — arbitration

Companion of [`SKILL.md`](../SKILL.md) (the dispatcher). Read on entry to the
**arbitration phase**: the pinned presentation, reject-only arbitration, the
events emission, policy three-way choices, blocker eligibility, and the
second-cycle gate.

## Arbitration

After lint, structure, prose, policy consistency, and cold read have run,
collect their findings into one list and hand it to the owner. The **owner is the sole arbiter**.

**Pinned presentation (SPEC-review-ux CAP-2, Story 13.32) — the round opens
with the consolidated findings list.** This presentation is contract, not
discretion: findings **de-duplicated across passes** (two passes raising the
same defect become one finding **with cross-pass agreement noted as votes**),
each finding **numbered**, **severity-tagged**, **location-anchored**, and
carrying its **one-sentence issue and its fix** — ranked **blockers → should →
nit, highest-leverage first**. The findings **format** itself (capped ≤10 per
pass, severity-tagged, no rewrites — *Findings contract*) is unchanged; this
pins how the consolidated list is shown.

**Reject-only arbitration (SPEC-review-ux CAP-3, Story 13.32).** Acceptance is
the overwhelming default, so the interaction costs attention only for
exceptions. **Ordinary findings** — lint, structure, prose, cold-read, every
severity — **default to ACCEPTED**: ask the owner **once**, "these N findings
will be applied — deselect any to reject" (a multi-select; an empty selection
= apply all). Presentation still follows the
[owner-facing proposal contract](../owner-facing-proposal-contract.md) —
**where** it sits in the article (the finding's `{location}`), **why** it is
raised, and choices whose labels state their **concrete effect on the article**:
keeping a finding selected means "apply the fix to the article", deselecting
means "leave the article unchanged" — never a bare accept/reject the owner
must decode. This is a presentation wrapper only: it **does not change** the
capped (≤10), severity-tagged findings **format** from *Findings contract*.
Two exceptions stay explicit, never defaulted:

- **policy-contradiction findings** keep their three-way choice (below) — no
  safe default exists: defaulting to "fix article" would auto-align the
  article to policy (SPEC-policy-consistency-pass forbids it), defaulting to
  "dismiss" would bury the tension the seam exists to surface;
- **a finding whose fix would alter owner-approved content** (an approved
  interview answer used as a sourced claim, an approved visual — NFR12) is
  asked explicitly.

Every finding still receives an **explicit recorded disposition** —
accepted-by-default is journaled as *accepted*; the journal and summary stay
complete.

**The single arbitration round.** One pass over the consolidated list:

- **No finding is skipped and none is auto-applied.** Apply an accepted fix
  yourself, or via **one targeted edit instruction per finding**; never
  open-ended rewriting.
- **A rejected finding is rejected.** Do **not** re-litigate it in a later pass or
  a second cycle — the decision stands.
- The round is **top-down and single-pass** over the ranked list: the
  highest-leverage findings are resolved before the nits.

**Arbitration events — one emit per disposition (SPEC-article-review CAP-5,
Story 13.42).** When the round completes, persist every finding's disposition
as a **raw dogfood event** — this is how the reviewer gets calibrated against
its own acceptance history (a chronically-rejected criterion surfaces through
the dogfood tool's recurrence bar as a "tune or demote this pass" proposal;
that analysis never runs here). Build one JSON line per arbitrated finding —
`{"pass", "criterion", "severity", "disposition", "reason"?, "anchor"?}`,
`reason` required on `rejected` and `anchor` the finding's location (e.g.
`L64:exploration-axes`) so distinct findings stay distinct and recurrence
collapses correctly (#497) — and emit:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/emit-arbitration-events.py <dispositions.jsonl> \
  --ws "$WS" --scenario <draft-slug>
```

Exactly N events for N findings, **nothing judged or classified at emit time,
no new report**. The events always land in `$WS/arbitration-events.jsonl`;
when the owner's user config declares an optional `dogfood.ingest_cmd`, the
emitter also feeds them to the dogfood ledger — absent or failing, it logs
one line and the run continues (enhancer, never a dependency; the workspace
file remains for offline mining).

**Policy-consistency findings arbitrate with three choices (Story 15.2).** A
`policy-contradiction` finding is contradiction detection, not a fix proposal,
so its choices differ from accept/reject — each label stating its concrete
effect:

- **Fix article** → "edit the article to resolve the conflict" — the owner
  edits (or gives one targeted edit instruction); never auto-applied;
- **Position moved** → "the article stands; record the reversal for the recall
  surface" — the run emits a **staging-candidate block** (the Story-14.5
  emitter, `--findings` form) into the run workspace for the owner to
  hand-copy into the hub's staging area; the draft text and its "publishable"
  eligibility are unchanged;
- **Dismiss** → "no effect" — recorded as dismissed.

After the round, emit the position-moved blocks in one call:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py staging-candidates \
  --findings <arbitrated-findings.json> --source-repo <host repo name> \
  --created <run date> [--tag <track>] > "$WS/staging-candidates.md"
```

An **unarbitrated or open policy finding never blocks "publishable"** —
criterion `policy-contradiction` is never blocker alone (a flagged reversal
may be correct); escalation is a per-finding owner call inside the round, and
nothing in the policy hub is ever created or modified (the consumer holds no
hub path at all — Story 13.73; the gateway serves read-only).

**Rubric-mapped findings are blocker-eligible (Story 12.2).** A structure or
prose finding that **maps to a quality-rubric dimension** (Epic 11: narrative
arc, paragraph flow, explanation calibration, readability mechanics — the same
dimensions a blocker's `Why blocker:` rationale names, per Story 12.1) is
**blocker-eligible**: it may be assigned `blocker`, exactly as a cold-read Q1/Q2
mismatch or a configuration defect. Review is a real **second net** for the
Stage 3→4 quality gate, not merely advisory — a rubric violation that slipped the
gate is a publication-stopping finding here.

**Second-cycle gate.** After the round:

- If a **blocker-severity finding survived** the fixes (the canonical cases: a
  cold-read **claim/audience mismatch**, or a **rubric-mapped structure/prose
  blocker**, still present after edits), trigger
  **exactly one additional full cycle** — lint → structure → prose → cold read
  again on the new draft version. **One** — the workflow never loops unbounded.
- **Otherwise the draft is publishable.** No surviving blocker ⇒ done — **unless
  an open rubric-mapped blocker or a configuration blocker remains**, in which
  case review does **not** report the draft "publishable" until it is fixed (the
  zero-token lint pass re-checks configuration as the backstop to Story 7.4).

**Per-pass model routing (recap).** Each pass runs on the tier and grounding in
the *Model routing* table above: **lint** is the zero-token script; **structure**
and **prose** run on a **Sonnet-class model with repo access** so claims are
checked against the sources; **cold read** runs on **any cheap model, context-free
by design**. The second cycle, if triggered, uses the same routing.
