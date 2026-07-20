# Review artifact lifecycle

What `review-article` writes, where, and when — and the one workflow convention
that makes review edits legible in git history. Derived from the current
implementation and specs; normative wording stays in the contracts it points
at. This complements [`pipeline-vocabulary.md`](pipeline-vocabulary.md) (the
draft side); the canonical review contract is
[`specs/spec-article-review/SPEC.md`](../specs/spec-article-review/SPEC.md).

Current behaviour is **spec-conformant, not a bug** — this page exists because
the lifecycle surprised an owner during dogfooding, not because anything needs
changing.

## review-article writes nothing into the host working tree

By contract, a review run reports its findings to the owner and **persists no
files into the host repo**. After a run, `git status` shows **nothing new** —
no `scratch/`, no findings log, no intermediate. Anything a pass needs to
persist goes to the run's workspace **outside** the host repo (resolved by the
path resolver). See the "Host-repo footprint (leave nothing behind)" section of
[`skills/review-article/SKILL.md`](../skills/review-article/SKILL.md).

The single exception is the deliberate one below: when the owner accepts
findings that edit the article.

## Accepted findings re-persist the canonical draft in place

When an arbitration round applies ≥1 accepted finding, the edited draft is
written back to **the same canonical path the draft flow wrote**
(`drafts/<slug>.md` at `output.drafts`), through the **same write path and
trailer convention** as draft-complete. There is:

- **no separate "reviewed" copy** — the canonical is edited in place;
- **no pre-review snapshot** — review takes none.

The edited canonical then re-enters the verification regime before anything is
reported done — the provenance map is rebuilt and revalidated, scoped
regression checks run, and existing variants are marked stale (the
**post-arbitration re-entry** constraint,
[`spec-article-review/SPEC.md`](../specs/spec-article-review/SPEC.md), added
per #362). Review **never emits or re-emits a platform variant**; re-emission
is a fresh, explicit owner publish decision.

A round that accepts **zero** findings leaves the draft, its provenance map,
and any variants untouched.

## `reviews/` is not review-article's

The host repo's `reviews/` directory is **not** written by `review-article`.
It is the output location of the separate, **record-only calibration panel**
(the `/review-draft` multi-role review) — a different tool with a different
purpose. If you expect review reports to appear somewhere, this is why they do
not appear under `reviews/` after a `review-article` run: that run produced
none.

## Durable outcomes are arbitration events, not reports

`review-article` writes no report file. The durable record of a review is the
set of **arbitration events** — one event per finding disposition, source
`review-arbitration`, emitted to the dogfood ledger (CAP-5,
[`spec-article-review/SPEC.md`](../specs/spec-article-review/SPEC.md)). They
exist so a chronically-rejected criterion can surface later as a "tune or
demote this pass" proposal; there is no per-run report artifact to look for.

## Convention: commit the canonical before running review

Because the host repo is git and accepted findings edit the canonical **in
place**, commit the canonical draft at **draft-complete, before running
review**. Then review's in-place edits diff cleanly against history — a
straightforward before/after comparison of exactly what arbitration changed —
with **no new snapshot mechanism** needed. This is a workflow convention, not a
pipeline change.

## See also

- [`specs/spec-article-review/SPEC.md`](../specs/spec-article-review/SPEC.md)
  — the review contract (CAP-5 arbitration events; the post-arbitration
  re-entry constraint).
- [`skills/review-article/SKILL.md`](../skills/review-article/SKILL.md) — the
  review workflow, including the host-repo footprint rule.
- [`pipeline-vocabulary.md`](pipeline-vocabulary.md) — the draft-side
  vocabulary and data flow.
