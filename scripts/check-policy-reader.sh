#!/usr/bin/env sh
# check-policy-reader.sh — verify the gateway-backed policy reader (Story
# 13.72, SPEC-policy-source-seam CAP-2 as amended 2026-07-18: served
# transport, same CLI contract). POSIX shell + stdlib Python only.
#
# Covers: the identical CLI contract (pin line, `=== FILE @ sha` sections,
# `N: text` lines) now composed entirely from gateway MCP payloads via the
# WRITING_ASSISTANT_GATEWAY_CMD test seam (stub server under fixtures/);
# ZERO filesystem reads under any hub path (the consumer holds NO hub path
# at all — Story 13.73: the policy_source block is the presence toggle
# `enabled: true`); the code whitelist and exit-5 refusals unchanged; served
# misses as answers (exit 0), distinguishable from unavailability; exit 11
# one-liner when the gateway is unreachable (old 12 collapses into it);
# surface_names (Story 18.16): list-topics enumerates and whole-GLOSSARY
# composes on a current gateway, with the exit-13 gaps kept ONLY as the
# older-gateway fallback (tools/list lacks surface_names); exit 10 for an
# absent toggle or `enabled: false`;
# exit 4 for a malformed block INCLUDING the retired path/track/topics keys
# (the resolver's migration notice relayed, never silently honored).

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

RDR="scripts/read-policy-source.py"
STUB="scripts/fixtures/policy-gateway-stub.py"
PY="python3 $root/$RDR"
SHA=8f3c2d1e4a5b6c7d8e9f0a1b2c3d4e5f60718293

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$root/$RDR', doraise=True)" 2>/dev/null \
  && ok "reader compiles" || { err "reader syntax error"; printf '\nFAILED.\n' >&2; exit 1; }
python3 -c "import py_compile; py_compile.compile('$root/$STUB', doraise=True)" 2>/dev/null \
  && ok "gateway stub compiles" || { err "stub syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# --- fixture: gateway-served content; NO hub path exists anywhere ------------
# The policy_source block is the presence toggle (13.73) — the config carries
# no filesystem location at all. Every passing read below is therefore proof
# of zero hub filesystem reads: there is nothing named to read — all content
# arrives from the stub gateway.
cat > "$work/fixture.json" <<JSON
{
  "pin": "product-lab@$SHA",
  "lessons": [
    ["LESSONS.md", 3, "report-trust-is-structural: enforce by mechanism. #ops"],
    ["LESSONS.md", 4, "consult-first: surface the miss with the question. #seam"],
    ["LESSONS.md", 7, "run-budget: wall-clock exemptions are explicit. #ops"]
  ],
  "topics": {
    "eval-alpha": [
      ["topics/eval-alpha.md", 1, "# eval-alpha"],
      ["topics/eval-alpha.md", 2, "decision: alpha holds."]
    ],
    "unrelated": [
      ["topics/unrelated.md", 1, "# unrelated"]
    ]
  },
  "glossary": {
    "report-trust": [["GLOSSARY.md", 2, "report-trust: trust is structural."]],
    "consult-first": [["GLOSSARY.md", 5, "consult-first: surface the miss."]]
  },
  "surface": {
    "topics": ["eval-alpha", "unrelated"],
    "glossary": ["report-trust", "consult-first"]
  }
}
JSON

host="$work/host"
mkdir -p "$host"
cat > "$host/writing-sources.yaml" <<'YAML'
sources:
  - path: .
output:
  drafts: articles/drafts/
policy_source:
  enabled: true
YAML

WRITING_ASSISTANT_GATEWAY_CMD="python3 $root/$STUB $work/fixture.json"
export WRITING_ASSISTANT_GATEWAY_CMD

# --- 1. Whitelist: static allowlist, no gateway, no filesystem ----------------
wl=$($PY --root "$host" whitelist)
echo "$wl" | grep -qx 'GLOSSARY.md' && echo "$wl" | grep -qx 'LESSONS.md' \
  && ok "whitelist names GLOSSARY.md and LESSONS.md" \
  || err "whitelist missing base files: $wl"
echo "$wl" | grep -q 'q_a' && err "whitelist leaked a q_a path" || ok "no q_a path in whitelist"

# --- 2. Pin: gateway payload verbatim ----------------------------------------
got=$($PY --root "$host" pin)
[ "$got" = "product-lab@$SHA" ] && ok "pin is the gateway's pin, verbatim" \
  || err "pin was '$got', expected product-lab@$SHA"

# --- 3. Read: pin header + pinned, line-numbered sections from payloads -------
out=$($PY --root "$host" read --only LESSONS.md)
echo "$out" | head -1 | grep -qx "pin: product-lab@$SHA" && ok "read leads with the pin" \
  || err "read did not lead with the pin"
echo "$out" | grep -qx "=== LESSONS.md @ $SHA" && ok "file sections carry the pin's sha" \
  || err "LESSONS section header missing/unpinned"
echo "$out" | grep -qx '3: report-trust-is-structural: enforce by mechanism. #ops' \
  && ok "content keeps the gateway's true line numbers (file:line@commit quotable)" \
  || err "line numbering missing or rewritten"
echo "$out" | grep -qx '7: run-budget: wall-clock exemptions are explicit. #ops' \
  && ok "non-consecutive served lines pass through at their own numbers" \
  || err "served line 7 lost"

# --- 4. Per-run topic selection via the gateway (Story 13.35 semantics) -------
rt=$($PY --root "$host" read --topics eval-alpha.md --only LESSONS.md topics/eval-alpha.md)
printf '%s\n' "$rt" | grep -qx "=== topics/eval-alpha.md @ $SHA" \
  && printf '%s\n' "$rt" | grep -qx '2: decision: alpha holds.' \
  && ok "read --topics serves the whole selected topic thread from the gateway" \
  || err "topic thread not served: $rt"
printf '%s' "$rt" | grep -q 'unrelated' && err "unselected topic leaked" \
  || ok "only the per-run selection is served"

# --- 5. Refusal by code: unchanged (exit 5), before any gateway call ----------
set +e; msg=$($PY --root "$host" read --only q_a/secret.md 2>&1 >/dev/null); rc=$?; set -e
[ "$rc" -eq 5 ] && printf '%s' "$msg" | grep -q 'refused' \
  && ok "q_a/ read refused (exit 5), regardless of arguments" \
  || err "q_a read: rc=$rc msg='$msg'"
set +e; $PY --root "$host" read --only ../../etc/hostname >/dev/null 2>&1; rc=$?; set -e
[ "$rc" -eq 5 ] && ok "path traversal refused (exit 5)" || err "traversal rc=$rc"
set +e; $PY --root "$host" read --only topics/unrelated.md >/dev/null 2>&1; rc=$?; set -e
[ "$rc" -eq 5 ] && ok "topic outside the per-run selection refused (whitelist, not existence)" \
  || err "non-selected topic rc=$rc"
set +e; $PY --root "$host" read --topics a.md b.md c.md >/dev/null 2>&1; rc=$?; set -e
[ "$rc" -eq 5 ] && ok "read --topics refuses >2 files (exit 5, cap code-enforced)" || err "cap not enforced: rc=$rc"
set +e; $PY --root "$host" read --topics ../q_a/secret.md >/dev/null 2>&1; rc=$?; set -e
[ "$rc" -eq 5 ] && ok "read --topics refuses a non-basename (exit 5)" || err "non-basename accepted: rc=$rc"

# --- 6. surface_names: list-topics enumerates, read composes whole GLOSSARY ----
# tsurezure-gateway#41 shipped surface_names (bounded enumeration, identifiers
# only); the reader adopts it (Story 18.16) so the exit-13 degradation is gone
# on a current gateway. The cite grammar is preserved: the composed GLOSSARY
# section carries the gateway's own line numbers, one `=== GLOSSARY.md @ sha`.
lt=$($PY --root "$host" list-topics)
printf '%s\n' "$lt" | grep -qx 'eval-alpha' && printf '%s\n' "$lt" | grep -qx 'unrelated' \
  && ok "list-topics enumerates topic identifiers via surface_names (no exit 13)" \
  || err "list-topics did not enumerate: $lt"

gout=$($PY --root "$host" read --only GLOSSARY.md)
printf '%s\n' "$gout" | head -1 | grep -qx "pin: product-lab@$SHA" \
  && printf '%s\n' "$gout" | grep -qx "=== GLOSSARY.md @ $SHA" \
  && printf '%s\n' "$gout" | grep -qx '2: report-trust: trust is structural.' \
  && printf '%s\n' "$gout" | grep -qx '5: consult-first: surface the miss.' \
  && ok "read composes whole GLOSSARY from surface_names + glossary_entry (cites preserved)" \
  || err "whole-GLOSSARY not composed: $gout"

# The composed GLOSSARY section is line-sorted (file's true order), single header
[ "$(printf '%s\n' "$gout" | grep -c '=== GLOSSARY.md')" -eq 1 ] \
  && [ "$(printf '%s\n' "$gout" | grep -n '^2:' | cut -d: -f1)" \
       -lt "$(printf '%s\n' "$gout" | grep -n '^5:' | cut -d: -f1)" ] \
  && ok "whole GLOSSARY is one section, entries in true line order" \
  || err "GLOSSARY composition not single/ordered: $gout"

# Default read (GLOSSARY + LESSONS) now serves both — exit-13 degradation closed
dout=$($PY --root "$host" read)
printf '%s\n' "$dout" | head -1 | grep -qx "pin: product-lab@$SHA" \
  && printf '%s\n' "$dout" | grep -qx "=== GLOSSARY.md @ $SHA" \
  && printf '%s\n' "$dout" | grep -qx "=== LESSONS.md @ $SHA" \
  && ok "default read serves GLOSSARY and LESSONS together (no exit 13)" \
  || err "default read did not serve both sections: $dout"

# --- 6b. Older gateway lacking surface_names: exit-13 fallback preserved -------
# tools/list omits surface_names → the reader degrades to the named gap, one
# line, never a file read (degrade, don't crash for a pre-#41 gateway).
cat > "$work/old-fixture.json" <<JSON
{
  "pin": "product-lab@$SHA",
  "tools": ["glossary_entry", "lessons_index", "topic_thread", "policy_lookup"],
  "lessons": [["LESSONS.md", 3, "x"]],
  "glossary": {"report-trust": [["GLOSSARY.md", 2, "y"]]},
  "surface": {"topics": ["eval-alpha"], "glossary": ["report-trust"]}
}
JSON
OLDCMD="python3 $root/$STUB $work/old-fixture.json"
set +e; msg=$(WRITING_ASSISTANT_GATEWAY_CMD="$OLDCMD" $PY --root "$host" list-topics 2>&1 >/dev/null); rc=$?; set -e
[ "$rc" -eq 13 ] && [ "$(printf '%s\n' "$msg" | wc -l)" -eq 1 ] \
  && printf '%s' "$msg" | grep -q 'cannot enumerate topics' \
  && ok "older gateway: list-topics falls back to exit 13, one line naming the gap" \
  || err "list-topics fallback: rc=$rc msg='$msg'"
set +e; msg=$(WRITING_ASSISTANT_GATEWAY_CMD="$OLDCMD" $PY --root "$host" read 2>&1 >/dev/null); rc=$?; set -e
[ "$rc" -eq 13 ] && [ "$(printf '%s\n' "$msg" | wc -l)" -eq 1 ] \
  && printf '%s' "$msg" | grep -q 'GLOSSARY.md whole' \
  && ok "older gateway: whole-GLOSSARY read falls back to exit 13, one line" \
  || err "whole-GLOSSARY fallback: rc=$rc msg='$msg'"

# --- 7. Served miss: an answer under the pin (exit 0), not unavailability -----
cat > "$work/miss-fixture.json" <<JSON
{"pin": "product-lab@$SHA", "lessons": [], "topics": {}}
JSON
set +e
mout=$(WRITING_ASSISTANT_GATEWAY_CMD="python3 $root/$STUB $work/miss-fixture.json" \
       $PY --root "$host" read --only LESSONS.md 2>"$work/miss.err"); rc=$?
set -e
[ "$rc" -eq 0 ] && echo "$mout" | head -1 | grep -qx "pin: product-lab@$SHA" \
  && echo "$mout" | grep -qx 'miss: LESSONS.md' \
  && [ ! -s "$work/miss.err" ] \
  && ok "gateway miss: exit 0, pin + 'miss: FILE' — a served answer" \
  || err "miss handling: rc=$rc out='$mout'"

# --- 8. Gateway unreachable: exit 11, exactly one unavailable line ------------
set +e
msg=$(WRITING_ASSISTANT_GATEWAY_CMD="$work/no-such-gateway-binary" \
      $PY --root "$host" pin 2>&1 >/dev/null); rc=$?
set -e
[ "$rc" -eq 11 ] && [ "$(printf '%s\n' "$msg" | wc -l)" -eq 1 ] \
  && printf '%s' "$msg" | grep -q 'policy_source unavailable: gateway unreachable' \
  && ok "unreachable gateway: exit 11, one 'gateway unreachable' line" \
  || err "unreachable: rc=$rc msg='$msg'"
set +e
msg=$(WRITING_ASSISTANT_GATEWAY_CMD="false" \
      $PY --root "$host" read --only LESSONS.md 2>&1 >/dev/null); rc=$?
set -e
[ "$rc" -eq 11 ] && printf '%s' "$msg" | grep -q 'gateway unreachable' \
  && ok "gateway dies mid-session: exit 11, never a partial/hung read" \
  || err "dead gateway: rc=$rc msg='$msg'"

# --- 9. Unset/disabled (10) / malformed incl. retired keys (4) ----------------
mkdir -p "$work/unset"; printf 'sources:\n  - path: .\n' > "$work/unset/writing-sources.yaml"
set +e; msg=$($PY --root "$work/unset" pin 2>&1 >/dev/null); rc=$?; set -e
[ "$rc" -eq 10 ] && [ "$(printf '%s\n' "$msg" | wc -l)" -eq 1 ] \
  && printf '%s' "$msg" | grep -q 'policy_source unavailable' \
  && ok "unset block: exit 10, one unavailable line" || err "unset: rc=$rc msg='$msg'"

# enabled: false — same degrade as unset (exit 10), never an error
mkdir -p "$work/off"
printf 'sources:\n  - path: .\npolicy_source:\n  enabled: false\n' > "$work/off/writing-sources.yaml"
set +e; msg=$($PY --root "$work/off" pin 2>&1 >/dev/null); rc=$?; set -e
[ "$rc" -eq 10 ] && [ "$(printf '%s\n' "$msg" | wc -l)" -eq 1 ] \
  && printf '%s' "$msg" | grep -q 'policy_source unavailable' \
  && ok "enabled: false — exit 10, one unavailable line (same degrade as unset)" \
  || err "enabled false: rc=$rc msg='$msg'"

cat > "$host/writing-sources.yaml" <<'YAML'
sources:
  - path: .
policy_source:
  enabled: true
  track: eval
YAML
set +e; msg=$($PY --root "$host" read --only LESSONS.md 2>&1 >/dev/null); rc=$?; set -e
[ "$rc" -eq 4 ] && printf '%s' "$msg" | grep -q 'policy_source.track' \
  && ok "leftover track key: reader refuses (exit 4), never silently applies it" \
  || err "leftover track: rc=$rc msg='$msg'"

# The RETIRED path key (13.73): exit 4 with the resolver's migration notice
# relayed — never silently honored, never joined into the filesystem.
cat > "$host/writing-sources.yaml" <<'YAML'
sources:
  - path: .
policy_source:
  path: ../no-such-hub
YAML
set +e; msg=$($PY --root "$host" pin 2>&1 >/dev/null); rc=$?; set -e
[ "$rc" -eq 4 ] && printf '%s' "$msg" | grep -q 'policy_source.path' \
  && printf '%s' "$msg" | grep -qi 'retired' \
  && printf '%s' "$msg" | grep -qi 'gateway owns the hub location' \
  && ok "retired path key: exit 4, migration notice relayed (never honored)" \
  || err "retired path key: rc=$rc msg='$msg'"

# Restore the toggle for the zero-reads section below.
mkdir -p "$work/plain-dir"; printf 'x\n' > "$work/plain-dir/GLOSSARY.md"
cat > "$host/writing-sources.yaml" <<'YAML'
sources:
  - path: .
policy_source:
  enabled: true
YAML
got=$($PY --root "$host" pin)
[ "$got" = "product-lab@$SHA" ] \
  && ok "toggle present + gateway up: served (12 retired, never emitted)" \
  || err "toggle + gateway: got '$got'"

# --- 10. Zero hub reads, read-only: nothing under any local path is touched ---
sleep 1  # mtime granularity
stamp="$work/stamp"; touch "$stamp"
$PY --root "$host" read --only LESSONS.md >/dev/null
$PY --root "$host" whitelist >/dev/null
changed=$(find "$work/plain-dir" -newer "$stamp" -type f | wc -l)
[ "$changed" -eq 0 ] && ok "read-only: no file under the declared path created or modified" \
  || err "reader touched $changed file(s) under the declared path"
grep -rqn 'policy_repo\|rev-parse\|glob.glob\|os.path.isdir\|os.path.isfile\|os.path.exists' "$root/$RDR" \
  && err "reader still carries direct-filesystem policy code" \
  || ok "no direct-filesystem policy code paths remain in the reader (no path-existence checks)"

if [ "$fail" -eq 0 ]; then
  printf '\nAll policy-reader checks passed.\n'; exit 0
else
  printf '\npolicy-reader checks FAILED.\n' >&2; exit 1
fi
