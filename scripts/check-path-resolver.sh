#!/usr/bin/env sh
# check-path-resolver.sh — verify the path resolver is the single source of
# storage paths (Story 9.1). POSIX shell + stdlib Python only.
#
# Covers: the resolver compiles; the state root honours $XDG_STATE_HOME set and
# unset (AC3); the repo key is the path slug of a given git toplevel (AC4);
# repo-dir composes state-root/repo-key; and a grep of skills and scripts finds
# NO state/workspace path literal constructed anywhere but resolve-paths.py
# (AC2 — the single-source invariant).

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

RES="scripts/resolve-paths.py"
PY="python3 $root/$RES"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else err "$1 (got '$2', want '$3')"; fi; }

# 0. Resolver compiles.
if python3 -c "import py_compile; py_compile.compile('$root/$RES', doraise=True)" 2>/dev/null; then
  ok "resolver compiles"
else
  err "resolver syntax error"; printf '\nChecks FAILED.\n' >&2; exit 1
fi

# 1. State root honours $XDG_STATE_HOME when set (AC3).
got=$(XDG_STATE_HOME=/tmp/xdgstate $PY state-root)
eq "state-root: XDG_STATE_HOME set" "$got" "/tmp/xdgstate/writing-assistant"

# 2. State root falls back to ~/.local/state when XDG_STATE_HOME is unset (AC3).
got=$(env -u XDG_STATE_HOME $PY state-root)
eq "state-root: XDG_STATE_HOME unset -> default" "$got" "$HOME/.local/state/writing-assistant"

# 2b. Empty XDG_STATE_HOME is treated as unset (XDG base-dir spec).
got=$(XDG_STATE_HOME= $PY state-root)
eq "state-root: empty XDG_STATE_HOME -> default" "$got" "$HOME/.local/state/writing-assistant"

# 3. Repo key is the path slug of the git toplevel (AC4): non-alnum runs -> '-'.
#    --root validates isdir (a later guard), so slug fixtures are real temp dirs.
slugroot=$(mktemp -d /tmp/blog.a_b.XXXXXX)
trap 'rm -rf "$slugroot" "${cfg:-}" "${hostwork:-}"' EXIT
want=$(printf '%s' "$slugroot" | sed 's/[^A-Za-z0-9][^A-Za-z0-9]*/-/g')
eq "repo-key: path slug of --root (non-alnum runs -> '-')" \
   "$($PY repo-key --root "$slugroot")" "$want"

# 4. repo-dir composes state-root/repo-key.
sr=$(XDG_STATE_HOME=/tmp/xdgstate $PY state-root)
rk=$($PY repo-key --root "$slugroot")
eq "repo-dir: state-root/repo-key" \
   "$(XDG_STATE_HOME=/tmp/xdgstate $PY repo-dir --root "$slugroot")" \
   "$sr/$rk"

# 4b. Per-repo config dir composes config-home/repos/repo-key (Story 13.23, #211).
ch=$(XDG_CONFIG_HOME=/tmp/xdgconf $PY config-home)
eq "config-home: honours XDG_CONFIG_HOME" "$ch" "/tmp/xdgconf/writing-assistant"
eq "repo-config-dir: config-home/repos/repo-key" \
   "$(XDG_CONFIG_HOME=/tmp/xdgconf $PY repo-config-dir --root "$slugroot")" \
   "$ch/repos/$rk"

# 4c. sources-file resolution (Story 13.23, #211): global wins > legacy read
#     with deprecation > neither exits 3 naming the machine-global path.
cfg=$(mktemp -d); hostwork=$(mktemp -d)
rk2=$($PY repo-key --root "$hostwork")
gdir="$cfg/writing-assistant/repos/$rk2"

# neither -> exit 3, prints the machine-global path, stderr says create-there
out=$(XDG_CONFIG_HOME="$cfg" $PY sources-file --root "$hostwork" 2>/tmp/sf_err.$$) && rc=0 || rc=$?
[ "$rc" = "3" ] && ok "sources-file: neither -> exit 3" || err "sources-file: neither -> exit $rc (want 3)"
eq "sources-file: neither names the machine-global path" "$out" "$gdir/writing-sources.yaml"
grep -q "never in the host repo" /tmp/sf_err.$$ \
  && ok "sources-file: neither-case stderr points away from the host repo" \
  || err "sources-file: neither-case stderr misses the boundary note"

# legacy only -> resolves to the in-repo file, deprecation on stderr
printf 'sources:\n  - path: .\n' > "$hostwork/writing-sources.yaml"
out=$(XDG_CONFIG_HOME="$cfg" $PY sources-file --root "$hostwork" 2>/tmp/sf_err.$$) || err "sources-file: legacy-only exited non-zero"
eq "sources-file: legacy only -> in-repo path" "$out" "$(realpath "$hostwork")/writing-sources.yaml"
grep -q "deprecated" /tmp/sf_err.$$ \
  && ok "sources-file: legacy-only emits a deprecation notice" \
  || err "sources-file: legacy-only missing deprecation notice"

# both -> machine-global wins
mkdir -p "$gdir"
printf 'sources:\n  - path: .\n' > "$gdir/writing-sources.yaml"
out=$(XDG_CONFIG_HOME="$cfg" $PY sources-file --root "$hostwork" 2>/dev/null)
eq "sources-file: both exist -> machine-global wins" "$out" "$gdir/writing-sources.yaml"

# global only -> machine-global, no deprecation
rm -f "$hostwork/writing-sources.yaml"
out=$(XDG_CONFIG_HOME="$cfg" $PY sources-file --root "$hostwork" 2>/tmp/sf_err.$$)
eq "sources-file: global only -> machine-global path" "$out" "$gdir/writing-sources.yaml"
[ -s /tmp/sf_err.$$ ] && err "sources-file: global-only should be silent on stderr" \
  || ok "sources-file: global-only is silent"
rm -f /tmp/sf_err.$$

# 4d. Consumers resolve through the same seam: resolve-writing-sources.py reads
#     the machine-global file (global-only case) and both-exist prefers global.
RWS="python3 $root/scripts/resolve-writing-sources.py"
got=$(XDG_CONFIG_HOME="$cfg" $RWS sources --root "$hostwork" 2>/dev/null)
eq "consumer: rws sources reads the machine-global file" "$got" "$(realpath "$hostwork")"
printf 'sources:\n  - path: /nonexistent-legacy-marker\n' > "$hostwork/writing-sources.yaml"
got=$(XDG_CONFIG_HOME="$cfg" $RWS sources --root "$hostwork" 2>/tmp/sf_err.$$)
eq "consumer: both exist -> global content wins" "$got" "$(realpath "$hostwork")"
grep -q "ignoring legacy" /tmp/sf_err.$$ \
  && ok "consumer: both-exist emits the ignoring-legacy notice" \
  || err "consumer: both-exist notice missing"
rm -f /tmp/sf_err.$$ "$hostwork/writing-sources.yaml"

# 5. Single-source invariant (AC2): no state/workspace path literal is
#    constructed anywhere in production skills/ or scripts/ except
#    resolve-paths.py. We look for the state-root literals and any hand-built
#    runs/ workspace path. check-*.sh are test harnesses that reference these
#    patterns to assert the resolver's behaviour, not to build production
#    paths, so they are excluded.
pat='\.local/state|XDG_STATE_HOME|runs/[^ )"'"'"']*<|runs/<run'
offenders=$(grep -REnoI "$pat" skills scripts 2>/dev/null \
  | grep -v '/__pycache__/' \
  | grep -v '^scripts/resolve-paths.py:' \
  | grep -v '^scripts/check-[^:]*\.sh:' || true)
if [ -z "$offenders" ]; then
  ok "single-source: no state/workspace path literal outside resolve-paths.py"
else
  err "state/workspace path literal constructed outside the resolver:"
  printf '%s\n' "$offenders" >&2
fi

# --- list-drafts: the review draft picker's enumeration (Story 13.31) ---------
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
host="$work/host"; mkdir -p "$host"; git -C "$host" init -q
export XDG_STATE_HOME="$work/state"

# Empty repo -> empty JSON list (data, not an error).
[ "$($PY list-drafts --root "$host")" = "[]" ] \
  && ok "list-drafts: no runs -> empty list, exit 0" || err "empty enumeration failed"

# One run with a draft + done checkpoint, one without a draft, one reviewed.
ws1=$($PY new-run --root "$host" --run-id r1)
printf -- '---\ntitle: "Alpha article"\n---\nbody\n' > "$ws1/draft.md"
printf '{"next_stage": "done", "framework": "F2"}' > "$ws1/checkpoint.json"
ws2=$($PY new-run --root "$host" --run-id r2)   # no draft.md — never listed
ws3=$($PY new-run --root "$host" --run-id r3)
printf -- '---\ntitle: "Gamma article"\n---\nbody\n' > "$ws3/draft.md"
printf '{"next_stage": "done", "framework": "F3", "reviewed": true}' > "$ws3/checkpoint.json"

$PY list-drafts --root "$host" | python3 -c "
import json, sys
ds = json.load(sys.stdin)
assert [d['run_id'] for d in ds] == ['r1', 'r3'], ds
a, g = ds
assert a['title'] == 'Alpha article' and a['status'] == 'complete', a
assert a['article_type'] == 'share engineering lessons', a
assert 'F2' not in json.dumps(a), 'internal id leaked into picker metadata'
assert g['status'] == 'reviewed', g
assert all(d['updated'] > 0 and d['draft'].endswith('draft.md') for d in ds)
" && ok "list-drafts: metadata (title, intent label, status), draft-less runs skipped, no F-id leak" \
  || err "list-drafts metadata wrong"

# Intent-label map stays in sync with the canonical one in draft-pipeline.py.
python3 - "$root" <<'PYEOF' && ok "picker intent labels match draft-pipeline INTENT_LABELS" || err "intent-label maps diverged"
import importlib.util, os, sys
def load(p, n):
    s = importlib.util.spec_from_file_location(n, p)
    m = importlib.util.module_from_spec(s); s.loader.exec_module(m); return m
root = sys.argv[1]
rp = load(os.path.join(root, "scripts", "resolve-paths.py"), "rp")
dp = load(os.path.join(root, "scripts", "draft-pipeline.py"), "dp")
assert rp._INTENT_LABELS == {k.upper(): v for k, v in dp.INTENT_LABELS.items()}, \
    (rp._INTENT_LABELS, dp.INTENT_LABELS)
PYEOF

# --- #309: target-repo selection is visible, and its precedence is tested -------
# The story's gap: no check exercised the cwd-default path or a --root/cwd
# disagreement, so the exit-2 contract and the precedence lived only in code.
tgt=$(mktemp -d); trap 'rm -rf "$work" "$tgt"' EXIT
git init -q "$tgt/other" && git -C "$tgt/other" commit -q --allow-empty -m x

# (a) from the repo root and (b) from a subdirectory -> the same resolved root.
root_here=$(cd "$root" && $PY target)
sub_here=$(cd "$root/scripts" && $PY target)
eq "target: same resolved root from the repo root and a subdirectory" "$root_here" "$sub_here"

# (c) outside any git repo with no --root -> exit 2, naming the fix.
set +e
msg=$(cd / && $PY target 2>&1 >/dev/null); rc=$?
set -e
[ "$rc" -eq 2 ] && ok "target: outside a git repo with no --root exits 2 (fail closed)" \
  || err "expected exit 2 outside a git repo, got $rc"
printf '%s' "$msg" | grep -q -- '--root' \
  && ok "target: the exit-2 diagnostic names --root as the fix" || err "exit-2 diagnostic unhelpful"

# (d) --root disagreeing with cwd -> informational notice naming BOTH; --root wins.
set +e
note=$(cd "$root" && $PY target --root "$tgt/other" 2>&1 >/dev/null)
picked=$(cd "$root" && $PY target --root "$tgt/other" 2>/dev/null)
set -e
printf '%s' "$note" | grep -q "$(cd "$tgt/other" && pwd -P)" && printf '%s' "$note" | grep -q "$root" \
  && ok "target: a --root/cwd disagreement names both roots" || err "disagreement notice missing a root: $note"
eq "target: explicit --root still wins the disagreement" "$picked" "$(cd "$tgt/other" && pwd -P)"

# (e) agreement -> no notice (the notice must not become noise on every run).
set +e; quiet=$(cd "$root" && $PY target --root "$root" 2>&1 >/dev/null); set -e
[ -z "$quiet" ] && ok "target: no notice when --root agrees with cwd" || err "spurious notice: $quiet"


# --- #309 (13.54): stage0's entry gate keys to the RESOLVED root ---------------
# The gate ran `git tag` with cwd=(root or None) — raw process cwd — while the
# workspace and config keyed to the resolved toplevel. Outside a git repo that
# produced a confident, WRONG diagnostic ("no tagged release") for what was
# actually an unresolvable target.
DPIPE="$root/scripts/draft-pipeline.py"
gatehost=$(mktemp -d); trap 'rm -rf "$work" "$tgt" "$gatehost"' EXIT
git init -q "$gatehost/h" && git -C "$gatehost/h" commit -q --allow-empty -m init
mkdir -p "$gatehost/h/sub"

# Outside any git repo with no --root: fail closed on the TARGET, not the gate.
set +e
gmsg=$(cd / && python3 "$DPIPE" start F1 README.md 2>&1 >/dev/null); grc=$?
set -e
[ "$grc" -eq 2 ] && ok "stage0/start: outside a git repo exits 2 (no raw-cwd side channel)" \
  || err "expected exit 2, got $grc"
printf '%s' "$gmsg" | grep -q 'cannot resolve the host repo' \
  && ok "stage0/start: the diagnostic names the unresolvable target, not a phantom gate failure" \
  || err "wrong diagnostic outside a repo: $gmsg"

# The gate keys to the resolved root: same verdict from the repo root and a
# subdirectory (untagged -> precondition unmet in both).
set +e
r_root=$(cd "$gatehost/h" && python3 "$DPIPE" start F1 README.md 2>&1 >/dev/null); rc_root=$?
r_sub=$(cd "$gatehost/h/sub" && python3 "$DPIPE" start F1 README.md 2>&1 >/dev/null); rc_sub=$?
set -e
eq "stage0/start: identical gate verdict from repo root and subdirectory" "$rc_root" "$rc_sub"

# With a tag, the gate passes from a subdirectory too — same root, same answer.
git -C "$gatehost/h" tag v1
(cd "$gatehost/h/sub" && python3 "$DPIPE" start F1 README.md >/dev/null 2>&1) \
  && ok "stage0/start: a tagged host passes the gate from a subdirectory" \
  || err "tagged host failed the gate from a subdirectory"

if [ "$fail" -eq 0 ]; then
  printf '\nAll path-resolver checks passed.\n'; exit 0
else
  printf '\npath-resolver checks FAILED.\n' >&2; exit 1
fi

