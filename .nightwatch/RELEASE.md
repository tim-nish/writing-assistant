---
phase: hardening
target: "First release — all planned epics complete"
progress: 0.67
updated: 2026-07-10
---
# Release progress

## Status update (latest first, capped at 10 entries)
- 2026-07-10 — forced re-run: progress unchanged at 0.67 (2/3 definition-of-done met). Tonight's repo-reconcile and arch-review both returned 0 verified findings — nothing to promote, no new release blockers, no new human decisions. RC-615fba README asset-paths drift is still physically present (now `README.md:155`), but the reconcile patch last night referenced (`.nightwatch/out/reconcile-2026-07-10.patch`) is no longer on disk and reconcile (degraded — unknown ecosystem) did not re-surface it or regenerate one; clearing it now needs a manual one-line edit. Generic hygiene unchanged: no CI (RP-70609d), no CHANGELOG (RP-09c718). Arch candidates AR-244928 / AR-7c1754 recurred, still unverified/needs-corroboration, not promoted.
- 2026-07-10 — tracker instantiated (first run). 2/3 definition-of-done items met: all 6 epics / 29 stories published, and the first dogfooding cycle (harvest → draft-article → review-article) passed. Remaining: validate/settle usage docs (open README asset-paths drift RC-615fba, patch available) plus generic hygiene (no CI, no CHANGELOG). No release blockers, no human decisions.

## Phase
hardening
_Mirrors STATE.md `phase`._

## Done
<!-- completed work, each item with evidence link -->
- **[DoD] All planned epics complete** — 6 epics, 29 stories all `status: published`. Evidence: `_bmad-output/planning-artifacts/epics.md:96` (Epic List, Epics 1–6); `_bmad-output/implementation-artifacts/*.md` (all 29 stories `status: published`); git `c64dc8c` (Epic 6 merged).
- **[DoD] harvest → draft-article → review-article works end-to-end (first dogfooding cycle passed)** — all three skills present and exercised. Evidence: `skills/harvest/SKILL.md`, `skills/draft-article/SKILL.md`, `skills/review-article/SKILL.md`; `docs/dogfood-findings.md:13` (2026-07-10 review-article run completed, draft reported publishable).
- **[generic] LICENSE present** — `LICENSE:1` (release-checks `license` = pass).
- **[generic] README has Install + Usage sections** — `README.md:8` (Install), `README.md:82` (Usage) (release-checks `readme_sections` = pass). _Content accuracy still open — see DoD-3 / RC-615fba below._
- **[generic] No secrets detected** — release-checks `no_secrets` = pass (`.nightwatch/out/release-checks-2026-07-10.json`).
- **[generic] TODO/FIXME under threshold** — 0 of ≤40 (release-checks `todo_threshold` = pass).

## Remaining — implementation
- **RP-70609d — Add CI configuration.** No CI config found (`.github/workflows/` absent); release-checks `ci_present` = fail. Evidence: `.nightwatch/out/release-checks-2026-07-10.json`.

## Remaining — documentation
- **[DoD-3, in progress] Install and usage documentation validated.** README Install/Usage sections exist and were exercised by the 2026-07-10 dogfood cycle, but two accuracy gaps remain open: the README asset-paths section drifts from code convention (see RC-615fba below), and the dogfood run surfaced a config-validation friction (`docs/dogfood-findings.md`, 2026-07-10). Check off once both are settled.
- **RC-615fba (tracked, not a blocker) — README asset-paths drift.** `README.md:155` still attributes bundled `scripts/`/`frameworks/` to `${CLAUDE_SKILL_DIR}`, but every real `SKILL.md` uses `${CLAUDE_PLUGIN_ROOT}` and the repo convention (`scripts/check-dev-harness.sh:96`) assigns shared `scripts/` to `${CLAUDE_PLUGIN_ROOT}`. Derived-doc drift (severity 2). Status 2026-07-10: drift still physically present; the patch previously staged (`.nightwatch/out/reconcile-2026-07-10.patch`) is no longer on disk, and tonight's repo-reconcile (degraded — unknown ecosystem) did not re-surface it or regenerate a patch, so a manual one-line edit is now required. Clears when the README line uses `${CLAUDE_PLUGIN_ROOT}`.
- **RP-09c718 — Add CHANGELOG.** No CHANGELOG present; release-checks `changelog` = fail. Evidence: `.nightwatch/out/release-checks-2026-07-10.json`.

## Release blockers
<!-- severity-1 findings, cross-referenced by finding id; clear automatically when the source clears -->
- None. No severity-1 findings tonight.

## Human decisions needed
<!-- human-decision findings, cross-referenced by finding id -->
- None. (Arch-review candidates AR-244928 — scripts↔skills hidden-coupling — and AR-7c1754 — `.gitignore` hotspot — recurred in tonight's arch-review but remain unverified, needs-corroboration, and were not promoted; `.nightwatch/out/arch-review-2026-07-10.json`.)

## Nice to have
- Revisit arch-review candidates AR-244928 and AR-7c1754 if corroborated in a later run (`.nightwatch/out/arch-review-2026-07-10.json`).
- Note: `version_tag` release-check is skipped — no `package.json` version to compare against tags (`.nightwatch/out/release-checks-2026-07-10.json`).

## Next actions (top 3)
1. Correct the README asset-paths line manually — set `README.md:155` to use `${CLAUDE_PLUGIN_ROOT}` instead of `${CLAUDE_SKILL_DIR}` (clears RC-615fba; advances DoD-3). No staged patch remains on disk.
2. Add a CI workflow → `.github/workflows/` (release-checks `ci_present` = fail; RP-70609d).
3. Add `CHANGELOG.md` and address the config-validation friction recorded in `docs/dogfood-findings.md` before tagging (RP-09c718).

## Notes (human-owned — never machine-edited)
<!-- Anything below this heading is byte-preserved by Nightwatch. Write freely. -->
