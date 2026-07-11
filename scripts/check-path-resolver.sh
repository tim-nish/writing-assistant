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
eq "repo-key: path slug of --root" \
   "$($PY repo-key --root /home/ada/work/blog)" "-home-ada-work-blog"
eq "repo-key: collapses runs of non-alnum" \
   "$($PY repo-key --root /a//b.c_d)" "-a-b-c-d"

# 4. repo-dir composes state-root/repo-key.
sr=$(XDG_STATE_HOME=/tmp/xdgstate $PY state-root)
rk=$($PY repo-key --root /home/ada/work/blog)
eq "repo-dir: state-root/repo-key" \
   "$(XDG_STATE_HOME=/tmp/xdgstate $PY repo-dir --root /home/ada/work/blog)" \
   "$sr/$rk"

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

if [ "$fail" -eq 0 ]; then
  printf '\nAll path-resolver checks passed.\n'; exit 0
else
  printf '\npath-resolver checks FAILED.\n' >&2; exit 1
fi
