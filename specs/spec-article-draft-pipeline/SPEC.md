---
id: SPEC-article-draft-pipeline
companions:
  - pipeline-stages.md
  - ../spec-article-frameworks/article-frameworks.md
sources:
  - ../../../website/q_a/2/question.md  # external: website repo (sibling checkout), traceability only
  - ../../../website/q_a/2/answer.md    # external: website repo (sibling checkout), traceability only
  - ../../q_a/a1.md                     # dogfooding Q&A round 1, traceability only
  - ../../docs/dogfood-findings.md      # dogfood evidence behind the 2026-07-10 amendments
  - ../../docs/harness-architecture.md  # 2026-07-11 article-quality harness decision (D1–D5) behind the 2026-07-11 amendments
---

> **Vendored copy.** Adopted verbatim from the website repo (`website/_bmad-output/specs/spec-article-draft-pipeline/`, 2026-07-09) per SPEC-writing-assistant; this copy is now the canonical version for this project. Repo-internal references (`q_a/…`, AP/AC numbers) refer to the website repo.
> **Amended 2026-07-10** per accepted dogfood findings (`docs/dogfood-findings.md`, `q_a/a1.md`): CAP-5 (up-front config validation) and CAP-6 (completion-summary contract) added; interview/verification constraints now reference SPEC-writing-assistant's owner-facing proposal contract.
> **Amended 2026-07-11** per the article-quality harness decision (`docs/harness-architecture.md`, D1–D5): CAP-3 reworked to three provenance classes with a sidecar provenance map; CAP-7 (mandatory stage 3→4 quality gate) added; the no-invented-evidence and rewrite constraints updated accordingly.

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate. Source documents listed in frontmatter are for traceability only — consult them only if you need narrative rationale or prose color this contract intentionally omits.

# Article Draft Pipeline

## Why

A pain to solve plus an opportunity to capture: the owner wants a publishable technical-article draft in ~10 minutes of personal attention, from raw material already in git (dev logs, specs, READMEs, commit history, BMAD memlogs). The owner's initial workflow idea — human extracts key points, AI reconstructs narrative — spends scarce human minutes on the step AI does better (extraction) and delegates the step that most needs human control (claims and voice). This pipeline inverts that: AI harvests with source pointers, the human contributes judgment through a bounded interview and a verification pass. Distribution, not artifact quality, is the current bottleneck (q_a/1); this pipeline is the throughput fix.

## Capabilities

- **CAP-1**
  - **intent:** From named sources, the pipeline builds a fact sheet of candidate claims, results, and numbers where every entry carries a source pointer (file/line, commit, or URL).
  - **success:** Auditing any fact-sheet entry leads to the exact source location; entries without a source do not appear.
- **CAP-2**
  - **intent:** The pipeline interviews the owner with at most 5 targeted questions covering only what sources cannot answer — surprise, significance, opinion, warnings — accepting bullet answers.
  - **success:** A run on a real project completes the interview in ≤5 questions and ≤5 minutes, and no question duplicates information already in the fact sheet.
- **CAP-3** (amended 2026-07-11 per `docs/harness-architecture.md` D1–D2)
  - **intent:** The pipeline fills the chosen framework (from SPEC-article-frameworks) to produce a draft with schema-conformant frontmatter, classifying every sentence into one of three provenance classes recorded in a sidecar provenance map: a **sourced claim** carries a fact-sheet or interview pointer; a **derived claim** compresses, combines, or restates ≥2 named sourced claims and inherits their pointers — introducing new causality, significance, evaluation, comparison, intent, or scope makes it inferred; **narration** asserts nothing checkable (falsifiability test) and needs no pointer. Inferred claims — asserting more than sources, interview, or derivation support — carry inline `[VERIFY]` markers as before.
  - **success:** For a produced draft, every claim-classed sentence traces to a source pointer, an interview answer, inherited pointers, or a `[VERIFY]` marker; an independent `verify-provenance` check finds no narration-classed sentence asserting a checkable proposition and no derived claim exceeding its inputs; frontmatter passes build validation (AC-4).
- **CAP-4**
  - **intent:** The pipeline emits platform-ready variants: a dev.to copy (full text, `canonical_url` placeholder) and/or a Zenn repo-sync copy (Zenn frontmatter), per the article's language and canonical policy (AP-6).
  - **success:** Each variant is publishable on its platform without manual reformatting beyond filling the canonical URL.
- **CAP-5** (added 2026-07-10)
  - **intent:** Before any generation or review work, the pipeline validates the resolved configuration (`user-config.yaml`, `writing-sources.yaml`): unresolved placeholder values (example-file defaults such as the pointer-block site name), malformed URLs (e.g. double slashes in `canonical_url` composition), and missing required keys are reported as configuration errors up front — publishing configuration is a precondition, never an article-quality finding discovered at the end of the pipeline.
  - **success:** Running the pipeline against a config still carrying an example placeholder or a malformed URL halts at stage 0 with a per-key report naming the file and fix; a clean config produces no configuration findings anywhere later in the run.
- **CAP-6** (added 2026-07-10)
  - **intent:** Every run — including standalone harvest — ends with a completion summary partitioned into exactly three labeled buckets (**informational notes**, **publish blockers** — e.g. unresolved `[VERIFY]` markers, unrendered figures, a quality-gate failure surviving its revision cycles (CAP-7), **optional cleanup**) followed by an explicit next-step suggestion (e.g. run review, or for a standalone harvest: review the fact sheet or run draft-article). No run ends by only reporting results. The **reading-time estimate** (words ÷ ~200 wpm EN, characters ÷ ~500 cpm JA) is an informational-bucket item **only for runs that produce or review an article body**; standalone harvest has no article body to measure and omits it.
  - **success:** A run with a known blocker lists it under publish blockers and nowhere else; every run's summary — harvest included — contains the three bucket headings and a concrete next step; an article-producing or article-review run additionally shows a reading-time estimate, while a standalone harvest run shows none.
- **CAP-7** (added 2026-07-11 per `docs/harness-architecture.md` D3–D5)
  - **intent:** A mandatory article-quality gate sits between stage 3 and stage 4 — a stage-progression precondition like the `[VERIFY]` exit criterion, never an advisory finding. The draft must pass a fixed four-dimension rubric (narrative arc, paragraph flow, explanation calibration, readability mechanics; the rubric is a versioned plugin asset), judged by zero-token mechanical checks (dimension 4) plus one single-pass cheap-tier rubric judge (dimensions 1–3) emitting pass/fail per dimension with failing locations, in findings format, no rewritten text. On failure, stage 3 revises against the named failing dimensions and re-runs **both** the quality gate and `verify-provenance` — at most two revision cycles; a failure surviving them surfaces as a publish blocker (CAP-6) naming the failing dimensions and locations, never silently retried or waived.
  - **success:** A fact-sheet-stitched draft (wall-to-wall sourced claims with no derived/narration tissue) fails the gate and never reaches stage 4 unrevised; a gate failure after two revision cycles appears in the completion summary's publish-blocker bucket with dimensions and locations; a passing draft enters stage 4 having consumed zero minutes of the owner's attention budget on quality retries.

## Constraints

- Human attention budget ≤10 minutes per article (interview + verification passes); wall-clock time is unconstrained.
- No invented evidence (amended 2026-07-11): sourced claims carry pointers; derived claims may compress, combine, or restate named fact-sheet inputs — inheriting their pointers — but must not introduce new causality, significance, evaluation, comparison, intent, or scope; narration asserts nothing checkable (falsifiability test: no reviewer with source access could mark it false); every other assertion carries `[VERIFY]`. The pipeline never silently asserts, and the drafting agent never grades its own claim/narration boundary — `verify-provenance` runs independent of the drafting context.
- A section needing more than one rewrite routes back to a new interview question, never into open-ended editing; quality-gate revisions (CAP-7) are likewise bounded — two cycles, then a publish blocker, never open-ended iteration.
- Interview questions (CAP-2) and owner-verification items obey SPEC-writing-assistant's **owner-facing proposal contract**: each shows where the item lands in the article (outline context + short section preview), why it is asked, and choices stating their concrete effect on the article — the owner answers from repository knowledge alone, never by inferring the generation logic.
- Consumes the framework templates from SPEC-article-frameworks verbatim; category structure is not redesigned per run.
- Implemented as a Claude Code skill (`.claude/skills/`) so harvest can read the repo directly.

## Non-goals

- No publishing: the pipeline never calls dev.to/Zenn APIs or pushes to a Zenn-synced repo; the owner publishes.
- No review: quality passes are SPEC-article-review's contract.
- No image *rendering* or hosting; evidence figures and rendered images are produced by the owner's tooling. *(Narrowed 2026-07-10 by SPEC-article-visuals: proposing visual **source** — Mermaid, figure specs, image-generation prompts — is that spec's contract and in scope for the pipeline; rendering remains out.)*
- No topic selection: the owner chooses what to write; the pipeline does not maintain an idea backlog.

## Success signal

The owner takes a real project (e.g. a QuantScenarioBench release) from "invoke pipeline" to a draft they would hand to review in ≤10 minutes of their own attention, and spot-checking the draft finds zero unmarked invented claims.

## Assumptions

- Drafting runs on the strongest model available to the owner (q_a/2 answer §4.1: draft quality determines the number of downstream review cycles).

## Open Questions

- Should the pipeline also create the site's `mode: external` article record for JA/Zenn pieces, or does that stay a manual follow-up?
