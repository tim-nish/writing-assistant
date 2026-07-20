# SPEC — policy-directed editorial strategy (Tsurezure as the product)

**Status: RATIFIED (2026-07-15, owner, via /triage-gh on #231) — direction,
invariants, and both open-question resolutions ratified; CAP-1–4 decomposed
into stories 13.37–13.40, CAP-5 stays deferred.**
Origin: owner redefinition during dogfood round 2: writing-assistant is no
longer primarily an article-writing tool; it is the dedicated demonstration
that a personal policy corpus (Tsurezure) measurably improves knowledge
work. Companion evidence: in the 2026-07-15 QSB run the single
highest-leverage editorial decision — lead with a finished argument
("reproducibility is the feature") instead of a capability tour — was
produced by one policy seed (`LESSONS.md:36 → p1`), with the facts
unchanged. Policy already directs editorial strategy; this spec makes that
influence first-class, bounded, and audited instead of incidental.

## Why — the generalized pattern

What made the QSB seed work was not the specific lesson but the mechanism:

> **pinned durable-judgment corpus × fresh artifact → tension proposal →
> owner arbitration → proposal-only write-back, every influence audited.**

Three properties made it safe *and* effective, and they are the invariants
every extension below must preserve:

1. **Policy proposes; the owner ratifies.** A recorded position generates a
   question or a recommended default — never a silent decision (SPEC-policy-source-seam CAP-2's
   generalization).
2. **Policy never supplies facts.** Provenance classes are untouched: an
   editorial direction is not a source pointer, and no policy line ever
   grounds a factual claim in the draft.
3. **Every influence is audited.** The `consulted:` grammar extends to
   editorial influence: which policy line shaped which decision, at which
   pin. The demo pitch derives directly from this line: same repo, same
   facts — the article with and without the policy, and the line-level
   trace of what the policy changed.

## Capabilities

- **CAP-1 — policy-informed article-type recommendation.** The intent
  question (spec-draft-article-ux CAP-1) drafts its recommendation from the
  policy surface as well as repo state — e.g. a recorded position on what
  the owner's channel should emit shapes which article type is proposed.
  Seed quoted + pinned in the question's Why; recorded in `consulted:`.
- **CAP-2 — policy-seeded angle as a first-class slot.** The claim/angle
  question (presentation slot 1, spec-draft-article-ux CAP-4) is
  policy-seeded whenever the surface yields a tension or a recorded
  editorial stance; its answer is recorded as the run's *editorial anchor*
  and carried into review as the claim intent anchor. (This formalizes
  what p1 did by accident.)
- **CAP-3 — policy-calibrated review emphasis.** The review's severity
  criteria stay fixed, but pass prompts receive the run's policy-derived
  editorial anchors (claim, channel expectations) so findings are argued
  against the owner's recorded standards, not generic taste. The policy
  consistency pass is unchanged; this affects only what the structure and
  prose reviewers weight. Influence recorded in the review `consulted:`.
- **CAP-4 — the with/without demonstration artifact.** A run can emit a
  short *policy-influence report* from existing run state (journal +
  presented payloads + consulted lines): which decisions were
  policy-directed, which seeds drove them, what the generic-mode
  counterfactual would have been (the suppressed/unseeded defaults). No
  second draft is generated — the report is a view over recorded
  influence, not an A/B run. This is the Tsurezure demo deliverable.
- **CAP-5 — channel strategy (deferred).** Policy-informed platform/variant
  strategy (which platforms, what each carries — e.g. recorded positions on
  content channels) is in scope for the redefinition but deferred until
  CAP-1–4 prove out; noted so it is not re-proposed from scratch.
- **CAP-6 — recommended defaults for editorial-judgment gaps
  (recall-then-ratify, fail-closed; added 2026-07-18 per #312).** Before the
  Stage-2 interview, a confirmed NEEDS-OWNER gap of an *editorial-judgment*
  class — `opinion`, `significance`, `surprise`, `tradeoff`, `warning`,
  `audience` — may be presented as a **proposed default** recalled from the
  policy surface, which the owner explicitly approves, modifies, replaces, or
  skips, instead of as a bare open question. This is invariant 1
  (propose-ratify) applied to the *shape* of an editorial-judgment answer, not
  a new influence class: it reduces per-question effort, never the question
  count, and is no substitute for #302's reserved-slot guarantee (the interview
  cap fills on count, not time). It is bounded and fail-closed:
  - **Eligible classes are editorial judgments only.** Factual, numerical,
    repository-state, and verification gaps — including NEEDS-OWNER re-raises
    and confirm/deny of repository claims — are ineligible; a default on an
    ineligible class is a **named validator rejection** (same posture as the
    Story-14.3 pre-filled-answer / confirmation-shaped-seed classes). A
    policy-seeded *tension* question is ineligible and never carries a default
    (SPEC-policy-source-seam CAP-2 — owner-only by nature).
  - **A default is never an answer and never evidence** (invariant 2). The item's
    `owner_answer` stays structurally empty at generation; a ratified default is
    recorded as interview-sourced owner judgment (the modified/replaced
    provenance class), never the pointer-inheriting `approved` class. Policy
    pointers appear only in `seed<-`/`consulted:` audit records (invariant 3)
    and never become SOURCE pointers; a factual claim grounded only in a policy
    line still fails the provenance gate or remains `[VERIFY]`.
  - **The owner ratifies every default; nothing is silently adopted.** A
    rejected or skipped default leaves its gap an unresolved NEEDS-OWNER item,
    exactly as if none had been offered. **Every presented default counts toward
    the existing ≤5 interview cap** — no pre-interview side batch relocates gap
    decisions outside the ratified owner-attention bound.
  - **A default may be recalled only under the whole-consulted-surface authoring
    rule (#299) and staleness protection (#306):** a seed predating the material
    it addresses routes to staleness/reversal handling, never a confident
    default. Consultation uses the existing pinned, bounded, read-only policy
    reader (`read-policy-source.py`, ≤2 draft-time-selected topics, code-enforced
    allowlist, recorded pin) — no new reader or access path.
  - **Amended 2026-07-19 (triage, #423):** the recalled default generalizes to
    **1–3 candidate defaults ordered by recontextualizing power** (the one that
    most reframes the others first), each recalled with its pinned rationale; the
    owner ratifies **exactly one** (approve/modify/replace/skip). The candidates
    are presented as the **single** interview item (they count once against the
    ≤5 cap — never a per-candidate batch); `owner_answer` stays empty at
    generation, a policy pointer never becomes a SOURCE, and machine-*finality*
    is declined (SPEC-policy-source-seam Non-goals). Invariants 1–3, class
    eligibility, and the whole-surface/staleness authoring rules are unchanged; a
    single candidate is the prior behavior.

## Constraints

- The three invariants above are hard lines; a capability that cannot
  satisfy all three (propose-ratify, no-facts, audited) is out of scope.
- Generic mode (no `policy_source`) must remain fully functional and
  silent — the demo's control arm is the product's degraded mode, so its
  quality is part of the demo.
- Declines are data: a rejected policy-directed proposal is recorded (like
  the interview's recorded decline), because "owner overrides policy" is
  itself the recall surface's raw material (staging-candidate path
  unchanged, proposal-only).
- No writes under `policy_source.path`, ever (seam invariant).

## Resolved questions (ratified 2026-07-15 with the direction)

1. The policy-influence report (CAP-4) ships **on request only** —
   trust-is-the-asset; an unread per-run report trains ignoring.
2. CAP-3's anchors do **not** flow to the cold read — the cold read's value
   is context-free isolation (the control arm); informing it destroys it.
