# Hygiene baseline — /hygiene-sweep

First sweep: 2026-07-27, repo @ 9792819. Consulted the served policy surface;
the pin and cite set are recorded machine-locally per the publication boundary:
`owner decision record — 2026-07-27 (hygiene-sweep baseline consult)`
(resolve with `python3 scripts/provenance-pin.py resolve`).

## Findings ledger

| Sweep | Finding | Disposition |
|---|---|---|
| 2026-07-27 | F1 grandfathered review-article/SKILL.md regrowing (904→930 warn-only) | filed #818 |
| 2026-07-27 | F3 line-budget family blind to byte-dense files (pipeline spec 88KB/144 ln) | filed #819 |
| 2026-07-27 | F2 companion stage files uncapped (stage0 731 ln > 600 ceiling) | filed #820 |

## Measurements — 2026-07-27

Tracked files: 290. Approx tokens = bytes/4.

| File / read-set | Lines | Bytes | ~Tokens |
|---|---|---|---|
| CLAUDE.md | 94 | 5,039 | 1.3k |
| README.md | 281 | 14,186 | 3.5k |
| CAPABILITIES.md | 74 | 5,562 | 1.4k |
| skills/review-article/SKILL.md | 930 | 50,613 | 12.7k |
| skills/harvest/SKILL.md | 546 | 31,543 | 7.9k |
| skills/draft-article/SKILL.md | 179 | 11,301 | 2.8k |
| skills/draft-article/stages/stage0.md | 731 | 43,093 | 10.8k |
| skills/draft-article/stages/stage1.md | 105 | 6,028 | 1.5k |
| skills/draft-article/stages/stage2.md | 705 | 41,978 | 10.5k |
| skills/draft-article/stages/stage3.md | 603 | 34,743 | 8.7k |
| skills/draft-article/stages/stage4.md | 62 | 2,811 | 0.7k |
| skills/draft-article/stages/gate.md | 218 | 12,420 | 3.1k |
| skills/draft-article/stages/complete.md | 238 | 15,029 | 3.8k |
| skills/adapt-canonical/SKILL.md | 298 | 14,402 | 3.6k |
| skills/terrain/SKILL.md | 286 | 14,995 | 3.7k |
| skills/emit-variants/SKILL.md | 248 | 12,702 | 3.2k |
| skills/fork-gate-consult-first/SKILL.md | 221 | 11,990 | 3.0k |
| skills/setup/SKILL.md | 179 | 9,227 | 2.3k |
| skills/policy-divergence-detector/SKILL.md | 106 | 5,495 | 1.4k |
| specs/spec-article-draft-pipeline/SPEC.md | 144 | 88,474 | 22.1k |
| specs/spec-terrain/SPEC.md | 944 | 64,398 | 16.1k |
| specs/spec-platform-variants/SPEC.md | 506 | 34,510 | 8.6k |
| specs/spec-canonical-adaptation/SPEC.md | 249 | 31,098 | 7.8k |
| specs/spec-writing-assistant/SPEC.md | 99 | 30,605 | 7.7k |
| specs/spec-policy-source-seam/SPEC.md | 88 | 24,469 | 6.1k |
| scripts/draft-pipeline.py | 7,302 | 380,277 | 95.1k (ratcheted 7,297+1%) |
| scripts/ check-*.sh family (130 files) | 23,383 | 1,194,006 | — (test surface, not context load) |
| docs/dogfood-findings.md | 521 | 29,744 | 7.4k (cold; not on a skill read-set) |

Read-set notes: draft-article loads SKILL.md + one stage file per transition
(largest single load stage0 ≈ 13.6k tok with dispatcher); review-article loads
its 930-line SKILL.md whole (12.7k tok) every sitting — the outlier, filed #818.

Measured clean 2026-07-27: no verbatim spec↔skill duplication (0 shared
≥120-char lines); twin topic-map checks cover distinct CAPs; framework checks
f1–f5 distinct; no generated/vendored artifacts.
