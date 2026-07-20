---
id: SPEC-policy-consistency-pass
companions:
  - pass-formats.md
  - ../spec-policy-source-seam/SPEC.md        # adopted: the seam plumbing this pass consumes (reader, pin, consulted, staging emitter)
  - ../spec-article-review/SPEC.md            # adopted: the review pipeline this pass joins (pass order, findings format, arbitration)
  - ../spec-article-review/review-prompts.md  # adopted: severity criteria table carries the policy-contradiction row
sources:
  # Authoritative external contract §3 — owner decision record 2026-07-14 (writing-assistant seam),
  # held in the owner's private policy hub, retrievable by date + title (read-only).
---

> **Adopted 2026-07-14.** Promoted from `_bmad-output/specs/spec-policy-consistency-pass/` (BMAD-generated, owner-approved 2026-07-14, implemented as Epic 15, issues #197–#200, PRs #201–#204) per the canonical-spec promotion convention (README "BMAD / hand-written separation", #188); **this copy is now the canonical version**. The BMAD memlog stays with the generating workspace — process state, not contract.

> **Amended 2026-07-20 (#436)** per the owner decision record 2026-07-20 (consumer-triggered policy feedback): the "no third consumer of the seam" non-goal below is **superseded** — the consumer-side policy-divergence detector (SPEC-policy-divergence-detector) is sanctioned as the seam plumbing's third consumer, detection-only and proposal-only. This pass's own contract is unchanged.

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate. Source documents listed in frontmatter are for traceability only — consult them only if you need narrative rationale or prose color this contract intentionally omits.

# Policy-Consistency Review Pass (A2)

## Why

The ratified 2026-07-14 seam decision ordered two consumers of one read/pin/consulted plumbing: the interview seam (A1, shipped as Epic 14 and dogfooded) first, then this output-side check as the second — proportionality to the first use case rather than a cross-repo framework. The gap it closes: a draft can now *assert* something that contradicts a position recorded in the owner's policy hub, and nothing catches it before publication. The pass is contradiction detection for the owner's judgment — never a conformity filter: a flagged conflict may mean the article is wrong, or that the position moved, and only the owner decides which; a correct reversal routes back to the recall surface as a staging-candidate block while the article stands.

## Capabilities

- **CAP-1** — a pass inside the existing review pipeline
  - **intent:** review-article's fixed order becomes lint → structure → prose → **policy-consistency** → cold read: one cheap-tier LLM pass per draft version that reads the draft plus the bounded policy surface and flags claims conflicting with recorded positions. Cold read stays last so its no-context isolation is untouched; no new tool, no new invocation surface.
  - **success:** A draft asserting the opposite of a pinned LESSONS line yields exactly one finding from this pass; a draft with no conflicts emits nothing (no praise, no summary); the pass runs once per draft version like CAP-2/CAP-3 of SPEC-article-review.
- **CAP-2** — quote-vs-quote findings
  - **intent:** Each finding pairs the article line (quote + `path:line`) with the recall-surface line it conflicts with (quote + `file:line@commit` at the run's pin), plus severity, criterion rationale, and the issue stated in one sentence — and **no suggested rewrite**: unlike the other passes' suggested-fix field, this pass proposes no diffs (companion `pass-formats.md`).
  - **success:** Every emitted finding carries both pointers and both verbatim quotes; auditing either side resolves at the stated location/commit; findings are capped at 10 (review constraint) with the highest-leverage conflict first.
- **CAP-3** — owner arbitration with reversal routing
  - **intent:** Findings enter the same single arbitration round as every other pass, under the owner-facing proposal contract, with three effect-stating choices: **fix article** (owner edits; the finding is accepted), **position moved** (the article stands; the run emits a staging-candidate block — the Story-14.5 emitter — recording the reversal for the recall surface), **dismiss** (no effect). Nothing is ever auto-applied.
  - **success:** Choosing "position moved" produces a schema-valid staging-candidate block in the run workspace and does not change the draft or its "publishable" eligibility; the review never edits the article or any file under `policy_source.path`.
- **CAP-4** — shared seam plumbing, verbatim
  - **intent:** The pass consumes SPEC-policy-source-seam's plumbing unchanged: the same `policy_source` key, the same bounded pinned read (`read-policy-source.py` — GLOSSARY, LESSONS, ≤2 track-matched topics, whitelist in code), the same pin, and the review run artifact ends with the same `/ask`-style `consulted:` line mapping checked policy lines to the findings they produced (`consulted: none (...)` otherwise).
  - **success:** No new reader, config key, or pointer format exists after this epic; the review artifact's `consulted:` line names the pin and every finding's policy source; a run with `policy_source` absent or unusable skips the pass with one logged line and the rest of the review completes unchanged.
- **CAP-5** — criterion-anchored severity for policy conflicts
  - **intent:** `review-prompts.md`'s severity criteria table gains a **policy-contradiction** row: default severity **should**, never blocker by itself — a flagged reversal may be *correct*, so a policy conflict cannot gate "publishable"; the owner may escalate any individual finding during arbitration.
  - **success:** A policy finding always names `policy-contradiction` as its criterion (severity without a named criterion stays a contract violation); an unarbitrated policy finding does not block the "publishable" verdict.

## Constraints

- **Contradiction only, never conformity:** the pass flags conflicts; it never suggests aligning the article to policy, never proposes diffs, and never auto-conforms — the owner's arbitration is the only path to any change.
- Pass mechanics inherit SPEC-article-review verbatim: once per draft version, cheap tier, ≤10 findings, no rewritten text, owner is sole arbiter, proposal-contract presentation.
- The policy surface read is the seam's bounded read — nothing beyond GLOSSARY.md, LESSONS.md, and the ≤2 matched topics; never the hub's history archive; never a write under `policy_source.path`; staging-candidate blocks land in the run workspace only, hand-copied by the owner.
- Cold-read robustness (seam side effect, this epic's cleanup): the cold-read comparison against the interview journal's q2/q5 entries must tolerate a **capped** q5 (policy seeds can displace it under the ≤5 budget) — it reports an absent anchor as a finding-free note, never fails the pass.
- Scripts stay stdlib-only Python / POSIX shell with `check-*.sh` harnesses (repo convention).

## Non-goals

- Auto-conforming rewrites, auto-applied fixes, or any diff proposal from this pass.
- Automated writes into the policy hub (staging emission stays proposal-only, workspace-only).
- Extending the cold read's context (it remains isolation-by-design; the policy surface is never shown to it).
- Semantic search, embeddings, additional policy repos, or any read beyond the seam's whitelist.
- ~~A third consumer of the seam — nothing here generalizes the plumbing beyond its two ratified users.~~ **Superseded 2026-07-20** (top-of-file amendment, #436): the policy-divergence detector is the sanctioned third consumer.

## Success signal

A review run over a draft that contradicts one pinned recall-surface line produces exactly one quote-vs-quote finding with both pointers; the owner marks it "position moved", a staging-candidate block appears in the run workspace, the draft's verdict is unaffected — and the same review with `policy_source` removed completes with the pass skipped on one logged line.

## Assumptions

- The pass runs grounded in the host repo (Claude Code) like the other review passes, so article-side quotes can carry `path:line` pointers to the draft file.
- The staging-candidate emitter (Story 14.5) is reusable from the review flow with a finding-shaped input — if its interview-answer coupling proves too tight, a small refactor is in scope for this epic.
