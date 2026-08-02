#!/usr/bin/env sh
# parallel-safe
# tier: full — measured over the inner ceiling (#913); end-to-end/scenario class
# covers: config/platform-profiles/devto.example.yaml config/user-config.example.yaml scripts/resolve-paths.py scripts/resolve-writing-sources.py scripts/validate-config.py skills/draft-article/SKILL.md skills/draft-article/stages/complete.md skills/draft-article/stages/gate.md skills/draft-article/stages/stage0.md skills/draft-article/stages/stage1.md skills/draft-article/stages/stage2.md skills/draft-article/stages/stage3.md skills/draft-article/stages/stage4.md skills/review-article/SKILL.md skills/review-article/phases/arbitration.md skills/review-article/phases/entry.md skills/review-article/phases/passes.md skills/review-article/phases/reentry.md
# check-config-validation.sh — verify Stage-0 configuration validation (Story 7.4,
# CAP-5): before any generation or review, a config carrying an example
# placeholder, a malformed URL (double-slash canonical_url), or a missing required
# key halts with a per-key report naming the file and the fix; a clean config
# passes silently with no later configuration finding. Both skills wire it in as
# their stage 0. POSIX shell + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"
__DA_ALL="${TMPDIR:-/tmp}/da-skill-all.$$.md"
cat skills/draft-article/SKILL.md skills/draft-article/stages/stage0.md skills/draft-article/stages/stage1.md skills/draft-article/stages/stage2.md skills/draft-article/stages/stage3.md skills/draft-article/stages/gate.md skills/draft-article/stages/stage4.md skills/draft-article/stages/complete.md > "$__DA_ALL"


VAL="scripts/validate-config.py"
DRAFT="$__DA_ALL"
REVIEW=$(mktemp)
cat skills/review-article/SKILL.md skills/review-article/phases/entry.md \
    skills/review-article/phases/passes.md skills/review-article/phases/arbitration.md \
    skills/review-article/phases/reentry.md > "$REVIEW"
# ^ story 20.13 (#818): the skill is now a dispatcher + phase companions; checks
#   assert over the concatenation, whose order matches the pre-split file.
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$root/$VAL', doraise=True)" 2>/dev/null \
  && ok "validator compiles" || { err "validator syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
mkdir -p "$work/root"
cat > "$work/root/writing-sources.yaml" <<'YAML'
sources:
  - path: .
output:
  drafts: articles/drafts/
YAML
cat > "$work/clean.yaml" <<'YAML'
owner:
  name: "Ada Lovelace"
  site_url: "https://ada.dev"
  site_name: "ada.dev"
  focus_areas: "compilers, formal methods"
pointer_block:
  template: |
    ---
    *I write about {focus_areas} — more at [{site_name}]({site_url}).*
  newsletter:
    status: coming-soon
    rss_url: "https://ada.dev/rss.xml"
    follow_url: "https://ada.dev/follow"
    capture_url: "https://ada.dev/subscribe"
frontmatter:
  schema: [slug, title, date]
syndication:
  policy:
    en:
      mode: canonical
      variants: [devto]
  variants:
    devto:
      canonical_url_base: "https://ada.dev/articles"
YAML

V() { python3 "$VAL" --repo-config /dev/null --root "$work/root" "$@"; }

# 1. Clean config -> silent, exit 0.
if out=$(V --global-config "$work/clean.yaml" 2>&1); then rc=0; else rc=$?; fi
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then ok "clean config passes silently (exit 0, no output)"
else err "clean config not silent/zero (rc=$rc, out='$out')"; fi

# 2. Example placeholders -> halts, names the file.
if out=$(V --global-config config/user-config.example.yaml 2>&1); then rc=0; else rc=$?; fi
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'placeholder' \
   && printf '%s' "$out" | grep -q 'user-config.yaml'; then
  ok "placeholder config halts with a per-key report naming user-config.yaml"
else err "placeholder config not caught (rc=$rc)"; fi

# 3. Malformed URL (trailing-slash canonical_url_base -> double-slash canonical_url).
sed 's#https://ada.dev/articles#https://ada.dev/articles/#' "$work/clean.yaml" > "$work/badurl.yaml"
if out=$(V --global-config "$work/badurl.yaml" 2>&1); then rc=0; else rc=$?; fi
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -qi 'double.slash\|trailing slash'; then
  ok "malformed URL (double-slash canonical_url) halts with a fix"
else err "malformed URL not caught (rc=$rc)"; fi

# 4. Missing required key -> halts, names the key + file.
grep -v 'site_url' "$work/clean.yaml" > "$work/missing.yaml"
if out=$(V --global-config "$work/missing.yaml" 2>&1); then rc=0; else rc=$?; fi
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'owner.site_url' \
   && printf '%s' "$out" | grep -qi 'missing'; then
  ok "missing required key halts naming the key + file"
else err "missing key not caught (rc=$rc)"; fi

# 5. Missing/empty writing-sources -> error names the example's full path + the
#    required location (host-repo root), so a first-time user can act (#144).
mkdir -p "$work/emptyroot"
printf 'sources:\n' > "$work/emptyroot/writing-sources.yaml"   # declared but no readable sources
if out=$(python3 "$VAL" --repo-config /dev/null --root "$work/emptyroot" --global-config "$work/clean.yaml" 2>&1); then rc=0; else rc=$?; fi
if [ "$rc" -ne 0 ] \
   && printf '%s' "$out" | grep -q 'writing-sources.example.yaml' \
   && printf '%s' "$out" | grep -q 'emptyroot'; then
  ok "missing sources names the example's full path + required location (#144)"
else err "missing-sources error lacks example path/location (rc=$rc, out='$out')"; fi

# 5. Both skills wire the validator in as their up-front stage 0.
for f in "$DRAFT" "$REVIEW"; do
  grep -q 'validate-config.py' "$f" && ok "$f wires in validate-config" \
    || err "$f does not run validate-config"
  grep -qi 'per-key report naming the file\|per-key report' "$f" \
    && ok "$f documents the per-key file report" || err "$f missing file-report note"
  grep -qi 'silently' "$f" && ok "$f documents the silent-clean path" \
    || err "$f missing silent-clean note"
done

# 6. Draft SKILL: a missing writing-sources is a hard stop with an owner-confirmed
#    scaffold, not silent self-remediation (#144).
grep -qi 'hard stop' "$DRAFT" && grep -qi 'owner-confirmed' "$DRAFT" \
  && grep -qi 'never scaffold silently\|show the owner the path and contents' "$DRAFT" \
  && ok "draft SKILL: missing sources halts with an owner-confirmed scaffold (#144)" \
  || err "draft SKILL missing the hard-stop/scaffold contract for missing sources"

# 7. Story 16.2 — platform-profile validation folds into the same stage-0 pass.
#    Profiles live under the resolver's repo-config dir; drive it via a scoped
#    XDG_CONFIG_HOME so the fixture controls the machine-global location.
export XDG_CONFIG_HOME="$work/cfg"
repo_key=$(python3 scripts/resolve-paths.py repo-key --root "$work/root")
ppdir="$work/cfg/writing-assistant/repos/$repo_key/platform-profiles"
mkdir -p "$ppdir"

# 7a. A profile missing a required key halts stage 0, naming the profile file.
cat > "$ppdir/bad.yaml" <<'YAML'
platform: bad
language: en
packaging: {}
distribution_hook: x
YAML
if out=$(V --global-config "$work/clean.yaml" 2>&1); then rc=0; else rc=$?; fi
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'bad.yaml' \
   && printf '%s' "$out" | grep -qi 'audience'; then
  ok "profile missing a required key halts stage 0 naming the profile"
else err "profile missing-key not folded into stage 0 (rc=$rc, out='$out')"; fi
rm "$ppdir/bad.yaml"

# 7b. A profile declaring an intent key (mode) is rejected — intent lives in
#     user config's syndication.policy, never a profile.
cat > "$ppdir/intent.yaml" <<'YAML'
platform: intent
audience: en-reader
language: en
mode: canonical
packaging:
  visuals: mermaid-embedded
distribution_hook: x
YAML
if out=$(V --global-config "$work/clean.yaml" 2>&1); then rc=0; else rc=$?; fi
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'intent.yaml' \
   && printf '%s' "$out" | grep -qi 'intent'; then
  ok "profile intent key (mode) rejected at stage 0"
else err "profile intent-key not rejected (rc=$rc, out='$out')"; fi
rm "$ppdir/intent.yaml"

# 7c. Legacy syndication.variants.* relayed EXACTLY once as an advisory notice
#     (non-blocking) when profiles are configured; a clean valid profile adds no
#     blocking finding.
cp config/platform-profiles/devto.example.yaml "$ppdir/devto.yaml"
out=$(V --global-config "$work/clean.yaml" 2>&1 || true)
n=$(printf '%s\n' "$out" | grep -c 'notice: deprecated: syndication.variants')
if [ "$n" -eq 1 ]; then ok "legacy syndication.variants.* relayed exactly once"
else err "deprecation notice not relayed exactly once (got $n)"; fi
if out=$(V --global-config "$work/clean.yaml" 2>&1); then rc=0; else rc=$?; fi
if [ "$rc" -eq 0 ]; then ok "clean valid profile adds no blocking finding (exit 0)"
else err "clean valid profile blocked stage 0 (rc=$rc, out='$out')"; fi
rm "$ppdir/devto.yaml"

# 8. Story 18.33's track_topics existence lint + stale-mapping warning (8a-8d)
#    were REMOVED with the `track_topics` mapping itself (Story 20.161,
#    SPEC-policy-topic-at-draft CAP-3/CAP-5 as amended 2026-08-02, #1246):
#    there is no key left to lint. What is asserted instead: a leftover
#    mapping block is inert config — unknown to the parser, no finding, no
#    warning, nothing applied — because CAP-3's removal condition (no owned
#    repo config carries the keys) was checked at delivery and holds.
unset XDG_CONFIG_HOME
mkdir -p "$work/articles/drafts"
mkdir -p "$work/maproot"
cat > "$work/maproot/writing-sources.yaml" <<YAML
sources:
  - path: .
output:
  drafts: $work/articles/drafts/
policy_source:
  enabled: true
  track_topics:
    eval-engineering: benchmark-engineering
YAML
set +e
out=$(python3 "$VAL" --repo-config /dev/null --root "$work/maproot" \
      --global-config "$work/clean.yaml" 2>&1); rc=$?
set -e
if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q 'track_topics'; then
  ok "a leftover track_topics block is inert: no lint, no warning, toggle alone governs (20.161)"
else err "leftover track_topics still produced findings (rc=$rc, out='$out')"; fi

# 8e. The topic ask is RETIRED (Story 20.160, #1255; SPEC-policy-topic-at-draft
#     amended 2026-08-02, #1246 — owner ruling). This assertion used to require
#     the draft SKILL to document `track_topics` seeding a DEFAULT
#     RECOMMENDATION for the ≤2-topic proposal. There is no proposal any more,
#     so that contract is obsolete — and an assertion guarding a retired
#     mechanism is worse than none: it fails green work and teaches the reader
#     that the mechanism still lives. Inverted rather than deleted, so the
#     retirement keeps a carrier: the ask must be ABSENT and the claim-bounded
#     transport PRESENT.
#     The `track_topics` CONFIG KEY itself was removed by story 20.161,
#     together with its validation (section 8 above asserts it is inert).
#     Asserted on the INVOCATION, not on the prose: stage2.md quotes the
#     retired question verbatim in its own retirement note, so a string-absence
#     sweep over the text cannot tell a mention from a use — the enumerated-
#     prohibition trap. The registry is the real carrier for the gate's absence
#     (`check-gate-inventory.sh`); here the carrier is what the stage RUNS.
if grep -qE '(^|[^-])read --topics' "$DRAFT"; then
  err "the draft SKILL still invokes the retired \`read --topics\` pre-pick (#1246)"
elif grep -q 'query --claim' "$DRAFT"; then
  ok "topic ask retired; the policy read is claim-bounded (#1246)"
else
  err "draft SKILL invokes neither \`read --topics\` nor \`query --claim\`"
fi

# 9. The `journey:` config key is RETIRED (Story 20.134, #1183). Its only
#    consumer was the host-repo episode join, which is removed, so the key, its
#    resolver subcommand, its exit code and this lint went with it. The tests
#    that asserted the lint are deleted rather than weakened; what is asserted
#    here is that the subcommand is gone, so nothing keeps calling it.
RWS="scripts/resolve-writing-sources.py"
set +e
python3 "$RWS" --root "$work" journey >/dev/null 2>&1; rc=$?
set -e
[ "$rc" -ne 0 ] \
  && ok "#1183: the retired \`journey\` subcommand is gone (argparse refuses it)" \
  || err "the retired \`journey\` subcommand still resolves"
grep -qE '^def get_journey|validate_journey\(args' "$RWS" "$VAL" \
  && err "a retired journey: reader or lint is still defined (#1183)" \
  || ok "#1183: no journey: reader or lint is defined anywhere"

if [ "$fail" -eq 0 ]; then
  printf '\nAll config-validation checks passed.\n'; exit 0
else
  printf '\nconfig-validation checks FAILED.\n' >&2; exit 1
fi
