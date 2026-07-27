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
| **blocker** | a **quality-rubric dimension violation** (Epic 11: narrative arc / paragraph flow / explanation calibration / readability mechanics), a **cold-read Q1 (claim) or Q2 (audience) mismatch**, a **configuration defect**, or — **on a derived canonical only** — a **declared-convention violation** (Story 20.4; see below) |
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

The four are **not extended** by the declared-convention criterion below: that
criterion is a sibling of the rubric, never a fifth dimension. `rubric-version`
in `quality-rubric.md` is unchanged, and EN drafts and the Stage 3→4 draft gate
see no behavior change.

## Declared-convention conformance — derived canonicals only (Story 20.4, #800)

**Applies when, and only when, the draft carries an `adapted_from` pin** — the
derived-canonical discriminator (`scripts/draft-pipeline.py`, `_ADAPTED_FROM`).
An **authored** canonical is graded by exactly the three criteria that predate
this section; this one never fires on it.

**What it grades.** The target language's own declaration in
`config/language-conventions.yaml`, keyed by the draft's `language` field:

- `register` — e.g. `ja` declares です/ます (polite form), consistent
  throughout, no mixed 常体.
- `terminology` — e.g. `ja` declares technical terms kept in English or
  established katakana, never force-translated.

**Why this is a criterion and not taste.** The same declaration is already
authoritative on the way *in*: adaptation reads it to decide how to write
(`scripts/adapt-canonical.py`). Grading against it at review makes the pipeline
check what it instructed, rather than inventing a second standard. A finding
here names the declared convention it violates — that is the criterion the
`Why {severity}:` field must carry.

**Undeclared language ⇒ skip, and disclose the skip.** A `language` with no
entry in the conventions file is **not** graded and **not** reported as a
defect; the pass states that it skipped. This follows the ratified precedent
for the title claim-verb test (#701): a check that cannot judge a whole
artifact class must not report on it, and silence beats a false positive that
trains the owner to ignore the lint.

**Scope discipline.** The criterion is artifact-class-scoped by design; the
blocker anchor holds only while that scoping does. Extending it beyond derived
canonicals is a spec change (SPEC-article-review), never a prompt edit.

## Finding class — writing-problem vs missing-input (Story 13.62)

Orthogonal to severity, every finding carries a **class** that says what can
repair it (SPEC-article-review):

- **writing-problem** (the default, unmarked) — fixable in the draft: a cut, a
  reorder, a clarity edit. It carries a `Fix: {suggestion}` field, exactly as
  above.
- **missing-input** — the draft lacks *source material* (insufficient
  evidence, a missing example/episode, an unsupported narrative claim) that
  prose editing cannot manufacture. It is marked `[missing-input]` after its
  severity, and instead of `Fix:` it names an **upstream remediation** — one
  of exactly two forms:
  - `Upstream: re-harvest {scoped target}` — a narrowed source set to harvest;
  - `Upstream: ask {one bounded owner question}` — a single elicitation.

  A missing-input finding is **blocker-eligible**: an unrepaired one blocks the
  "publishable" verdict, exactly as a rubric or configuration blocker does. It
  routes to the pipeline's bounded missing-input repair hop
  (SPEC-article-draft-pipeline), never to a prose fix.

Finding format by class:

```
writing-problem:  - [severity] {location}: {issue}. Why {severity}: {criterion}. Fix: {suggestion}.
missing-input:    - [severity] [missing-input] {location}: {issue}. Why {severity}: {criterion}. Upstream: re-harvest {target} | ask {question}.
```

The two shapes are mutually exclusive and mechanically checked
(`validate-review-findings.py`): a `[missing-input]` finding carrying only a
prose `Fix:`, or a writing-problem finding carrying an `Upstream:`, is a
**contract violation** — the review pass that raised the finding owns the
classification (isolation), never the drafting agent.
