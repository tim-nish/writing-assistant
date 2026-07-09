---
id: SPEC-article-review
companions:
  - review-prompts.md
sources:
  - ../../../website/q_a/2/question.md  # external: website repo (sibling checkout), traceability only
  - ../../../website/q_a/2/answer.md    # external: website repo (sibling checkout), traceability only
---

> **Vendored copy.** Adopted verbatim from the website repo (`website/_bmad-output/specs/spec-article-review/`, 2026-07-09) per SPEC-writing-assistant; this copy is now the canonical version for this project. Repo-internal references (`q_a/…`) refer to the website repo.

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate. Source documents listed in frontmatter are for traceability only — consult them only if you need narrative rationale or prose color this contract intentionally omits.

# Article Review Workflow

## Why

A pain to solve: the owner wants article review that maximizes ROI while keeping token costs low, and initially framed editing as "process tokens" to minimize. Reframed (q_a/2 answer §0.3): a published article is a permanent public artifact; the true process cost is unbounded iterative churn. The design goal is therefore maximum defect yield per pass with a fixed, small number of passes — mechanical checks cost zero tokens, LLM passes run once each on cheap models, and the owner arbitrates findings in a single round.

## Capabilities

- **CAP-1**
  - **intent:** A zero-token lint script checks every draft mechanically: frontmatter validity against the article schema, title length, pointer-block presence, heading density, dead links.
  - **success:** Running the script on a draft with a seeded defect of each kind reports all of them with file/line, consuming no LLM tokens.
- **CAP-2**
  - **intent:** A structural pass (cuts, reordering, missing/redundant sections) runs once per draft version on a cheap model, producing a capped findings list.
  - **success:** Output is ≤10 findings, each location + severity + issue + suggested fix; no rewritten text; a draft with a misplaced section gets a corresponding finding.
- **CAP-3**
  - **intent:** A prose pass (clarity, tone, hedging, jargon) runs once per draft version after structure is settled, same findings format.
  - **success:** Same format criteria as CAP-2; zero output tokens spent on praise or summary.
- **CAP-4**
  - **intent:** A cold read by a model with no project context answers a reader rubric — what is the article's claim, who is it for, what was unclear — simulating the actual reader.
  - **success:** A draft relying on unexplained repo-internal context yields a cold-read answer that misstates the claim or flags the gap, demonstrating the pass catches missing-context defects.

## Constraints

- Fixed pass order: lint → structure → prose → cold read. Structure precedes prose because structural changes invalidate prose feedback.
- Each LLM pass runs exactly once per draft version; a second full cycle only if a blocker-severity finding survives the owner's arbitration round.
- Findings format: location + severity (blocker/should/nit) + issue + suggested fix, capped at 10 per pass; praise and summary forbidden; each pass names its single highest-leverage change first.
- Review passes use cheap-tier models (Sonnet class; Haiku class for the mechanical end) and run grounded in the repo (Claude Code) so factual claims can be checked against sources. Drafting-model choice is SPEC-article-draft-pipeline's concern.
- The owner is the arbiter: findings are accepted/rejected in one round; no auto-applied edits.

## Non-goals

- No automatic application of fixes without owner acceptance.
- No multi-agent adversarial review as the default (reserve `bmad-code-review`-style layering for exceptional pieces).
- No grammar-tool or external SaaS integration.
- No review of unpublished ideas or outlines — the unit of review is a framework-complete draft.

## Success signal

A framework-complete draft goes from "review requested" to "publishable" within one lint run, three single LLM passes, and one owner arbitration round — and a seeded-defect draft (one structural, one prose, one missing-context, three mechanical defects) has every seed caught by the designated pass.

## Assumptions

- The installed `bmad-editorial-review-structure` and `bmad-editorial-review-prose` skills are the implementation vehicles for CAP-2/CAP-3, parameterized by the prompts in `review-prompts.md`, rather than building new reviewers from scratch.

## Open Questions

- Should the cold read (CAP-4) run on a non-Claude provider for a stronger independent-reader simulation, or stay single-provider for workflow simplicity?
