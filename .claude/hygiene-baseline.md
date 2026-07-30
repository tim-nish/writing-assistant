# Hygiene baseline — /hygiene-sweep

First sweep: 2026-07-27, repo @ 9792819. Second sweep same day, repo @ 4ddf48f.
Consulted the served policy surface each sweep; pins and cite sets are recorded
machine-locally per the publication boundary:
`owner decision record — 2026-07-27 (hygiene-sweep baseline consult)`
`owner decision record — 2026-07-27 (hygiene-sweep second consult)`
(resolve with `python3 scripts/provenance-pin.py resolve`).

## Findings ledger

| Sweep | Finding | Disposition |
|---|---|---|
| 2026-07-27 | F1 grandfathered review-article/SKILL.md regrowing (904→930 warn-only) | filed #818 — remediated (story 20.13, dispatcher split) |
| 2026-07-27 | F3 line-budget family blind to byte-dense files (pipeline spec 88KB/144 ln) | filed #819 — remediated (story 20.15, spec byte axis) |
| 2026-07-27 | F2 companion stage files uncapped (stage0 731 ln > 600 ceiling) | filed #820 — remediated (story 20.14, companion budget + ratchets) |
| 2026-07-27 (2nd) | F4 spec-terrain at 92% of its 72,000-byte hard ceiling under active growth (+1,951 B/day) | filed #829 |

| 2026-07-30 (3rd) | F5 class 4: full tier has no declared runtime ceiling (247.8s/122 checks timed; 322.5s complete @569fdca) | filed #961 |
| 2026-07-30 (3rd) | F6 class 1: spec-writing-assistant/SPEC.md 70,515 B = 97.9% of SPEC_HARD_BYTES=72000, +103.8% in 3 days | filed #960 |
| 2026-07-30 (3rd) | F7 class 1+3: skills/terrain/SKILL.md 457 ln (+66.8%), in warn band, largest single load entry at 6.3k tok | filed #962 |
| 2026-07-30 (3rd) | F8 class 2: 322-char "Canonical contract" paragraph verbatim in 5 SPEC files, no check enforces identity | rejected — convention by design; re-triggers only if it drifts, since sizes are re-baselined below |
| 2026-07-30 (3rd) | F9 class 4 (guard defect, not this repo): class-4 guard attributed a concurrent writer's change to check-stale-variant.sh, aborting the pass with 25 checks untimed | filed claude-toolkit#166 — out of target-repo scope, recorded here so it is not re-found |
| 2026-07-30 (3rd) | F10 class 1: CLAUDE.md 114 ln/6,199 B (+23%) and CAPABILITIES.md 94 ln/6,841 B (+23%), no declared cap | rejected at this size — fresh sizes recorded below, so future >20% growth re-triggers against the NEW baseline, not the 2026-07-27 one |
| 2026-07-30 (3rd) | suppressed as dedupe against ratified state: check-suite count 147 vs declared CHECK_SUITE_BASELINE=138 (the repo's own check warns; slope IS the instrument) | not a finding |
| 2026-07-30 (3rd) | suppressed as dedupe against ratified state: unscoped inner total 36.6s > INNER_TOTAL_MS=15000 (unscoped runs are ratified to fail; the per-edit run is scoped) | not a finding |

## Measurements — 2026-07-27 (2nd), repo @ 4ddf48f

Tracked files: 296. Approx tokens = bytes/4.

| File / read-set | Lines | Bytes | ~Tokens |
|---|---|---|---|
| CLAUDE.md | 94 | 5,039 | 1.3k |
| README.md | 281 | 14,186 | 3.5k |
| CAPABILITIES.md | 74 | 5,562 | 1.4k |
| skills/review-article/SKILL.md | 104 | 6,261 | 1.6k (was 930 ln / 12.7k) |
| skills/review-article/phases/entry.md | 192 | 9,311 | 2.3k (new) |
| skills/review-article/phases/passes.md | 402 | 22,388 | 5.6k (new; warn band) |
| skills/review-article/phases/arbitration.md | 136 | 7,735 | 1.9k (new) |
| skills/review-article/phases/reentry.md | 198 | 11,226 | 2.8k (new) |
| skills/harvest/SKILL.md | 546 | 31,543 | 7.9k (warn band, unchanged) |
| skills/draft-article/SKILL.md | 179 | 11,301 | 2.8k |
| skills/draft-article/stages/stage0.md | 731 | 43,093 | 10.8k (ratcheted ≤738) |
| skills/draft-article/stages/stage1.md | 105 | 6,028 | 1.5k |
| skills/draft-article/stages/stage2.md | 705 | 41,978 | 10.5k (ratcheted ≤712) |
| skills/draft-article/stages/stage3.md | 603 | 34,743 | 8.7k (ratcheted ≤609) |
| skills/draft-article/stages/stage4.md | 62 | 2,811 | 0.7k |
| skills/draft-article/stages/gate.md | 218 | 12,420 | 3.1k |
| skills/draft-article/stages/complete.md | 238 | 15,029 | 3.8k |
| skills/adapt-canonical/SKILL.md | 298 | 14,402 | 3.6k |
| skills/terrain/SKILL.md | 286 | 14,995 | 3.7k |
| skills/emit-variants/SKILL.md | 248 | 12,702 | 3.2k |
| skills/fork-gate-consult-first/SKILL.md | 221 | 11,990 | 3.0k |
| skills/setup/SKILL.md | 179 | 9,227 | 2.3k |
| skills/policy-divergence-detector/SKILL.md | 106 | 5,495 | 1.4k |
| specs/spec-article-draft-pipeline/SPEC.md | 144 | 88,474 | 22.1k (ratcheted ≤89,358 B) |
| specs/spec-terrain/SPEC.md | 972 | 66,349 | 16.6k (+1,951 B; 92% of 72,000 ceiling — filed #829) |
| specs/spec-platform-variants/SPEC.md | 506 | 34,510 | 8.6k |
| specs/spec-canonical-adaptation/SPEC.md | 249 | 31,098 | 7.8k |
| specs/spec-writing-assistant/SPEC.md | 101 | 32,814 | 8.2k (+2,209 B, +7%) |
| specs/spec-policy-source-seam/SPEC.md | 88 | 24,469 | 6.1k |
| scripts/draft-pipeline.py | 7,302 | 380,277 | 95.1k (ratcheted 7,297+1%) |
| scripts/ check-*.sh family (131 files) | 23,775 | 1,215,609 | — (test surface, not context load; +392 ln) |
| docs/dogfood-findings.md | 521 | 29,744 | 7.4k (cold; not on a skill read-set) |

Read-set notes: review-article now loads a 104-line dispatcher + one phase file
per phase — largest single load entry ≈ 3.9k tok (was 12.7k whole-skill). All
declared budgets (skill lines, companion lines, spec bytes, script lines) pass;
warn-band items are mechanically watched by scripts/check-skill-budget.sh.

Measured clean 2026-07-27 (2nd): no verbatim ≥120-char duplication across
dispatcher/phases/specs; no file grew >20% since baseline; no read-set exceeds
a declared budget; no generated/vendored artifacts.

## Measurements — 2026-07-30 (3rd), repo @ 0f98952

Tracked files: 328. Approx tokens = bytes/4.
**Tree note:** an unrelated session held two uncommitted spec edits during this sweep
(`spec-writing-assistant`, `spec-article-draft-pipeline`); sizes below include them,
and nothing in the working tree was touched by this sweep.

| File / read-set | Lines | Bytes | ~Tokens |
|---|---|---|---|
| CLAUDE.md | 114 | 6,199 | 1.5k |
| README.md | 281 | 14,186 | 3.5k |
| CAPABILITIES.md | 94 | 6,841 | 1.7k |
| skills/review-article/SKILL.md | 104 | 6,261 | 1.6k |
| skills/harvest/SKILL.md | 558 | 32,317 | 8.1k |
| skills/draft-article/SKILL.md | 181 | 11,436 | 2.9k |
| skills/draft-article/stages/stage0.md | 731 | 43,093 | 10.8k |
| skills/draft-article/stages/stage2.md | 705 | 41,978 | 10.5k |
| skills/draft-article/stages/stage3.md | 609 | 35,172 | 8.8k |
| skills/terrain/SKILL.md | 457 | 25,014 | 6.3k |
| skills/adapt-canonical/SKILL.md | 298 | 14,402 | 3.6k |
| skills/emit-variants/SKILL.md | 248 | 12,702 | 3.2k |
| specs/spec-article-draft-pipeline/SPEC.md | 100 | 45,468 | 11.4k |
| specs/spec-terrain/SPEC.md | 864 | 59,560 | 14.9k |
| specs/spec-writing-assistant/SPEC.md | 118 | 70,515 | 17.6k |
| specs/spec-platform-variants/SPEC.md | 506 | 34,510 | 8.6k |
| scripts/draft-pipeline.py | 5,386 | 280,345 | 70.1k |
| docs/dogfood-findings.md | 521 | 29,744 | 7.4k |

### Runtime rows — FIRST class-4 baseline for this repo (no delta available)

Timed one check at a time under the class-4 execution guard: hard 60s timeout,
`git status` compared between each. **Pass incomplete:** 122 of 147 checks timed
(74 inner = 36.6s, 48 full-only = 211.1s;
total 247.8s), then the guard stopped on F9's false attribution.
Reference figure for the complete tier, measured earlier the same day at `569fdca`: **322.5s / 145 checks**.

| Check | Tier | Seconds | Status |
|---|---|---|---|
| scripts/check-cross-language-offer.sh | full | 21.84 | ok |
| scripts/check-checkpoint-resume.sh | full | 10.42 | ok |
| scripts/check-stage0-fold.sh | full | 9.37 | ok |
| scripts/check-footprint-invariant.sh | full | 9.29 | ok |
| scripts/check-ja-emission.sh | full | 8.98 | ok |
| scripts/check-config-validation.sh | full | 7.71 | ok |
| scripts/check-complete-gate.sh | full | 7.59 | ok |
| scripts/check-interview-journal.sh | full | 6.78 | ok |
| scripts/check-harvest.sh | full | 6.45 | ok |
| scripts/check-derived-canonical.sh | full | 5.68 | ok |
| scripts/check-quality-gate.sh | full | 5.62 | ok |
| scripts/check-adaptation-staleness.sh | full | 5.29 | ok |
| scripts/check-stage5-variants.sh | full | 5.21 | ok |
| scripts/check-policy-reader.sh | full | 4.80 | ok |

**Untimed (25), reported rather than omitted:** check-story-element-selection.sh, check-subcommand-carriers.sh, check-substituted-served-path.sh, check-substrate-purity.sh, check-terrain-code-inner.sh, check-terrain-compose-inner.sh, check-terrain-consultant-inner.sh, check-terrain-decisions.sh, check-terrain-member.sh, check-terrain-select-brief-inner.sh, check-terrain-select-index-inner.sh, check-terrain-select-set-inner.sh, check-terrain-split.sh, check-terrain-view-inner.sh, check-topic-map-depth.sh, check-topic-map-screen.sh, check-topic-map.sh, check-unmapped-intent.sh, check-user-config-example.sh, check-verify-provenance.sh, check-visual-fallback-ladder.sh, check-visual-proposals.sh, check-visual-set-plan.sh, check-write-before-read.sh, check-writing-sources.sh.

Declared runtime bounds at this sweep: `INNER_MS=2000` (max timed inner 1.79s — no
violation), `INNER_TOTAL_MS=15000` (unscoped inner runs; ratified to fail, per-edit
runs are scoped), full tier **undeclared** — filed #961.
