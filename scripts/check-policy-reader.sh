#!/usr/bin/env sh
# check-policy-reader.sh — verify the bounded, pinned, read-only policy reader
# (Story 14.2, SPEC-policy-source-seam CAP-2). POSIX shell + stdlib Python only.
#
# Covers: the code whitelist (GLOSSARY + LESSONS + ≤2 track-matched topics);
# refusal of q_a/ and any other out-of-whitelist path (exit 5, by code);
# symlink-escape candidates never become readable; the product-lab@<commit>
# pin; the distinct unavailable exit codes (10 unset / 11 missing path /
# 12 not a git repo) with exactly one stderr line; and read-only-ness (no
# file under the policy path created or modified by a read).

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

RDR="scripts/read-policy-source.py"
PY="python3 $root/$RDR"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$root/$RDR', doraise=True)" 2>/dev/null \
  && ok "reader compiles" || { err "reader syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# --- fixture: a policy repo with recall surface + q_a/ ------------------------
plab="$work/product-lab"
mkdir -p "$plab/topics" "$plab/q_a"
printf '# Glossary\n\nwriting-assistant: the article engine.\n' > "$plab/GLOSSARY.md"
printf '# Lessons\n\nreport-trust-is-structural: enforce by mechanism.\n' > "$plab/LESSONS.md"
printf '# eval-alpha\n' > "$plab/topics/eval-alpha.md"
printf '# eval-beta\n'  > "$plab/topics/eval-beta.md"
printf '# eval-gamma\n' > "$plab/topics/eval-gamma.md"
printf '# unrelated\n'  > "$plab/topics/unrelated.md"
printf 'SECRET: never readable\n' > "$plab/q_a/secret.md"
git -C "$plab" init -q
git -C "$plab" -c user.email=t@t -c user.name=t add -A
git -C "$plab" -c user.email=t@t -c user.name=t commit -qm init
sha=$(git -C "$plab" rev-parse HEAD)

host="$work/host"
mkdir -p "$host"
cat > "$host/writing-sources.yaml" <<'YAML'
sources:
  - path: .
output:
  drafts: articles/drafts/
policy_source:
  path: ../product-lab
  track: eval
YAML

# --- 1. Whitelist: base files + track-matched topics, capped at 2 -------------
wl=$($PY --root "$host" whitelist)
echo "$wl" | grep -qx 'GLOSSARY.md' && echo "$wl" | grep -qx 'LESSONS.md' \
  && ok "whitelist includes GLOSSARY.md and LESSONS.md" \
  || err "whitelist missing base files: $wl"
n_topics=$(echo "$wl" | grep -c '^topics/' || true)
[ "$n_topics" -eq 2 ] && ok "3 matching topics capped at 2" \
  || err "expected 2 topic entries, got $n_topics: $wl"
echo "$wl" | grep -qx 'topics/eval-alpha.md' && echo "$wl" | grep -qx 'topics/eval-beta.md' \
  && ok "cap keeps sorted-first matches (eval-alpha, eval-beta)" \
  || err "unexpected topic selection: $wl"
echo "$wl" | grep -q 'q_a' && err "whitelist leaked a q_a path" || ok "no q_a path in whitelist"

# --- 2. Pin ---------------------------------------------------------------------
got=$($PY --root "$host" pin)
[ "$got" = "product-lab@$sha" ] && ok "pin is product-lab@<rev-parse HEAD>" \
  || err "pin was '$got', expected product-lab@$sha"

# --- 3. Read: pin header + per-file pinned, line-numbered sections ---------------
out=$($PY --root "$host" read)
echo "$out" | head -1 | grep -qx "pin: product-lab@$sha" && ok "read leads with the pin" \
  || err "read did not lead with the pin"
echo "$out" | grep -qx "=== GLOSSARY.md @ $sha" && ok "file sections carry the same pin" \
  || err "GLOSSARY section header missing/unpinned"
echo "$out" | grep -q '^3: writing-assistant: the article engine.' \
  && ok "content is line-numbered (file:line@commit quotable)" \
  || err "line numbering missing"
echo "$out" | grep -q 'SECRET' && err "read leaked q_a content" || ok "read emitted no q_a content"

# --- 4. Refusal by code: q_a/, arbitrary paths ------------------------------------
set +e; msg=$($PY --root "$host" read --only q_a/secret.md 2>&1 >/dev/null); rc=$?; set -e
[ "$rc" -eq 5 ] && printf '%s' "$msg" | grep -q 'refused' \
  && ok "q_a/ read refused (exit 5), regardless of arguments" \
  || err "q_a read: rc=$rc msg='$msg'"
set +e; $PY --root "$host" read --only ../../etc/hostname >/dev/null 2>&1; rc=$?; set -e
[ "$rc" -eq 5 ] && ok "path traversal refused (exit 5)" || err "traversal rc=$rc"
set +e; $PY --root "$host" read --only topics/unrelated.md >/dev/null 2>&1; rc=$?; set -e
[ "$rc" -eq 5 ] && ok "existing but non-matched topic refused (whitelist, not existence)" \
  || err "non-matched topic rc=$rc"

# --- 5. Symlink escape never becomes readable --------------------------------------
mkdir -p "$work/outside"; printf 'OUTSIDE\n' > "$work/outside/leak.md"
ln -s "$work/outside/leak.md" "$plab/topics/evil.md"
cat > "$host/writing-sources.yaml" <<'YAML'
sources:
  - path: .
output:
  drafts: articles/drafts/
policy_source:
  path: ../product-lab
  topics: [evil.md]
YAML
out=$($PY --root "$host" read)
echo "$out" | grep -q 'OUTSIDE' && err "symlink escape leaked content" \
  || ok "symlink escaping the policy root is not readable"
echo "$out" | grep -q '^absent: topics/evil.md' && ok "escape reported as absent, not followed" \
  || err "escape not reported"
rm "$plab/topics/evil.md"

# --- 6. Explicit topics override beats track; no track/topics = base only -----------
cat > "$host/writing-sources.yaml" <<'YAML'
sources:
  - path: .
policy_source:
  path: ../product-lab
  track: eval
  topics: [unrelated.md]
YAML
wl=$($PY --root "$host" whitelist)
echo "$wl" | grep -qx 'topics/unrelated.md' && [ "$(echo "$wl" | grep -c '^topics/')" -eq 1 ] \
  && ok "explicit topics: overrides track matching" || err "override failed: $wl"
cat > "$host/writing-sources.yaml" <<'YAML'
sources:
  - path: .
policy_source:
  path: ../product-lab
YAML
wl=$($PY --root "$host" whitelist)
[ "$(echo "$wl" | grep -c '^topics/')" -eq 0 ] \
  && ok "no track/topics: GLOSSARY + LESSONS only (still a valid run)" \
  || err "expected no topics: $wl"

# --- 7. Distinct unavailable statuses, one stderr line each -------------------------
mkdir -p "$work/unset"; printf 'sources:\n  - path: .\n' > "$work/unset/writing-sources.yaml"
set +e; msg=$($PY --root "$work/unset" pin 2>&1 >/dev/null); rc=$?; set -e
[ "$rc" -eq 10 ] && [ "$(printf '%s\n' "$msg" | wc -l)" -eq 1 ] \
  && printf '%s' "$msg" | grep -q 'policy_source unavailable' \
  && ok "unset block: exit 10, one unavailable line" || err "unset: rc=$rc msg='$msg'"

mkdir -p "$work/ghost"
printf 'sources:\n  - path: .\npolicy_source:\n  path: ../nowhere\n' > "$work/ghost/writing-sources.yaml"
set +e; msg=$($PY --root "$work/ghost" pin 2>&1 >/dev/null); rc=$?; set -e
[ "$rc" -eq 11 ] && [ "$(printf '%s\n' "$msg" | wc -l)" -eq 1 ] \
  && ok "missing path: exit 11, one unavailable line" || err "missing path: rc=$rc msg='$msg'"

mkdir -p "$work/notgit/plaindir"
printf 'sources:\n  - path: .\npolicy_source:\n  path: ../notgit-plab\n' > "$work/notgit/writing-sources.yaml"
mkdir -p "$work/notgit-plab"; printf 'x\n' > "$work/notgit-plab/GLOSSARY.md"
set +e; msg=$($PY --root "$work/notgit" pin 2>&1 >/dev/null); rc=$?; set -e
[ "$rc" -eq 12 ] && [ "$(printf '%s\n' "$msg" | wc -l)" -eq 1 ] \
  && ok "not a git repo: exit 12, one unavailable line" || err "not-git: rc=$rc msg='$msg'"

# --- 8. Read-only: a read changes nothing under the policy path ---------------------
cat > "$host/writing-sources.yaml" <<'YAML'
sources:
  - path: .
policy_source:
  path: ../product-lab
  track: eval
YAML
sleep 1  # ensure mtime granularity
stamp="$work/stamp"; touch "$stamp"
$PY --root "$host" read >/dev/null
$PY --root "$host" whitelist >/dev/null
changed=$(find "$plab" -newer "$stamp" -type f | wc -l)
[ "$changed" -eq 0 ] && ok "read-only: no file under the policy path created or modified" \
  || err "reader touched $changed file(s) under the policy path"

# --- Per-run topic selection (Story 13.35, SPEC-policy-topic-at-draft CAP-2) --
# list-topics: names only, never content.
lt=$($PY --root "$host" list-topics)
printf '%s\n' "$lt" | grep -qx 'unrelated.md' && printf '%s\n' "$lt" | grep -qx 'eval-gamma.md' \
  && ok "list-topics lists every topics/*.md basename" || err "list-topics incomplete: $lt"
printf '%s' "$lt" | grep -q '#' && err "list-topics leaked file content" \
  || ok "list-topics prints names only (no content)"

# read --topics BUILDS the whitelist (overrides config track), still capped.
rt=$($PY --root "$host" read --topics unrelated.md)
printf '%s' "$rt" | grep -q '=== topics/unrelated.md' \
  && ok "read --topics reads the per-run selection (config track overridden)" \
  || err "read --topics did not read the selected topic"
printf '%s' "$rt" | grep -q 'eval-alpha' && err "config-track topic leaked into a --topics read" \
  || ok "read --topics excludes the config-track topics"
printf '%s' "$rt" | grep -q '=== GLOSSARY.md' && ok "GLOSSARY + LESSONS still always read" \
  || err "base files missing from --topics read"

# Cap and basename rules enforced in code (exit 5).
set +e; $PY --root "$host" read --topics eval-alpha.md eval-beta.md eval-gamma.md >/dev/null 2>&1; rc=$?; set -e
[ "$rc" -eq 5 ] && ok "read --topics refuses >2 files (exit 5, cap code-enforced)" || err "cap not enforced: rc=$rc"
set +e; $PY --root "$host" read --topics ../q_a/secret.md >/dev/null 2>&1; rc=$?; set -e
[ "$rc" -eq 5 ] && ok "read --topics refuses a non-basename (exit 5)" || err "non-basename accepted: rc=$rc"

if [ "$fail" -eq 0 ]; then
  printf '\nAll policy-reader checks passed.\n'; exit 0
else
  printf '\npolicy-reader checks FAILED.\n' >&2; exit 1
fi
