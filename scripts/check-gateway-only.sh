#!/usr/bin/env sh
# check-gateway-only.sh — gateway-only regression suite (Story 13.74,
# SPEC-policy-source-seam CAP-2 success clause as amended 2026-07-18, #366).
# POSIX shell + stdlib Python only.
#
# Enforces mechanically that the gateway-only decision survives future
# changes:
#
#   1. STATIC SCAN — no writing-assistant code path reads a recall-surface
#      file directly. Rule (deterministic, zero false positives by design):
#      a hub-file name (GLOSSARY.md / LESSONS.md / topics/*.md) within 3
#      lines of a file-access call site (open(/read_text/read_bytes/
#      readlines/Path(/git -C/cat/sed -n/subprocess) is a violation.
#      Exempt from the scan: fixtures/ (they BUILD fixture hubs), check-*.sh
#      harnesses (same), and two named files where hub names are labels,
#      never paths — scripts/read-policy-source.py (the gateway MCP client;
#      its zero-direct-filesystem property is asserted separately by
#      check-policy-reader.sh section 10) and scripts/fixtures/
#      policy-gateway-stub.py. The scanner takes target dirs as arguments so
#      the suite can prove it FAILS on a seeded violation (self-test below).
#   2. CONFIG SCAN — no onboarded repo's machine-global writing-sources.yaml
#      carries a policy_source path key (the consumer holds no hub path,
#      13.73); the resolver rejects a path key with the named retired-key
#      error.
#   3. STOPPED-GATEWAY END-TO-END — with the gateway command pointing at a
#      nonexistent binary and hub-shaped CANARY trees planted under and
#      beside the host root with unreadable (chmod 000) files, the reader
#      degrades to exit 11 with the single documented line and no output.
#      What this proves: the toggle-only config names no path, so any
#      resurrected direct-read code would have to derive one — the canaries
#      sit at the historically plausible locations, and an open() on them
#      raises EACCES, which would surface as a different exit/extra stderr.
#      Combined with the static scan (no access call sites exist near hub
#      names anywhere in scripts/ or skills/), this is the strongest
#      portable zero-hub-reads assertion without strace.
#   4. DOCTOR — gateway-access-doctor.py resolves the log like the
#      gateway's resolveLogPath, windows/filters entries, and cross-checks
#      `consulted:` receipts against log entries in BOTH directions
#      (matched / unmatched-log-entry / unmatched-receipt fixtures).

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

RDR="scripts/read-policy-source.py"
RES="scripts/resolve-writing-sources.py"
DOC="scripts/gateway-access-doctor.py"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

for f in "$RDR" "$RES" "$DOC"; do
  python3 -c "import py_compile; py_compile.compile('$root/$f', doraise=True)" 2>/dev/null \
    || { err "$f syntax error"; printf '\nFAILED.\n' >&2; exit 1; }
done
ok "reader, resolver, doctor compile"

work=$(mktemp -d); trap 'chmod -R u+rwX "$work" 2>/dev/null; rm -rf "$work"' EXIT

# --- 1. Static scan: no direct recall-surface reads in scripts/ or skills/ ----
cat > "$work/scan.py" <<'PY'
"""Static gateway-only scan (rule documented in check-gateway-only.sh).
Usage: scan.py DIR [DIR ...] — exit 1 listing file:line for each violation."""
import os, re, sys

HUB = re.compile(r"GLOSSARY\.md|LESSONS\.md|topics/\S*\.md|topics/\*")
ACCESS = re.compile(
    r"\bopen\(|read_text|read_bytes|readlines\(|with open|\bPath\(|"
    r"git\s+-C\b|\bcat\s|sed\s+-n|subprocess")
WINDOW = 3
SKIP_DIRS = {"fixtures", "__pycache__", ".git"}
# Hub names are labels here, never paths (rationale in the harness header):
ALLOW = {"read-policy-source.py", "policy-gateway-stub.py"}

violations = []
for top in sys.argv[1:]:
    for dirpath, dirnames, filenames in os.walk(top):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in sorted(filenames):
            if name in ALLOW or (name.startswith("check-") and name.endswith(".sh")):
                continue
            path = os.path.join(dirpath, name)
            try:
                with open(path, encoding="utf-8", errors="replace") as fh:
                    lines = fh.read().splitlines()
            except OSError:
                continue
            for i, line in enumerate(lines):
                if not HUB.search(line):
                    continue
                lo, hi = max(0, i - WINDOW), min(len(lines), i + WINDOW + 1)
                for j in range(lo, hi):
                    m = ACCESS.search(lines[j])
                    if m:
                        violations.append(
                            f"{path}:{i + 1}: hub-file name within {WINDOW} lines "
                            f"of file-access call site ({m.group(0).strip()!r} "
                            f"at line {j + 1})")
                        break

if violations:
    for v in violations:
        print("VIOLATION:", v)
    sys.exit(1)
sys.exit(0)
PY

if scan_out=$(python3 "$work/scan.py" "$root/scripts" "$root/skills" 2>&1); then
  ok "static scan: no direct recall-surface read in scripts/ or skills/"
else
  err "static scan found direct reads:
$scan_out"
fi

# Self-test: the scan MUST fail on a seeded direct read (proves it can catch).
mkdir -p "$work/seeded"
cat > "$work/seeded/bad-helper.py" <<'PYV'
import os
def load_policy(hub):
    # a resurrected direct read of the recall surface
    with open(os.path.join(hub, "LESSONS.md")) as fh:
        return fh.readlines()
PYV
set +e; sout=$(python3 "$work/scan.py" "$work/seeded"); rc=$?; set -e
[ "$rc" -eq 1 ] && printf '%s' "$sout" | grep -q 'bad-helper.py:4' \
  && ok "scan self-test: seeded direct read caught, offending file:line named" \
  || err "scan self-test failed: rc=$rc out='$sout'"
# Indirect form: cat via subprocess against a config-derived hub path.
mkdir -p "$work/seeded2"
cat > "$work/seeded2/bad-cat.py" <<'PYV'
import subprocess
def load(hub):
    return subprocess.run(["cat", hub + "/GLOSSARY.md"], capture_output=True)
PYV
set +e; sout=$(python3 "$work/scan.py" "$work/seeded2"); rc=$?; set -e
[ "$rc" -eq 1 ] && printf '%s' "$sout" | grep -q 'bad-cat.py' \
  && ok "scan self-test: subprocess-cat form caught" \
  || err "scan self-test (subprocess form): rc=$rc out='$sout'"

# --- 2. Config scan: no policy_source path key in any onboarded repo ----------
cat > "$work/cfgscan.py" <<'PY'
"""Fail if any machine-global writing-sources.yaml carries policy_source.path.
Usage: cfgscan.py REPOS_DIR — tanuki test-host entries are skipped."""
import os, re, sys

repos = sys.argv[1]
bad = []
if os.path.isdir(repos):
    for entry in sorted(os.listdir(repos)):
        if "-tanuki-" in entry:
            continue  # disposable tanuki loop test hosts
        cfg = os.path.join(repos, entry, "writing-sources.yaml")
        if not os.path.isfile(cfg):
            continue
        with open(cfg, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
        in_block = False
        for n, line in enumerate(lines, 1):
            if re.match(r"^policy_source\s*:", line):
                in_block = True
                continue
            if in_block:
                if line.strip() and not line[:1].isspace():
                    in_block = False
                elif re.match(r"^\s+path\s*:", line):
                    bad.append(f"{cfg}:{n}")
for b in bad:
    print("VIOLATION:", b, "— policy_source carries a filesystem path (retired, 13.73)")
sys.exit(1 if bad else 0)
PY

if cout=$(python3 "$work/cfgscan.py" "${XDG_CONFIG_HOME:-$HOME/.config}/writing-assistant/repos" 2>&1); then
  ok "config scan: no onboarded repo carries a policy_source path key"
else
  err "config scan:
$cout"
fi
# Self-test: a path-carrying config is caught.
mkdir -p "$work/repos/some-host"
printf 'sources:\n  - path: .\npolicy_source:\n  path: ../product-lab\n' \
  > "$work/repos/some-host/writing-sources.yaml"
set +e; cout=$(python3 "$work/cfgscan.py" "$work/repos"); rc=$?; set -e
[ "$rc" -eq 1 ] && printf '%s' "$cout" | grep -q 'some-host/writing-sources.yaml:4' \
  && ok "config-scan self-test: seeded path key caught at file:line" \
  || err "config-scan self-test: rc=$rc out='$cout'"

# The resolver names the retired key on a path-carrying fixture.
set +e
msg=$(python3 "$root/$RES" --root "$work/repos/some-host" policy-source 2>&1 >/dev/null); rc=$?
set -e
[ "$rc" -eq 4 ] && printf '%s' "$msg" | grep -q 'policy_source.path' \
  && printf '%s' "$msg" | grep -qi 'retired' \
  && ok "resolver rejects a path key with the named retired-key error (exit 4)" \
  || err "resolver on path key: rc=$rc msg='$msg'"

# --- 3. Stopped gateway: generic degrade, zero hub reads ----------------------
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
# Canary hub-shaped trees at the historically plausible locations: under the
# host root and beside it (the legacy `../product-lab` relative default).
for canary in "$host/policy-hub" "$work/product-lab"; do
  mkdir -p "$canary/topics"
  printf 'canary\n' > "$canary/GLOSSARY.md"
  printf 'canary\n' > "$canary/LESSONS.md"
  printf 'canary\n' > "$canary/topics/eval.md"
  chmod 000 "$canary/GLOSSARY.md" "$canary/LESSONS.md" "$canary/topics/eval.md"
done

set +e
out=$(WRITING_ASSISTANT_GATEWAY_CMD="$work/no-such-gateway-binary" \
      python3 "$root/$RDR" --root "$host" read --only LESSONS.md 2>"$work/e3"); rc=$?
set -e
lines=$(wc -l < "$work/e3")
[ "$rc" -eq 11 ] && [ -z "$out" ] && [ "$lines" -eq 1 ] \
  && grep -q 'policy_source unavailable: gateway unreachable' "$work/e3" \
  && ok "stopped gateway: exit 11, empty stdout, the one degrade line" \
  || err "stopped gateway: rc=$rc out='$out' stderr='$(cat "$work/e3")'"
# Unreadable canaries drew no error: nothing attempted an open() on them.
grep -qi 'permission\|EACCES\|policy-hub\|product-lab' "$work/e3" \
  && err "reader touched a canary hub file (EACCES surfaced)" \
  || ok "canary hubs untouched: no EACCES, no canary path in output"

# --- 4. Doctor: log resolution, windowing, two-direction receipt check --------
SHA=8f3c2d1e4a5b6c7d8e9f0a1b2c3d4e5f60718293
OTHER=1111111111111111111111111111111111111111
log="$work/access.jsonl"
cat > "$log" <<JSON
{"ts":"2026-07-18T10:00:00.000Z","consumer":"writing-assistant","tool":"lessons_index","realms_granted":["owner"],"files_served":["LESSONS.md"],"lines_served":3,"pin":"product-lab@$SHA","decision":"allow","config_version":"b4b149321eae"}
{"ts":"2026-07-18T10:00:01.000Z","consumer":"claude-code","tool":"policy_lookup","realms_granted":["owner"],"files_served":["GLOSSARY.md"],"lines_served":9,"pin":"product-lab@$SHA","decision":"allow","config_version":"b4b149321eae"}
{"ts":"2026-07-17T09:00:00.000Z","consumer":"writing-assistant","tool":"topic_thread","realms_granted":["owner"],"files_served":[],"lines_served":0,"pin":"product-lab@$OTHER","decision":"deny","config_version":"b4b149321eae"}
JSON
DOCTOR="python3 $root/$DOC --log $log --consumer writing-assistant"

out=$($DOCTOR --since 2026-07-18T00:00:00Z)
printf '%s\n' "$out" | grep -q '^1 entry for consumer=writing-assistant' \
  && printf '%s' "$out" | grep -q 'tool=lessons_index' \
  && ! printf '%s' "$out" | grep -q 'claude-code' \
  && ! printf '%s' "$out" | grep -q "$OTHER" \
  && ok "doctor windows by consumer and --since; summary carries tool/pin/config_version" \
  || err "doctor windowing: $out"

# matched receipts: both directions clean, exit 0 under --strict
printf 'consulted: product-lab@%s — LESSONS.md:3 → t1\n' "$SHA" > "$work/r-match"
set +e; out=$($DOCTOR --since 2026-07-18T00:00:00Z --receipts "$work/r-match" --strict); rc=$?; set -e
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'cross-check ok' \
  && ok "matched receipts: two-direction cross-check clean (exit 0 --strict)" \
  || err "matched receipts: rc=$rc out='$out'"

# unmatched receipt: pin never logged -> named, exit 1 under --strict
printf 'consulted: product-lab@%s — LESSONS.md:3 → t1\n' "$OTHER" > "$work/r-orphan"
set +e; out=$($DOCTOR --since 2026-07-18T00:00:00Z --receipts "$work/r-orphan" --strict); rc=$?; set -e
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "UNMATCHED RECEIPT: pin product-lab@$OTHER" \
  && ok "unmatched receipt pin: reported, exit 1 under --strict" \
  || err "unmatched receipt: rc=$rc out='$out'"

# unmatched log entry: served read with no receipt -> named, exit 1 --strict;
# a generic-mode `consulted: none` receipt claims nothing.
printf 'consulted: none (policy_source unavailable)\n' > "$work/r-none"
set +e; out=$($DOCTOR --since 2026-07-18T00:00:00Z --receipts "$work/r-none" --strict); rc=$?; set -e
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'UNMATCHED LOG ENTRY:' \
  && printf '%s' "$out" | grep -q '0 pinned consulted line(s), 1 generic' \
  && ok "unmatched log entry vs generic receipts: reported, exit 1 under --strict" \
  || err "unmatched log entry: rc=$rc out='$out'"
# without --strict the same mismatch reports but exits 0
set +e; $DOCTOR --since 2026-07-18T00:00:00Z --receipts "$work/r-none" >/dev/null; rc=$?; set -e
[ "$rc" -eq 0 ] && ok "mismatch without --strict: reported, exit 0" \
  || err "non-strict mismatch rc=$rc"

# log resolution via the operator config's statePath (resolveLogPath mirror)
mkdir -p "$work/state"; cp "$log" "$work/state/access.jsonl"
printf '{"statePath": "%s"}\n' "$work/state" > "$work/gwcfg.json"
out=$(python3 "$root/$DOC" --gateway-config "$work/gwcfg.json" \
      --consumer writing-assistant --since 2026-07-18T00:00:00Z)
printf '%s' "$out" | grep -q "$work/state/access.jsonl" \
  && printf '%s\n' "$out" | grep -q '^1 entry' \
  && ok "log path resolves from operator config statePath (resolveLogPath mirror)" \
  || err "statePath resolution: $out"

# read-only: the doctor never mutates the log
sum_before=$(cksum "$log"); $DOCTOR --receipts "$work/r-match" >/dev/null || true
sum_after=$(cksum "$log")
[ "$sum_before" = "$sum_after" ] && ok "doctor is read-only: log byte-identical after runs" \
  || err "doctor modified the access log"

if [ "$fail" -eq 0 ]; then
  printf '\nAll gateway-only checks passed.\n'; exit 0
else
  printf '\ngateway-only checks FAILED.\n' >&2; exit 1
fi
