# Review prompts and severity criteria

Shared prompt assets for the review passes (ported from the SPEC-article-review
companion). The **severity criteria table** below is the contract that makes a
finding's severity **auditable**: every finding names the criterion that sets
its severity (Story 12.1), so severity is assigned by a stated rule, never by
unstated reviewer taste.

## Severity criteria table (Story 12.1)

A finding's `Why {severity}:` rationale field names one criterion from this
table. The finding format is:

```
- [severity] {location}: {issue}. Why {severity}: {criterion}. Fix: {suggestion}.
```

| Severity | Criterion (what earns this severity) |
|---|---|
| **blocker** | a **quality-rubric dimension violation** (Epic 11: narrative arc / paragraph flow / explanation calibration / readability mechanics), a **cold-read Q1 (claim) or Q2 (audience) mismatch**, or a **configuration defect** |
| **should** | a **cold-read Q3 or Q4** finding, a **non-rubric structure/prose** issue (real, but not a rubric-dimension violation), or a **policy-contradiction** (Story 15.1: the article quote conflicts with a pinned recall-surface quote — never blocker alone, since a flagged reversal may be correct; the owner may escalate an individual finding in arbitration) |
| **nit** | **polish** — optional refinement with no correctness, clarity, or publishability cost |

- A **blocker** is publication-stopping: an open rubric-mapped blocker (or a
  configuration blocker) means review does **not** report the draft
  "publishable" (Story 12.2).
- A finding whose severity does not map to a row above — or that omits the
  `Why {severity}:` field — is a **contract violation**: it is re-authored to
  name its criterion, or dropped.

## Rubric-dimension anchor

The rubric dimensions a **blocker** may name are exactly the four in
[`../draft-article/quality-rubric.md`](../draft-article/quality-rubric.md):
narrative arc, paragraph flow, explanation calibration, readability mechanics.
A structure/prose finding that maps to one of these is **blocker-eligible**
(Story 12.2); one that does not is at most **should**.
