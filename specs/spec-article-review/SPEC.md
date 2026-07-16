---
id: SPEC-article-review
companions:
  - review-prompts.md
sources:
  # Originating private site repo, decision round (traceability only).
  # Prior dogfooding review round (private; records removed 2026-07-16), traceability only.
  - ../../docs/dogfood-findings.md      # dogfood evidence behind the 2026-07-10 amendments
  - ../../docs/harness-architecture.md  # 2026-07-11 article-quality harness decision behind the 2026-07-11 amendments
---

> **Vendored copy.** Adopted verbatim from the originating private site repo (2026-07-09) per SPEC-writing-assistant; this copy is now the canonical version for this project. Bare archive references refer to that originating repo.
> **Amended 2026-07-10** per accepted dogfood findings (`docs/dogfood-findings.md`, prior dogfooding round): arbitration prompts follow SPEC-writing-assistant's owner-facing proposal contract; configuration defects are separated from article-quality findings and gate the "publishable" verdict.
> **Amended 2026-07-11** per the article-quality harness decision (`docs/harness-architecture.md`, D3): severity is criterion-anchored — findings carry a rationale field naming the criterion that sets their severity; quality-rubric violations are blocker-eligible and block "publishable".

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate. Source documents listed in frontmatter are for traceability only — consult them only if you need narrative rationale or prose color this contract intentionally omits.

# Article Review Workflow

## Why

A pain to solve: the owner wants article review that maximizes ROI while keeping token costs low, and initially framed editing as "process tokens" to minimize. Reframed (ratified owner decision §0.3): a published article is a permanent public artifact; the true process cost is unbounded iterative churn. The design goal is therefore maximum defect yield per pass with a fixed, small number of passes — mechanical checks cost zero tokens, LLM passes run once each on cheap models, and the owner arbitrates findings in a single round.

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
- Findings format (amended 2026-07-11): location + severity (blocker/should/nit) + **rationale naming the criterion that sets the severity** + issue + suggested fix, capped at 10 per pass; praise and summary forbidden; each pass names its single highest-leverage change first.
- **Severity is criterion-anchored** (added 2026-07-11 per `docs/harness-architecture.md` D3): a finding is a blocker only by naming its criterion — a quality-rubric dimension violation (the draft pipeline's stage 3→4 gate rubric, re-checked here as the second net), a cold-read Q1/Q2 mismatch, or a configuration defect. Rubric-mapped structure/prose findings are blocker-eligible, and an open one blocks the "publishable" verdict exactly as configuration blockers do. The full severity criteria table lives in `review-prompts.md`; severity assigned without a named criterion is a contract violation, not reviewer judgment.
- Review passes use cheap-tier models (Sonnet class; Haiku class for the mechanical end) and run grounded in the repo (Claude Code) so factual claims can be checked against sources. Drafting-model choice is SPEC-article-draft-pipeline's concern.
- The owner is the arbiter: findings are accepted/rejected in one round; no auto-applied edits. Arbitration presentation obeys SPEC-writing-assistant's **owner-facing proposal contract**: each finding shows where it sits in the article, why it is raised, and accept/reject choices stating their concrete effect on the article.
- **Configuration defects are not article findings** (added 2026-07-10): unresolved config placeholders, malformed URLs, and schema-invalid frontmatter caused by configuration route to the completion summary's publish-blocker bucket (SPEC-article-draft-pipeline CAP-6), not into the capped prose/structure findings lists — and review never reports a draft "publishable" while a configuration blocker is open. Up-front detection is SPEC-article-draft-pipeline CAP-5's contract; review's lint pass (CAP-1) is the backstop that re-checks it.

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
- **Owner proposal (2026-07-16, owner decision record: review pipeline complete) — persist arbitration outcomes as dogfood events.** The arbitration round (owner accepts/rejects each finding) currently records nothing, so the reviewer can never be calibrated against its own acceptance history. Proposed: one emit per finding disposition into the dogfood ledger (source: `review-arbitration`; fields: pass, criterion, severity, disposition, one-line reason on reject) — raw events only, no classification at emit time; a criterion whose findings are chronically rejected then surfaces through the dogfood tool's existing recurrence bar as a "tune or demote this pass" proposal. No new subsystem, no new report. Proposal-only: adopting it means one emit call in the arbitration step; declining leaves reviewer calibration to memory.
