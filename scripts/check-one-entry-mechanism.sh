#!/usr/bin/env sh
# check-one-entry-mechanism.sh — verify Story 18.47 (#560, SPEC-article-draft-
# pipeline CAP-9 2026-07-22 #554 amendment): the #431 named-element pin is the
# DEGENERATE CASE of the free-form entry point, not a second mechanism; and
# consumption/overlap exclusion gates what is SURFACED by default, never what
# the owner may pick — a named already-consumed element is honoured.
# POSIX shell + stdlib Python only.

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

python3 -c "import py_compile; py_compile.compile('$DP', doraise=True)" 2>/dev/null \
  && ok "pipeline helper compiles" || { err "helper syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
host="$work/host"; mkdir -p "$host"; git -C "$host" init -q
printf 'sources:\n  - path: .\n' > "$host/writing-sources.yaml"

# --- 1. both entry forms resolve through the SAME path -------------------------
python3 "$DP" entry --element "lesson:retry-storm" > "$work/named.json" 2>/dev/null \
  || err "entry --element failed"
python3 "$DP" entry --request "the story of how the judge missed the retry storm" \
  > "$work/free.json" 2>/dev/null || err "entry --request failed"
python3 - "$work/named.json" "$work/free.json" <<'PYEOF' && ok "a named entry and a free-form entry take the same path — one record shape, the named case marked degenerate" || err "the two entry forms diverge"
import json, sys
a = json.load(open(sys.argv[1]))["entry"]
b = json.load(open(sys.argv[2]))["entry"]
assert set(a) - {"pinned", "request"} == set(b) - {"pinned", "request"}, (a, b)
assert a["form"] == "named-element" and b["form"] == "free-form", (a, b)
assert a["named"] == ["lesson:retry-storm"], a      # degenerate: exactly one member
assert b["named"] == [], b                          # general: none named
assert a["source_boundary"] == b["source_boundary"] == "unchanged", (a, b)
PYEOF

# --- 2. no second code path: state.element is PROJECTED from the entry ---------
python3 "$DP" stage0 F2 specs/ --root "$host" --element "cache-warmth" > "$work/s0.json" 2>/dev/null
python3 - "$work/s0.json" <<'PYEOF' && ok "the #431 pin is projected from the one entry record (state.entry -> state.element), not resolved separately" || err "state.element is not projected from the entry record"
import json, sys
st = json.load(open(sys.argv[1]))
st = st.get("run_state", st)
assert st["entry"]["form"] == "named-element", st["entry"]
assert st["entry"]["named"] == ["cache-warmth"], st["entry"]
assert st["element"]["name"] == "cache-warmth", st        # #431 guarantee preserved
assert st["entry"].get("pinned") is True, st["entry"]
PYEOF
n=$(grep -c '^def _entry_request' "$DP" || true)
[ "$n" = "1" ] && ok "exactly one entry resolver (_entry_request) — no second mechanism" \
  || err "expected exactly 1 _entry_request definition, found $n"

# --- 3. the #431 guarantees survive the generalization -------------------------
python3 "$DP" stage0 F2 specs/ --root "$host" > "$work/plain.json" 2>/dev/null
python3 - "$work/plain.json" <<'PYEOF' && ok "no entry directive: no pin, no entry record — the default surface is unchanged (#430 intact)" || err "default selection changed"
import json, sys
st = json.load(open(sys.argv[1]))
st = st.get("run_state", st)
assert "element" not in st and "entry" not in st, st
PYEOF
python3 - "$work/s0.json" "$work/plain.json" <<'PYEOF' && ok "neither entry form widens the declared-source boundary — sources are identical with and without the pin" || err "an entry form widened the source boundary"
import json, sys
a = json.load(open(sys.argv[1])); a = a.get("run_state", a)
b = json.load(open(sys.argv[2])); b = b.get("run_state", b)
assert a["sources"] == b["sources"], (a["sources"], b["sources"])
assert a["sources_raw"] == b["sources_raw"], (a, b)
PYEOF

# --- 4. exclusion gates SURFACING, never PERMISSION ---------------------------
printf '{"project_consumed_index":{"lesson:retry-storm":"plans/first-article.md"}}' > "$work/ci.json"
python3 "$DP" entry --element "lesson:retry-storm" --consumed-index "$work/ci.json" \
  > "$work/consumed.json" 2>/dev/null \
  && ok "naming an ALREADY-CONSUMED element proceeds — never refused, never an error exit" \
  || err "a named consumed element was refused (exclusion leaked into permission)"
python3 - "$work/consumed.json" <<'PYEOF' && ok "the honoured element carries the consumption disclosure (which plan consumed it), not a block" || err "honour disclosure missing"
import json, sys
d = json.load(open(sys.argv[1]))
row = d["named_elements"][0]
assert row["honoured"] is True, row
assert row["consumed_by"] == "plans/first-article.md", row
assert "surfaced by default" in row["disclosure"], row
assert "never what the owner may pick" in row["disclosure"], row
PYEOF
python3 - "$work/consumed.json" <<'PYEOF' && ok "the default surface is untouched by an honoured pick — permission semantics only (#430 unchanged)" || err "the honour path changed the default surface"
import json, sys
assert json.load(open(sys.argv[1]))["default_selection"] == "unchanged"
PYEOF
# consult's whole output OR a bare index is accepted (one consumption record)
printf '{"lesson:retry-storm":"plans/first-article.md"}' > "$work/bare.json"
python3 "$DP" entry --element "lesson:retry-storm" --consumed-index "$work/bare.json" \
  | grep -q 'consumed_by' \
  && ok "the consumed index is read from consult's output or the bare index — one consumption record, no new store" \
  || err "bare consumed index not accepted"
# an UNconsumed named element is honoured too, with no spurious disclosure
python3 "$DP" entry --element "lesson:brand-new" --consumed-index "$work/ci.json" \
  > "$work/fresh.json" 2>/dev/null
python3 - "$work/fresh.json" <<'PYEOF' && ok "an unconsumed named element is honoured with no consumption disclosure invented" || err "spurious disclosure on an unconsumed element"
import json, sys
row = json.load(open(sys.argv[1]))["named_elements"][0]
assert row["honoured"] is True and "consumed_by" not in row and "disclosure" not in row, row
PYEOF

# --- 5. the entry resolver selects nothing and writes nothing ------------------
before=$(git -C "$host" status --porcelain | wc -l)
python3 "$DP" entry --element "lesson:retry-storm" --consumed-index "$work/ci.json" >/dev/null 2>&1
after=$(git -C "$host" status --porcelain | wc -l)
[ "$before" = "$after" ] && ok "entry resolution is read-only — it selects nothing and touches no file" \
  || err "entry resolution wrote to the host tree"

# --- 6. SKILL describes entry semantics in ONE place ---------------------------
norm() { tr '\n' ' ' < "$1" | tr -s ' ' | sed 's/\*\*//g; s/`//g'; }
S=$(norm "$SKILL")
printf '%s' "$S" | grep -qiE 'degenerate case' \
  && ok "SKILL: the named-element pin is the degenerate case of the free-form entry" \
  || err "SKILL missing the degenerate-case framing"
printf '%s' "$S" | grep -qiE 'not a separate code path and not a second described mechanism' \
  && ok "SKILL: not a separate code path, not a second described mechanism" \
  || err "SKILL missing the one-mechanism rule"
printf '%s' "$S" | grep -qiE 'gates SURFACING, never PERMISSION|gates surfacing, never permission' \
  && ok "SKILL: exclusion gates surfacing, never permission" \
  || err "SKILL missing the surfacing-not-permission rule"
printf '%s' "$S" | grep -qiE 'is honoured' \
  && ok "SKILL: a named already-consumed element is honoured" \
  || err "SKILL missing the honoured-pick rule"
printf '%s' "$S" | grep -qi 'threshold-gates-surfacing-not-permission' \
  && ok "SKILL cites the governing lesson by slug" || err "SKILL missing the lesson citation"
printf '%s' "$S" | grep -qiE 'never the default surface' \
  && ok "SKILL: permission semantics only — the default surface is unchanged (#430)" \
  || err "SKILL missing the default-surface-unchanged rule"
printf '%s' "$S" | grep -qiE 'declared-source boundary is identical for both entry forms' \
  && ok "SKILL: the declared-source boundary is identical for both entry forms" \
  || err "SKILL missing the shared-boundary statement"
# exactly one place describes the entry mechanism
c=$(grep -c '^\*\*One entry mechanism' "$SKILL" || true)
[ "$c" = "1" ] && ok "exactly one entry-mechanism description in the draft SKILL" \
  || err "expected exactly one entry-mechanism block, found $c"

if [ "$fail" -eq 0 ]; then
  printf '\nAll one-entry-mechanism checks passed.\n'; exit 0
else
  printf '\none-entry-mechanism checks FAILED.\n' >&2; exit 1
fi
