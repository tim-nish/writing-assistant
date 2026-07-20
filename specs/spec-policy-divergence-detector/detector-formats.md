# Detector formats (companion to SPEC-policy-divergence-detector)

The two artifacts this detector introduces, plus the reused emission formats.
Field sets are the contract; concrete syntax is normative for machine-validated
artifacts (candidate record, ledger) and illustrative for gate presentation.

## 1. Divergence-candidate record

One record per flag, validated before it may reach the owner gate (CAP-2).

```json
{
  "id": "div-2026-07-20-001",
  "detected": "2026-07-20",
  "consult_point": "review:policy-consistency | interview:seeding | session:consult-first",
  "direction": "contradiction | outgrown",
  "decision": {
    "statement": "One sentence stating the implementation decision actually taken.",
    "evidence": "specs/spec-article-review/SPEC.md:38"
  },
  "policy": {
    "quote": "verbatim served line",
    "pointer": "LESSONS.md:41@<commit>",
    "pin": "<policy-source>@<commit>"
  },
  "rationale": "One sentence on why these two disagree.",
  "status": "candidate"
}
```

Validation rejects: a missing/empty quote, either pointer, or the pin; a
`direction` outside the two values; any additional field (the schema is closed
— in particular there is no verdict, severity, or proposed-resolution field).
`evidence` is a repo `path:line` or a run-artifact pointer; `statement` and
`rationale` are single sentences describing a disagreement, never resolving it.

## 2. Disposition ledger (`config/policy-divergence-ledger.json`)

Repo-tracked, append-and-tombstone, bounded by the per-run cap and pin-expiry
(CAP-4). Dedup key: (`policy.pointer` sans commit, `direction`,
`decision.evidence`).

```json
{
  "entries": [
    {
      "key": "LESSONS.md:41|outgrown|specs/spec-article-review/SPEC.md:38",
      "first_seen": "2026-07-20",
      "disposition": "reported | fix-here | dismissed",
      "ref": "#NNN | run-workspace path | null",
      "reason": "one line, required when dismissed",
      "pin_at_disposition": "<policy-source>@<commit>",
      "occurrences": 3
    }
  ]
}
```

An entry stops deduping (expires) when the current run's pin has advanced past
an upstream change touching the quoted line; expired entries are tombstoned,
never deleted. A deduped re-detection increments `occurrences` and prompts
nothing.

## 3. Gate presentation (illustrative)

Candidates enter the existing owner gate under the proposal contract —
Where/Why/Effect, journal entry per disposition:

- **Where:** the consult point and the decision's evidence pointer.
- **Why:** the quote-vs-quote pair — decision statement against the pinned
  upstream line — plus the one-sentence rationale.
- **Effect:** the three choices with their outcomes stated: *report upstream*
  (staging block in run workspace or issue in this repo; upstream untouched;
  you copy by hand), *fix here* (ordinary issue in this repo; no upstream
  proposal), *dismiss* (ledger entry with your reason; won't re-prompt).

## 4. Reused emission formats (no new upstream-facing format)

- **Staging-schema block:** the seam CAP-4 staging-candidate emitter schema
  verbatim (`seam-formats.md` §3) — the candidate's quote-vs-quote pair goes in
  the block's question/decision prose, framed as a policy-update *proposal*.
- **Tracker issue:** this repo's ordinary issue format carrying the candidate
  record body, titled by direction and subject, referencing the ledger key.
