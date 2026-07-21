#!/usr/bin/env sh
# check-stage0-fold.sh — verify the folded Stage-0 command (Story 13.13):
# config validation + framework check + workspace autostart in ONE invocation,
# halting on the first problem, preserving each check's diagnostics, and never
# minting a workspace on a bad config/framework. POSIX shell + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="$root/scripts/draft-pipeline.py"
SKILL="skills/draft-article/SKILL.md"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
jget() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

python3 -c "import py_compile; py_compile.compile('$DP', doraise=True)" 2>/dev/null \
  && ok "pipeline helper compiles" || { err "helper syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
host="$work/host"; mkdir -p "$host"; git -C "$host" init -q
export XDG_STATE_HOME="$work/state"

ws_count() { find "$work/state" -type d -path '*/runs/*' 2>/dev/null | wc -l; }

# 1. Bad config (no writing-sources.yaml) -> halt, verbatim report, no run_state,
#    no workspace minted.
if out=$(python3 "$DP" stage0 F2 specs/ --root "$host" 2>"$work/err"); then rc=0; else rc=$?; fi
[ "$rc" -ne 0 ] && ok "stage0 halts non-zero on a bad config" || err "stage0 did not halt on bad config"
grep -q 'configuration validation failed' "$work/err" && ok "stage0 relays validate-config's report verbatim" || err "stage0 lost the config report"
[ -z "$out" ] && ok "stage0 prints no run_state JSON on a bad config" || err "stage0 emitted run_state on a bad config"
[ "$(ws_count)" -eq 0 ] && ok "no workspace minted on a bad config" || err "workspace minted despite bad config"

# Make the config clean for the remaining cases.
printf 'sources:\n  - path: .\n' > "$host/writing-sources.yaml"

# 2. Bad framework -> exit 2, nothing started, still no workspace.
if out=$(python3 "$DP" stage0 F9 specs/ --root "$host" 2>"$work/err"); then rc=0; else rc=$?; fi
[ "$rc" -eq 2 ] && ok "stage0 rejects an invalid framework (exit 2)" || err "stage0 did not reject bad framework"
grep -q 'invalid article type' "$work/err" && ok "stage0 names the invalid article type" || err "article-type error not reported"
grep -q 'introduce the project' "$work/err" && ok "invalid-type error lists intent labels" || err "error does not list intent labels"
[ "$(ws_count)" -eq 0 ] && ok "no workspace minted on a bad framework" || err "workspace minted despite bad framework"

# 2b. Intent label resolves to the same framework as its F-id alias
#     (SPEC-draft-article-ux CAP-1, Story 13.27) — closed mapping, no fuzz.
out=$(python3 "$DP" stage0 "share engineering lessons" specs/ --root "$host")
echo "$out" | jget 'd["run_state"]["framework"]' | grep -q F2 \
  && ok "intent label 'share engineering lessons' resolves to F2" \
  || err "intent label did not resolve to F2"
if python3 "$DP" stage0 "share lessons" specs/ --root "$host" >/dev/null 2>&1; then
  err "fuzzy intent label accepted — mapping must be closed"
else
  ok "near-miss intent label rejected (closed mapping)"
fi

# 3. Clean config + framework -> one JSON with config_ok, run_state, and a workspace.
out=$(python3 "$DP" stage0 F2 specs/ --root "$host")
echo "$out" | jget 'd["config_ok"]' | grep -q True && ok "stage0 reports config_ok on a clean config" || err "config_ok missing/false"
echo "$out" | jget 'd["run_state"]["framework"]' | grep -q F2 && ok "stage0 carries the run_state (framework F2)" || err "run_state missing"
echo "$out" | jget 'd["resumed"]' | grep -q False && ok "stage0 mints a fresh run when none is in progress" || err "stage0 false-resumed"
ws=$(echo "$out" | jget 'd["ws"]'); [ -d "$ws" ] && ok "stage0 returns a real workspace dir" || err "stage0 workspace missing"

# 4. Fold is real: on a second invocation with an in-progress checkpoint, stage0
#    resumes it rather than minting a new run.
printf '{"stage":"consume","next_stage":"interview"}' | python3 "$DP" checkpoint --ws "$ws" - >/dev/null
out=$(python3 "$DP" stage0 F2 specs/ --root "$host")
echo "$out" | jget 'd["resumed"]' | grep -q True && ok "stage0 auto-resumes an in-progress run" || err "stage0 did not resume"
echo "$out" | jget 'd["next_stage"]' | grep -q interview && ok "stage0 resumes at the recorded next_stage" || err "stage0 resumed at wrong stage"
unset XDG_STATE_HOME

# 5. SKILL wires Stage 0 as one folded call.
grep -qi 'draft-pipeline.py stage0' "$SKILL" && grep -qi 'one call\|single invocation\|one turn' "$SKILL" \
  && ok "SKILL wires the folded stage0 (Story 13.13)" || err "SKILL does not wire the folded stage0"

# 6. CAP-8 (#432) — an optional depth/scope directive is captured into run-state:
#    a level maps to {"level": …}, anything else to {"scope": …}, and absent it
#    is simply not present (prior behavior byte-for-byte).
out=$(python3 "$DP" start F2 specs/ --root "$host" --depth deep-dive)
echo "$out" | jget "d.get('depth')" | grep -q "'level': 'deep-dive'" \
  && ok "depth level directive captured as {level} (CAP-8)" || err "depth level not captured"
out=$(python3 "$DP" start F2 specs/ --root "$host" --depth "just the retry bug, deeply")
echo "$out" | jget "d.get('depth')" | grep -q "'scope':" \
  && ok "depth scope statement captured as {scope} (CAP-8)" || err "depth scope not captured"
out=$(python3 "$DP" start F2 specs/ --root "$host")
echo "$out" | jget "'depth' in d" | grep -q False \
  && ok "no --depth -> no depth key (prior behavior unchanged)" || err "depth key present without directive"
grep -qi 'depth/scope directive' "$SKILL" && grep -q 'CAP-8' "$SKILL" \
  && ok "SKILL documents the depth/scope directive (CAP-8)" || err "SKILL missing depth/scope guidance"

# 6b. Story 18.24 (#505) — an optional free-form owner coverage brief rides the
#     same stage-0 call: recorded with owner-authored provenance, and it NEVER
#     widens the classified source set (a filter, never a scope widener).
out=$(python3 "$DP" start F2 specs/ --root "$host" --brief "cover the retry storm")
echo "$out" | jget "d.get('brief',{}).get('provenance')" | grep -q owner-authored \
  && ok "coverage brief captured with owner-authored provenance (#505)" || err "brief provenance not captured"
base_src=$(python3 "$DP" start F2 specs/ --root "$host" | jget 'json.dumps(d["sources"])')
brief_src=$(echo "$out" | jget 'json.dumps(d["sources"])')
[ "$base_src" = "$brief_src" ] \
  && ok "the brief leaves the source set identical (never a scope widener)" || err "brief widened the source set"
out=$(python3 "$DP" start F2 specs/ --root "$host")
echo "$out" | jget "'brief' in d" | grep -q False \
  && ok "no --brief -> no brief key (prior behavior unchanged)" || err "brief key present without a brief"
grep -qi 'coverage brief' "$SKILL" \
  && ok "SKILL documents the owner coverage brief (#505)" || err "SKILL missing coverage-brief guidance"

# 7. Story 18.19 (#494) — a declared syndication variant with no resolvable
#    platform profile WARNS (informational bucket), never a hard fail; a
#    resolvable platform produces no warning.
export XDG_STATE_HOME="$work/state7"
cat > "$work/synd-cfg.json" <<'JSON'
{"owner":{"name":"X","site_url":"https://x"},
 "frontmatter":{"schema":["slug"]},
 "syndication":{"policy":{"en":{"mode":"canonical","variants":["devto"]}}}}
JSON
mkdir -p "$work/pp_empty"        # no devto.yaml → devto is unresolvable
out=$(python3 "$DP" stage0 F2 specs/ --root "$host" \
        --config-json "$work/synd-cfg.json" --profiles-dir "$work/pp_empty") \
  && ok "stage0 still succeeds (exit 0) with an unresolvable declared variant" \
  || err "stage0 hard-failed on an unresolvable declared variant (must warn, not fail)"
echo "$out" | jget '[w["platform"] for w in d.get("syndication_warnings", [])]' | grep -q devto \
  && ok "declared variant with no profile is surfaced as a stage-0 warning (devto)" \
  || err "unresolvable declared variant produced no warning"
echo "$out" | jget 'd.get("syndication_warnings",[{}])[0].get("bucket")' | grep -q informational \
  && ok "the warning is in the informational bucket (not a hard fail)" || err "warning bucket wrong"
echo "$out" | jget 'd["config_ok"]' | grep -q True \
  && ok "config_ok stays True under the informational warning" || err "warning flipped config_ok"
echo "$out" | jget 'd["next_stage"]' | grep -q harvest \
  && ok "next_stage still harvest under the informational warning" || err "warning changed next_stage"

mkdir -p "$work/pp_full"         # devto.yaml resolves → no warning
cp config/platform-profiles/devto.example.yaml "$work/pp_full/devto.yaml"
out=$(python3 "$DP" stage0 F2 specs/ --root "$host" \
        --config-json "$work/synd-cfg.json" --profiles-dir "$work/pp_full")
echo "$out" | jget '"syndication_warnings" in d' | grep -q False \
  && ok "a declared variant WITH a resolvable profile produces no warning" \
  || err "a resolvable declared variant still warned"

# A config declaring no syndication variants never adds the warning key at all.
printf '{"owner":{"name":"X"},"frontmatter":{"schema":["slug"]}}' > "$work/nosynd.json"
out=$(python3 "$DP" stage0 F2 specs/ --root "$host" \
        --config-json "$work/nosynd.json" --profiles-dir "$work/pp_empty")
echo "$out" | jget '"syndication_warnings" in d' | grep -q False \
  && ok "no declared variants → no syndication warning key (prior output shape)" \
  || err "syndication warning key appeared with no declared variants"

# 7b. Story 18.36 (#530) — the SAME declared-variant/no-resolvable-profile
#     finding is ALSO surfaced as an actionable PUBLISH BLOCKER naming the exact
#     missing profile path (routed to the completion summary's publish-blocker
#     bucket), while draft start stays non-blocking (config_ok/next_stage
#     unchanged — 18.19 holds).
out=$(python3 "$DP" stage0 F2 specs/ --root "$host" \
        --config-json "$work/synd-cfg.json" --profiles-dir "$work/pp_empty")
echo "$out" | jget '[b["platform"] for b in d.get("publish_blockers", [])]' | grep -q devto \
  && ok "#530 unresolvable declared variant → publish_blockers entry (devto)" \
  || err "#530 no publish blocker for an unresolvable declared variant"
echo "$out" | jget 'd.get("publish_blockers",[{}])[0].get("missing_profile_path","")' \
  | grep -Eq 'pp_empty/devto\.yaml$' \
  && ok "#530 publish blocker names the EXACT missing profile path (<dir>/devto.yaml)" \
  || err "#530 publish blocker path wrong: $(echo "$out" | jget 'd.get("publish_blockers")')"
echo "$out" | jget 'd.get("publish_blockers",[{}])[0].get("bucket")' | grep -q publish-blocker \
  && ok "#530 blocker is tagged for the publish-blocker bucket" || err "#530 blocker bucket wrong"
echo "$out" | jget 'd["config_ok"]' | grep -q True \
  && ok "#530 config_ok stays True (draft start not blocked — 18.19 preserved)" || err "#530 blocker flipped config_ok"
echo "$out" | jget 'd["next_stage"]' | grep -q harvest \
  && ok "#530 next_stage still harvest (blocker is publish-boundary, not a halt)" || err "#530 blocker changed next_stage"

# A declared variant WITH a resolvable profile → no publish blocker (unchanged).
out=$(python3 "$DP" stage0 F2 specs/ --root "$host" \
        --config-json "$work/synd-cfg.json" --profiles-dir "$work/pp_full")
echo "$out" | jget '"publish_blockers" in d' | grep -q False \
  && ok "#530 resolvable declared variant → no publish blocker" \
  || err "#530 resolvable declared variant still produced a publish blocker"

# No declared variants → no publish blocker key at all.
out=$(python3 "$DP" stage0 F2 specs/ --root "$host" \
        --config-json "$work/nosynd.json" --profiles-dir "$work/pp_empty")
echo "$out" | jget '"publish_blockers" in d' | grep -q False \
  && ok "#530 no declared variants → no publish blocker key" \
  || err "#530 publish blocker key appeared with no declared variants"
unset XDG_STATE_HOME

if [ "$fail" -eq 0 ]; then
  printf '\nAll stage0-fold checks passed.\n'; exit 0
else
  printf '\nstage0-fold checks FAILED.\n' >&2; exit 1
fi
