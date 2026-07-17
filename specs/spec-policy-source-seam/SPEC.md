---
id: SPEC-policy-source-seam
companions:
  - seam-formats.md
  - ../spec-article-draft-pipeline/SPEC.md            # adopted: CAP-2 triage contract this seam feeds
  - ../spec-article-draft-pipeline/pipeline-stages.md # adopted: Stage-2 question bank + interview journal
sources:
  # Authoritative external contract — owner decision record 2026-07-14 (writing-assistant seam),
  # held in the owner's private policy hub, retrievable by date + title (read-only).
---

> **Adopted 2026-07-14.** Promoted from `_bmad-output/specs/spec-policy-source-seam/` (BMAD-generated, owner-approved 2026-07-14, implemented as Epic 14, issues #178–#182) per the canonical-spec promotion convention (#188); **this copy is now the canonical version**. The BMAD memlog stays with the generating workspace — it is process state, not contract.
> **Amended 2026-07-14 (dogfood)** per the papers-repo seeded run: `answer --batch` records carry owner text as `answer` (emitter fix #191/#192); no contract change — record shape is implementation detail.
> **Amended 2026-07-15 (triage, #230)** per SPEC-policy-topic-at-draft: the first assumption below ("one host repo maps to one backlog track…") is **superseded** — dogfood round 2 falsified it (different articles from one repo need different topic slices). Topic selection moves to draft time under the proposal contract; `track`/`topics` config keys are demoted to per-run default recommendations and then removed. The seam's read-time contracts (≤2 cap, code-enforced whitelist, CAP-6 degradation, GLOSSARY+LESSONS-only fallback) are unchanged.

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate. Source documents listed in frontmatter are for traceability only — consult them only if you need narrative rationale or prose color this contract intentionally omits.

# Policy-Source Interview Seam (A1)

## Why

An opportunity to capture, ratified 2026-07-14: the owner keeps an authoritative policy hub (glossary, lessons, topic positions) in a separate private repository, and the Stage-2 gap interview currently asks generic questions blind to those positions. The hardest interview input is the *right question*; reading the recall surface lets the tool generate questions specific to the owner's recorded positions — surfacing tension (contradictions, reversals, missing rationale), never confirmation. The seam is a local read-only pointer: writing-assistant reads a bounded slice of that policy hub, the owner decides everything, and contribution back is proposal-only. Build order is ratified: this input side ships first; the review-side consistency pass (A2) later reuses the same plumbing.

## Capabilities

- **CAP-1** — `policy_source` config key
  - **intent:** A host repo may declare an optional `policy_source` block in `writing-sources.yaml`: a local filesystem `path` to the policy-hub checkout, ~~an optional `track` … and an optional explicit `topics:` list~~ *(the `track`/`topics` config keys were removed — superseded by per-article topic selection at draft time, SPEC-policy-topic-at-draft CAP-2/CAP-3, Story 13.36; a leftover key is a named configuration error)*. No URL scheme, no sync protocol — the pointer is the integration.
  - **success:** A repo with the block gets policy-seeded interviews; a repo without it behaves exactly as today; `validate-config` reports a malformed block (non-string path, or a leftover legacy `track`/`topics` key) as a stage-0 configuration error naming the key and fix.
- **CAP-2** — bounded, pinned, read-only policy reader
  - **intent:** A reader script resolves and reads **only** `GLOSSARY.md`, `LESSONS.md`, and ≤2 `topics/*.md` files ~~matched from the track (or the explicit `topics:` list, same cap)~~ *(selected per article at draft time — SPEC-policy-topic-at-draft CAP-2; same ≤2 cap, code-enforced)* under `policy_source.path`, and records the pin `<policy-source>@<commit>` (the resolved path's basename + `git rev-parse HEAD` at that path). The whitelist is enforced in code — the function takes the allowlist; the hub's history archive and every other path are structurally unreadable; the reader never writes outside the host run workspace.
  - **success:** Asking the reader for any path outside the whitelist (including any history-archive path) is refused by code regardless of prompt; every emitted policy quote carries `file:line@commit` (harvest pointer convention); the run artifact records the pin; no file under `policy_source.path` is ever created or modified.
- **CAP-3** — schema-enforced, question-shaped interview items
  - **intent:** Every Stage-2 candidate question is emitted as an interview item `{id, gap_type, seed: {quote, pointer, companion?} | null, question, owner_answer: ""}` (companion `seam-formats.md`). `gap_type` extends the NEEDS-OWNER taxonomy with four tension types — `contradiction`, `ambiguity`, `missing-rationale`, `reversal-candidate` — the only types a policy seed may generate. A validator rejects: a pre-filled `owner_answer`, a tension-typed item without a seed, a seed without a pinned pointer, and a seeded question that merely restates its seed (confirmation is not a gap type).
  - **success:** Each rejection class has a seeded test fixture that the validator fails; a valid item set passes; validation runs before triage so a bad item can never reach the owner.
  - **staleness routing** (added 2026-07-17, #306): a seed that **predates the material it appears to contradict** — decided from inputs the run already holds (the surface's `updated:`/`state:` lines and the run's pin; no new metadata is required of the hub) — is a *stale recorded position*, not a live conflict. Such an item is routed to `gap_type: reversal-candidate` and asks the owner to **confirm or update** the recorded position; it is never presented as a live tension to adjudicate. Its staging candidate (CAP-4) is framed as a **policy-update proposal for the stale line**, never as the resolution of a conflict — otherwise an owner answering a staleness artifact contributes a "resolution" to a dispute that never existed, and the seam's own recall surface degrades.
  - **whole-surface authoring** (added 2026-07-17, #299): a tension item is authored against the **consulted surface as a whole**, never a single quoted line. When another line in the same consulted surface already resolves the apparent conflict, the item is either **not raised** or raised **with the resolving line** carried in `seed.companion` (`{quote, pointer}`, same pinned-pointer grammar) so the owner arbitrates only the residual question. An apparent contradiction the surface itself answers is a *manufactured* tension — it spends a bounded owner-gate slot re-deciding settled ground, and an answer to it contributes a resolution to a conflict that never existed. The distinction such seeds most often miss is stated where items are authored: **harvest assembles evidence; the interview is the judgment gate** — evidence assembly is not unattended generation.
- **CAP-4** — staging-candidate emitter (proposal-only contribute-back)
  - **intent:** When an interview answer contains a durable decision or reversal, the run output appends a staging-candidate block whose schema mirrors the policy hub's staging-area frontmatter (`slug, created, source_repo, perishable, tags` + question/decision in full sentences; companion). The tool stops there — the owner copies accepted blocks into the policy hub by hand.
  - **success:** A run whose answers contain a reversal emits a schema-valid block in its run output; no run ever writes a file under `policy_source.path`.
- **CAP-5** — `consulted:` auditability line
  - **intent:** The interview run artifact ends with an `/ask`-style `consulted:` line naming which glossary entries, lessons, and topic lines seeded which questions (companion format).
  - **success:** For every policy-seeded question asked, the `consulted:` line maps its seed pointer to its question id; a generic-mode run emits `consulted: none (policy_source unavailable|unset)`.
- **CAP-6** — graceful degradation
  - **intent:** An absent `policy_source` key runs the interview in generic mode silently; a present-but-unusable one (path missing, unreadable, or not a git repo) logs one line and degrades to generic NEEDS-OWNER gap questions. The seam adds capability, never fragility.
  - **success:** Deleting or corrupting the policy checkout between runs changes the interview from seeded to generic with one logged line and zero failures; no stage aborts.

## Constraints

- Policy reading seeds candidate **questions only**, with one bounded exception (added 2026-07-18, SPEC-policy-editorial-direction CAP-6): a **recommended default for an editorial-judgment gap** — recalled and owner-ratified, `owner_answer` empty at generation, counted against the ≤5 cap. Triage (suppress/recommend/open) and recommendation generation otherwise remain a view over harvest output — the policy source never supplies or pre-fills a factual answer, and a policy line never becomes a SOURCE pointer (preserves SPEC-article-draft-pipeline CAP-2 and `docs/interview-architecture.md` D1).
- Policy-seeded questions obey the owner-facing proposal contract unchanged: selective prompts, Where/Why/Effect, journal entries; the seed quote + pointer is presented as the question's Why context, and the journal records seed pointers like recommendation groundings.
- The whitelist, the ≤2-topics cap, and read-only-ness are code-enforced (reader takes an allowlist), never prompt-enforced.
- Reader and validator are stdlib-only Python in `scripts/` (repo convention: no PyYAML, no JS/TS); each ships with a `check-*.sh` harness like every other script.
- Seed pointers use the existing `file:line@commit` harvest convention — no new pointer format.
- The policy-hub checkout is never modified, and nothing from its history archive (including its staging area) is ever read.

## Non-goals

- A2 — the review-article policy-consistency pass (ships later as this plumbing's second consumer).
- Automated contribute-back: no writes into the policy hub, no PR automation; the manual copy is the design until it proves to be real friction.
- Sync/export pipelines, URL/remote policy sources, embeddings or semantic search over policy or history, cross-repo `/ask` or any invocation mechanism.
- Redesigning Stage-2 triage, recommendations, or the interview journal beyond the additive fields named here.

## Success signal

A draft-article run in a host repo pointing at the policy hub asks at least one tension-typed question quoting a pinned policy line the owner recognizes as their own position — and the same run with `policy_source` removed completes identically minus the seeded questions.

## Assumptions

- ~~One host repo maps to one backlog track, so `policy_source.track` is a per-repo config value rather than a per-invocation argument.~~ **Superseded** (top-of-file 2026-07-15 amendment; falsified by dogfood round 2): topic selection is per-article at draft time — SPEC-policy-topic-at-draft; the `track`/`topics` keys were removed (Story 13.36).
- ~~Track→topic matching is by filename stem under `topics/`~~ *(now the per-run topic proposal's matching, same stem convention and ≤2 cap; no mapping table is imported from the policy hub — unchanged)*.
- Absent a per-run topic selection, the reader reads GLOSSARY + LESSONS only — still a valid seeded run.

