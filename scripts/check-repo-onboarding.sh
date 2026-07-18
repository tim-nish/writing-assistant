#!/usr/bin/env sh
# check-repo-onboarding.sh — verify SPEC-repo-onboarding: the CAP-2 config
# writers (set-policy-source, set-sources), the setup skill (CAP-1/3), and the
# README/manifest surface (CAP-4). POSIX shell + stdlib Python only.
#
# Covers: creating a full config from scratch through writers only (no manual
# YAML) in the conventional block order; the re-shaped set-policy-source
# (Story 13.73: presence toggle, NO path argument; declarative block replace
# is the sanctioned migration for a legacy path/track/topics block);
# idempotency (unchanged input rewrites nothing); fail-closed refusals that
# write NOTHING (`..` include pattern / empty list exit 5); declarative
# set-sources replace emitting the inline include form (#221); legacy in-repo
# file migrating whole to the machine-global path on first write; and the
# setup skill contract lines (writers-only, policy_source optional with
# stated consequence, toggle-not-path, no absolute plugin paths).

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

RES="scripts/resolve-writing-sources.py"
PY="python3 $root/$RES"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$root/$RES', doraise=True)" 2>/dev/null \
  && ok "resolver compiles" || { err "resolver syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
# Isolate the machine-global config root so the suite never touches real config.
XDG_CONFIG_HOME="$work/xdg"; export XDG_CONFIG_HOME
mkdir -p "$work/host" "$work/plab"

gfile() { find "$work/xdg" -name writing-sources.yaml 2>/dev/null | head -1; }

# --- 1. Full config from scratch, writers only, conventional order ----------
printf '[{"path": ".", "include": ["docs/**", "README.md"]}, {"path": "../plab"}]' \
  | $PY set-sources --root "$work/host" >/dev/null 2>&1 \
  && ok "set-sources creates the file from scratch" \
  || err "set-sources failed on a missing config"
$PY set-draft-location "~/drafts/" --root "$work/host" >/dev/null 2>&1
out=$($PY set-policy-source --root "$work/host" 2>/dev/null); rc=$?
[ "$rc" -eq 0 ] && [ "$out" = '{"declared": true}' ] \
  && ok "set-policy-source declares the toggle (JSON echo, no path ever)" \
  || err "set-policy-source: rc=$rc out='$out'"
# The retired PATH positional (13.73) and the removed flags (13.36) are gone
# from the CLI — passing one is a usage error, not a silent write.
if $PY set-policy-source ../plab --root "$work/host" >/dev/null 2>&1; then
  err "PATH argument still accepted (retired, Story 13.73)"
else
  ok "PATH argument retired with the config key (13.73)"
fi
if $PY set-policy-source --track eval --root "$work/host" >/dev/null 2>&1; then
  err "--track still accepted (flag should be removed)"
else
  ok "--track flag removed with the config keys"
fi
f=$(gfile)
[ -n "$f" ] || { err "no machine-global file created"; printf '\nFAILED.\n' >&2; exit 1; }
case "$f" in "$work/host"/*) err "config landed IN the host repo (#211)";; *) ok "config is machine-global, not in-host (#211)";; esac
order=$(grep -nE '^(sources|output|policy_source):' "$f" | cut -d: -f2 | tr '\n' ' ')
[ "$order" = "sources output policy_source " ] \
  && ok "conventional block order (sources, output, policy_source)" \
  || err "unexpected block order: $order"
grep -q 'include: \["docs/\*\*", "README.md"\]' "$f" \
  && ok "set-sources emits the inline include form (#221)" \
  || err "include not emitted inline"

# --- 2. Surgery preserves comments outside the block & untouched keys --------
printf '# HEADER kept\n%s' "$(cat "$f")" > "$f"
$PY set-policy-source --root "$work/host" >/dev/null 2>&1
head -1 "$f" | grep -q '# HEADER kept' && ok "surgery keeps comments outside the block" || err "comment lost"
grep -q 'enabled: true' "$f" && ! grep -q '^  path:' "$f" \
  && ok "block is the presence toggle — no path key on disk" || err "toggle surgery wrong"

# --- 3. Idempotency: unchanged input writes nothing ---------------------------
m1=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f")
sleep 1
$PY set-policy-source --root "$work/host" >/dev/null 2>&1
m2=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f")
[ "$m1" = "$m2" ] && ok "set-policy-source idempotent" || err "rewrote an unchanged file"

# --- 4. Legacy keys: named errors on read, migrated whole by the writer -------
sed -i.bak '/^policy_source:/a\
  path: ../plab\
  track: leftover' "$f" && rm -f "$f.bak"
rc=0; msg=$($PY --root "$work/host" policy-source 2>&1 >/dev/null) || rc=$?
[ "$rc" -eq 4 ] && printf '%s' "$msg" | grep -q 'policy_source.path' \
  && printf '%s' "$msg" | grep -qi 'retired' \
  && ok "legacy path/track keys: getter exit 4 with the migration notice" \
  || err "legacy-key getter: rc=$rc msg='$msg'"
# The re-shaped writer is the sanctioned migration: the whole block is
# replaced by the toggle (13.73) — legacy keys never survive, never honored.
rc=0; $PY set-policy-source --root "$work/host" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 0 ] && grep -q 'enabled: true' "$f" \
  && ! grep -Eq '^  (path|track|topics):' "$f" \
  && ok "writer migrates a legacy block whole to the toggle (13.73)" \
  || err "legacy-block migration failed: rc=$rc"
before=$(cat "$f")
rc=0; printf '[{"path": ".", "include": ["../evil/**"]}]' | $PY set-sources --root "$work/host" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 5 ] && [ "$(cat "$f")" = "$before" ] \
  && ok ".. include pattern: exit 5, file untouched" || err ".. pattern: rc=$rc or file changed"
rc=0; printf '[]' | $PY set-sources --root "$work/host" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 5 ] && ok "empty sources list: exit 5" || err "empty list: rc=$rc"
rc=0; printf 'not json' | $PY set-sources --root "$work/host" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 5 ] && ok "non-JSON stdin: exit 5" || err "non-JSON: rc=$rc"

# --- 5. Declarative replace: old sources gone, others blocks survive ----------
printf '[{"path": "../plab"}]' | $PY set-sources --root "$work/host" >/dev/null 2>&1
grep -q 'path: \.$' "$f" && err "old source survived declarative replace" \
  || ok "declarative replace drops old sources"
grep -q 'drafts: ~/drafts/' "$f" && grep -q 'policy_source:' "$f" \
  && ok "output/policy blocks survive set-sources" || err "unrelated block lost"

# --- 6. Legacy in-repo file migrates whole on first write --------------------
mkdir -p "$work/legacyhost"
cat > "$work/legacyhost/writing-sources.yaml" <<'YAML'
sources:
  - path: .
output:
  drafts: articles/drafts/
YAML
$PY set-policy-source --root "$work/legacyhost" >/dev/null 2>"$work/e6"
grep -q 'migrated:' "$work/e6" && ok "legacy file: migration notice" || err "no migration notice"
g=$(find "$work/xdg" -path '*legacyhost*' -name writing-sources.yaml 2>/dev/null | head -1)
[ -n "$g" ] && grep -q 'sources:' "$g" && grep -q 'policy_source:' "$g" \
  && ok "legacy content migrated whole (sources + new block)" \
  || err "migration incomplete: $g"

# --- 7. Setup skill contract (CAP-1/3) ----------------------------------------
SK="skills/setup/SKILL.md"
[ -f "$SK" ] && ok "setup skill exists" || { err "missing $SK"; printf '\nFAILED.\n' >&2; exit 1; }
grep -q '^name: setup$' "$SK" && ok "skill frontmatter name" || err "frontmatter name missing"
grep -q 'set-policy-source' "$SK" && grep -q 'set-sources' "$SK" \
  && ok "skill writes through the sanctioned writers" || err "skill missing writer commands"
grep -qi 'Never present `policy_source` as required' "$SK" \
  && ok "policy_source stays optional (C2)" || err "skill lacks the optionality clause"
grep -q 'consulted: none' "$SK" \
  && ok "decline consequence stated (C2 setup-time surfacing)" || err "consequence line missing"
grep -q 'resolve-user-config.py' "$SK" \
  && ok "user-config check present (CAP-3)" || err "CAP-3 stage missing"
grep -q '/home/' "$SK" && err "skill carries an absolute path" \
  || ok "no absolute paths (CLAUDE_PLUGIN_ROOT only)"

# --- 8. README + manifest surface (CAP-4) -------------------------------------
grep -q '`setup` skill' README.md && ok "README documents setup as first-run path" \
  || err "README missing setup"
grep -q 'escape hatch' README.md && ok "README keeps manual edit as escape hatch" \
  || err "README escape hatch missing"
grep -q 'setup, draft-article' .claude-plugin/plugin.json \
  && ok "plugin manifest lists setup" || err "manifest missing setup"

# Setup offers/writes the PRESENCE TOGGLE only (Story 13.73, #366): never a
# filesystem path; topic context stays a draft-time decision (13.34/13.36).
SK="skills/setup/SKILL.md"
grep -q 'presence toggle' "$SK" && grep -q 'enabled: true' "$SK" \
  && ok "setup offer is the presence toggle" || err "setup missing the toggle offer"
grep -qi 'never a filesystem path' "$SK" \
  && ok "setup never proposes a hub path (13.73)" || err "setup still proposes a path"
grep -q 'set-policy-source <path>' "$SK" \
  && err "setup Stage C still passes a path to the writer" \
  || ok "setup Stage C writes the toggle without a path"
grep -q 'per-article decision' "$SK" && ok "setup names topics a per-article decision" \
  || err "draft-time rationale missing"
grep -qE 'a .track. matched|track proposal' "$SK" \
  && err "setup Stage B still proposes a track" \
  || ok "setup Stage B proposes no track"
# Stage E is a GATEWAY health check: findings, not hard failures (13.73).
grep -qi 'gateway health check' "$SK" \
  && ok "setup Stage E verifies via a gateway health check" \
  || err "Stage E missing the gateway health check wording"
grep -qi 'gateway-reachable' "$SK" \
  && ok "Stage E counts exit 13's named gap as gateway-reachable" \
  || err "Stage E missing the exit-13 reachability rule"

[ "$fail" -eq 0 ] && printf '\nPASSED.\n' || { printf '\nFAILED.\n' >&2; exit 1; }
