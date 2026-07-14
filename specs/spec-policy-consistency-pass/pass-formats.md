# Pass formats (companion to SPEC-policy-consistency-pass)

## 1. Finding (quote-vs-quote)

The review findings format (SPEC-article-review: location + severity +
criterion rationale + issue, ≤10, highest-leverage first) with the two-sided
evidence pair replacing the suggested fix — this pass proposes no diffs:

```
[should] drafts/intro.md:41 — policy-contradiction
  article:  "papers proves pull-based agent commands are the durable pattern."
            (drafts/intro.md:41)
  policy:   "Agent workflows must be push-based — scheduled, headless, …"
            (LESSONS.md:39@6357d9f…)
  issue: the draft asserts the opposite of the recorded push-based position.
```

Field set is the contract; rendering is illustrative. Both quotes are
verbatim; the policy pointer is `file:line@commit` at the run's pin (the
seam's harvest convention); severity defaults to `should`, criterion is
always `policy-contradiction`.

## 2. Arbitration choices (per finding, proposal contract)

| Choice | Effect (stated on the label) |
|---|---|
| Fix article | Finding accepted; the owner edits (review never auto-applies) |
| Position moved | Article stands; a staging-candidate block (seam CAP-4 / Story 14.5 emitter) records the reversal for the recall surface |
| Dismiss | No effect; recorded as dismissed in the arbitration record |

## 3. `consulted:` line (end of the review run artifact)

Same grammar as the interview seam's (seam `seam-formats.md` §4), mapping
checked policy lines to findings instead of questions:

```
consulted: product-lab@6357d9f… — LESSONS.md:39 → finding 1; GLOSSARY.md:123 → (no conflict)
```

Skipped-pass runs emit `consulted: none (policy_source unset)` or
`consulted: none (policy_source unavailable: <reason>)`.

## 4. Severity criteria table row (added to review-prompts.md)

| Criterion | Severity | Rule |
|---|---|---|
| policy-contradiction | should (never blocker alone) | Article quote conflicts with a pinned recall-surface quote; a flagged reversal may be correct, so it cannot gate "publishable" — owner may escalate per finding |
