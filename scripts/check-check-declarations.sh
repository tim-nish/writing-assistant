#!/usr/bin/env sh
# parallel-safe
# tier: inner — a header scan over scripts/check-*.sh, no execution
# removal-signal: the #910 retrospective classification pass runs (its reopen
#   trigger is recorded in specs/spec-writing-assistant/SPEC.md — a climbing
#   slope under the forward binding, or a check provably subsumed by the
#   #857/#858 seam and untouched for two months), after which every check
#   carries a classification and this new-file-only gate is redundant; or the
#   check suite stops being a budgeted family in that SPEC. Removed with
#   whichever lands first.
# check-check-declarations.sh — every NEW check declares its runtime tier and
# its removal signal in its header (Story 20.48, #922; spec amendment
# #910/#913 in specs/spec-writing-assistant/SPEC.md).
#
# Binds NEW checks only: the checks present at adoption (2026-07-30) are
# baselined below and are classified when touched, per the amendment's
# declined-retrospective-sweep decision — they never fail here. A check file
# not in the baseline must carry, near the top:
#
#   # tier: inner|full — <why this tier>
#   # removal-signal: <a condition someone could OBSERVE firing>
#
# The removal signal follows the ratified shape: concrete, observable
# conditions recorded at adoption — a bare expiry date alone does not satisfy
# it (a date is when to look, not what to look for).
#
# POSIX sh; runs in milliseconds (inner tier).

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

# The check suite at adoption (2026-07-30, Story 20.48) — 137 files. These are
# exempt (classified when touched); everything newer must declare. Do NOT add
# new checks here: a new check declares its headers instead.
BASELINE="
check-adaptation-staleness.sh
check-arbitration-events.sh
check-article-join-view.sh
check-article-plan.sh
check-brief-informed-structures.sh
check-canonical-adaptation.sh
check-capabilities-manifest.sh
check-checkpoint-resume.sh
check-complete-gate.sh
check-completion-summary.sh
check-config-defect-routing.sh
check-config-resolution.sh
check-config-validation.sh
check-consumption-exclusion.sh
check-consumption-population.sh
check-contract-draft-pipeline.sh
check-contract-review-arbitration.sh
check-coverage-brief.sh
check-cross-language-offer.sh
check-delivered-basename.sh
check-denial-list-growth.sh
check-derived-canonical.sh
check-dev-harness.sh
check-differential-context.sh
check-draft-scaffold.sh
check-emission-review-evidence.sh
check-episode-candidates.sh
check-evidence-types.sh
check-fact-sheet.sh
check-footprint-invariant.sh
check-fork-consult.sh
check-framework-f1.sh
check-framework-f2.sh
check-framework-f3.sh
check-framework-f4.sh
check-framework-f5.sh
check-framework-visual-slots.sh
check-frameworks.sh
check-gate-comparison.sh
check-gateway-only.sh
check-generic-engine.sh
check-harvest-scope.sh
check-harvest.sh
check-internal-vocabulary.sh
check-interview-items.sh
check-interview-journal.sh
check-ja-emission.sh
check-lint-article.sh
check-marketplace.sh
check-missing-input-cap.sh
check-named-element-pin.sh
check-narrative-structure.sh
check-needs-owner.sh
check-one-entry-mechanism.sh
check-one-structure-gate.sh
check-owner-term-codebook.sh
check-path-resolver.sh
check-per-run-workspace.sh
check-plan-boundary.sh
check-plan-conformance.sh
check-platform-lint.sh
check-platform-profiles.sh
check-platform-variant-visuals.sh
check-plugin-manifest.sh
check-policy-arbitration.sh
check-policy-block.sh
check-policy-classification.sh
check-policy-divergence-detector.sh
check-policy-divergence-runtime.sh
check-policy-influence-report.sh
check-policy-reader.sh
check-policy-source-config.sh
check-proposal-contract.sh
check-proposal-payload.sh
check-provenance-map.sh
check-provenance-pin.sh
check-publication-boundary.sh
check-quality-gate-delta.sh
check-quality-gate.sh
check-quality-rubric.sh
check-reading-time-depth.sh
check-readme.sh
check-recommended-default-provenance.sh
check-release-strip.sh
check-relocated-artifact-boundary.sh
check-repair-hop.sh
check-repo-onboarding.sh
check-retired-vocabulary.sh
check-review-arbitration.sh
check-review-coldread.sh
check-review-consulted.sh
check-review-declared-register.sh
check-review-diff.sh
check-review-findings-class.sh
check-review-policy-pass.sh
check-review-prose.sh
check-review-reentry.sh
check-review-skill.sh
check-review-starter.sh
check-review-structural.sh
check-rubric-dim-separation.sh
check-rubric-mapped-gate.sh
check-seeded-profile-drift.sh
check-severity-rationale.sh
check-site-record.sh
check-skeleton.sh
check-skill-budget.sh
check-slot-skip-semantics.sh
check-sourced-visuals.sh
check-stage0-fold.sh
check-stage1-consume.sh
check-stage2-interview.sh
check-stage2-policy-seam.sh
check-stage2-recommended.sh
check-stage2-triage.sh
check-stage3-fill.sh
check-stage4-verify.sh
check-stage5-variants.sh
check-staging-candidates.sh
check-stale-variant.sh
check-story-element-selection.sh
check-subcommand-carriers.sh
check-substituted-served-path.sh
check-substrate-purity.sh
check-terrain-decisions.sh
check-terrain-member.sh
check-topic-map-depth.sh
check-topic-map-screen.sh
check-topic-map.sh
check-unmapped-intent.sh
check-user-config-example.sh
check-verify-provenance.sh
check-visual-fallback-ladder.sh
check-visual-proposals.sh
check-visual-set-plan.sh
check-write-before-read.sh
check-writing-sources.sh
"

new=0
for f in scripts/check-*.sh; do
  [ -e "$f" ] || continue
  base=${f#scripts/}
  if printf '%s\n' "$BASELINE" | grep -qx "$base"; then continue; fi
  new=$((new + 1))
  head -25 "$f" | grep -Eq '^# tier: (inner|full)' \
    || err "$f is a new check with no '# tier: inner|full' header — declare its runtime tier (Story 20.48, #922)"
  sig=$(head -25 "$f" | sed -n 's/^# removal-signal:[[:space:]]*//p' | head -1)
  if [ -z "$sig" ]; then
    err "$f is a new check with no '# removal-signal:' header — record, at adoption, the observable condition that retires it (Story 20.48, #922)"
  else
    # A bare date is not a removal signal (AC5): strip date tokens and require
    # observable words to remain.
    residue=$(printf '%s' "$sig" | sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2}//g; s/[^A-Za-z]+/ /g')
    words=$(printf '%s\n' "$residue" | wc -w | tr -d ' ')
    [ "$words" -ge 3 ] \
      || err "$f declares a removal signal that is a bare date ('$sig') — name a condition someone could observe (Story 20.48 AC5)"
  fi
done

[ "$new" -gt 0 ] && ok "$new post-adoption check(s) scanned for tier + removal-signal declarations" \
  || ok "no post-adoption checks yet — baseline unchanged, nothing to enforce"

if [ "$fail" -eq 0 ]; then
  printf '\nAll check-declaration checks passed.\n'; exit 0
else
  printf '\ncheck-declaration checks FAILED.\n' >&2; exit 1
fi
