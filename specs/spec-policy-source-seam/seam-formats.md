# Seam formats (companion to SPEC-policy-source-seam)

The three wire formats the seam introduces. Field sets are the contract; the
concrete syntax shown is normative for machine-validated artifacts (items,
staging blocks) and illustrative for the human-facing `consulted:` line.

## 1. `policy_source` config block (`writing-sources.yaml`)

```yaml
policy_source:                     # optional — absent = generic interview, silently
  path: ../policy-hub              # local checkout of the owner's policy repo, resolved against host-repo root
  track: eval-engineering          # optional — backlog track; matches topics/<stem>*.md
  topics: [eval-engineering.md]    # optional — explicit override, basenames under topics/, max 2
```

Validation (stage 0, `validate-config` path): `path` must be a string;
`topics` entries must be plain basenames (no `/`, no `..`); `topics` length
≤ 2. A malformed block is a configuration error naming key and fix. A
well-formed block whose path is unusable at run time is NOT a config error —
that is CAP-6 degradation.

## 2. Interview item

Every Stage-2 candidate question, seeded or generic, is one item:

```json
{
  "id": "q3",
  "gap_type": "contradiction",
  "seed": {
    "quote": "verbatim policy line(s)",
    "pointer": "LESSONS.md:41@8f3c2d1"
  },
  "question": "one owner-facing question",
  "owner_answer": ""
}
```

- `gap_type` ∈ existing NEEDS-OWNER taxonomy (`audience`, `motivation`,
  `surprise`, `tradeoff`, `significance`, `warning`) ∪ tension types
  (`contradiction`, `ambiguity`, `missing-rationale`, `reversal-candidate`).
- Tension types are the only types a policy seed may generate; a generic
  item carries `seed: null`.
- `pointer` is `file:line@commit` (`file:line1-line2@commit` for a wrapped
  quote), file path relative to `policy_source.path`, commit = the run's pin.
- `owner_answer` is structurally empty at generation.

Validator rejection classes (each a seeded test fixture):

| # | Rejects | Guards |
|---|---|---|
| R1 | `owner_answer` non-empty at generation | tool cannot pre-decide |
| R2 | tension-typed item with `seed: null` | traceability is a rule, not a convention |
| R3 | seed whose `pointer` is missing/unpinned/outside the whitelist | every quote auditable at the pinned commit |
| R4 | seeded question that restates its seed (confirmation-shaped) | tension, not confirmation |
| R5 | `gap_type` outside the taxonomy | closed vocabulary |

## 3. Staging-candidate block (run output, proposal-only)

Emitted when an interview answer contains a durable decision or reversal;
schema mirrors the policy hub's staging-area frontmatter. The owner copies
accepted blocks by hand.

```markdown
<!-- staging-candidate -->
---
slug: 2026-07-14-<kebab-gist>
created: <run date>
source_repo: <host repo name>
perishable: true|false
tags: [<track>, ...]
---
Q: <the interview question, full sentence>
Decision: <the owner's answer as a durable statement, full sentences>
```

## 4. `consulted:` line (end of interview run artifact)

```
consulted: policy-hub@8f3c2d1 — GLOSSARY.md#writing-assistant → q2;
LESSONS.md:41 (report-trust-is-structural) → q3; topics/eval-engineering.md:12-14 → q5
```

Generic-mode runs emit `consulted: none (policy_source unset)` or
`consulted: none (policy_source unavailable: <one-line reason>)`.
