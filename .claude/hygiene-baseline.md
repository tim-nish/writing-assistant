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
