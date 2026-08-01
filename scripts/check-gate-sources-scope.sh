#!/usr/bin/env sh
# parallel-safe
# tier: inner
# covers: scripts/draft_gates.py skills/draft-article/stages/stage0.md
# removal-signal: the sources gate stops rendering a scope SIZE at all (an
#   owner surface that shows the enumerated set itself rather than a number
#   standing in for it) — at that point there is no count to source and
#   nothing here to assert.
# check-gate-sources-scope.sh — the sources gate COMPUTES its own count and
# states what the scope is made of (Story 20.135, #1178).
#
# THE FAILURE THIS ASSERTS AGAINST WAS NOT A WRONG NUMBER, IT WAS AN UNSOURCED
# ONE. On 2026-08-01 the gate read "6 file(s) are declared" and the owner
# approved believing they had approved six files; six was the count of include
# GLOBS, the expansion was 358 files, and `declared_count` was a parameter the
# agent filled in. A number a gate accepts is a number it cannot vouch for, so
# what is checkable is provenance — that the rendered figure equals what the
# enumerator returns for the same root, and that no figure is rendered when
# there is no enumeration behind it.
#
# THE COMPOSITION IS CHECKED AS SEPARATELY AS IT IS RENDERED. Size and
# composition fail differently: a right count over an undescribed set still
# leaves "all declared sources" unjudgeable, which is the half the owner
# actually needed.
#
# POSIX shell + stdlib Python only.
set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

fail=0
ok()  { printf 'ok:   %s\n' "$1"; }
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
XDG_STATE_HOME="$work/state"; export XDG_STATE_HOME
XDG_CONFIG_HOME="$work/xdg";  export XDG_CONFIG_HOME

# A host whose declaration expands to a KNOWN, LOPSIDED set: 3 prose files and
# 5 code/config ones. Lopsided on purpose — an even split cannot tell the two
# figures apart if they were ever swapped.
h="$work/host"; mkdir -p "$h/docs" "$h/scripts"
: > "$h/docs/a.md"; : > "$h/docs/b.md"; : > "$h/docs/notes.txt"
: > "$h/scripts/one.sh"; : > "$h/scripts/two.sh"; : > "$h/scripts/three.py"
: > "$h/scripts/conf.yaml"; : > "$h/scripts/data.json"
python3 "$root/scripts/resolve-writing-sources.py" --root "$h" set-sources \
  >/dev/null 2>&1 <<'JSON'
[{"path": ".", "include": ["docs/**", "scripts/**"]}]
JSON

enumerated=$(python3 "$root/scripts/resolve-writing-sources.py" --root "$h" \
  files 2>/dev/null | wc -l | tr -d ' ')
[ "$enumerated" = "8" ] || { err "fixture host enumerates $enumerated file(s), expected 8"; }

report=$(python3 - "$h" "$enumerated" <<'PY'
import inspect, json, re, sys
sys.path.insert(0, "scripts")
import draft_gates as dg

h, enumerated = sys.argv[1], int(sys.argv[2])
bad = []
def need(c, m):
    if not c:
        bad.append(m)

# --- AC1/AC5: the count is COMPUTED, and it is the enumerator's ------------
scope = dg.declared_scope(h)
need(scope is not None, "declared_scope() returned nothing for a host that "
                        "declares sources — the gate has no count to render")
if scope:
    need(scope["files"] == enumerated,
         "declared_scope() counted %d file(s); `resolve-writing-sources.py "
         "files` returns %d for the same root — the gate is not counting the "
         "enumerator's set" % (scope["files"], enumerated))
    need((scope["prose"], scope["code"]) == (3, 5),
         "the prose/code split is %r, expected (3, 5) — 3 .md/.txt against 5 "
         ".sh/.py/.yaml/.json" % ((scope["prose"], scope["code"]),))

built = dg.sources_gate(repo_root=h)["items"][0]
where = built["where"]
all_effect = built["choices"][0]["effect"]

# --- AC2: BOTH render sites carry the computed figure ----------------------
for name, text in (("where", where), ("the `all` effect", all_effect)):
    need(str(enumerated) in text,
         "%s does not carry the enumerated count %d: %r" % (name, enumerated, text))
    need("3 prose" in text and "5 code/config" in text,
         "%s does not state what the scope is MADE OF — size without "
         "composition is the half the owner could not judge (AC4): %r"
         % (name, text))

# --- AC5: the DENOMINATOR is named where the count is rendered -------------
need("writing-sources.yaml" in where and "Enumerating" in where,
     "the count is rendered without naming the enumeration it was counted "
     "over — a coverage claim is admissible only over an enumeration the "
     "claimant did not receive from the party it is made to: %r" % where)

# --- AC1: NO enumeration, NO count ----------------------------------------
blind = dg.sources_gate()["items"][0]
blind_text = blind["where"] + " " + blind["choices"][0]["effect"]
# A SIZE, specifically — "Stage 0" is a stage name and not a count, so the
# predicate is a number QUANTIFYING the scope rather than any digit at all.
need(not re.search(r"\d+\s*(file|prose|code|glob)", blind_text),
     "an unenumerable scope still rendered a size — the refusal is to render "
     "NO count, never a plausible one from a weaker source: %r" % blind_text)
need("not be enumerated" in blind["where"],
     "an unenumerable scope is silent about WHY there is no count; the owner "
     "cannot tell a missing figure from a zero one: %r" % blind["where"])

# --- AC2: the caller has NO CHANNEL for a count at all ---------------------
# The strongest form of "neither render site can display a number the gate did
# not compute" is that no parameter carries one. Asserted over the SIGNATURE
# rather than by grepping the file, so the docstring may keep explaining why
# `declared_count` is gone without the explanation reading as its survival.
params = inspect.signature(dg.sources_gate).parameters
need("declared_count" not in params,
     "sources_gate still takes declared_count — the caller-supplied figure "
     "has a path back to a render site")
need(not any("count" in p.lower() for p in params),
     "sources_gate takes a count-shaped parameter (%s) — the removed one came "
     "back under another name" % ", ".join(params))

# --- AC1/AC3: the parameter cannot be re-introduced ------------------------
try:
    dg.sources_gate(11)
except ValueError as e:
    need("#1178" in str(e) and "count" in str(e).lower(),
         "a caller passing the old count is refused without being told why: "
         "%r" % str(e))
else:
    bad.append("sources_gate(11) was ACCEPTED — the agent-supplied count is "
               "back, positionally, and renders as a machine fact")

print(json.dumps(bad))
PY
) || { err "the gate did not build over the fixture host"; printf '\nFAILED.\n' >&2; exit 1; }

if python3 - "$report" <<'PY'
import json, sys
bad = json.loads(sys.argv[1])
for m in bad:
    sys.stderr.write("FAIL: %s\n" % m)
sys.exit(1 if bad else 0)
PY
then
  ok "the sources gate computes its count from the enumerator, in both render sites"
  ok "the gate states the scope's prose/code COMPOSITION beside its size"
  ok "the gate names the enumeration it counted over"
  ok "no enumeration renders NO count, and says why"
  ok "the agent-supplied count parameter cannot be re-introduced"
  ok "sources_gate carries no count-shaped parameter at all"
else
  fail=1
fi

# --- AC3: the stage text says the agent supplies no count ------------------
S0="skills/draft-article/stages/stage0.md"
if grep -q 'NO file count' "$S0" && grep -q '1178' "$S0"; then
  ok "stage0.md tells the agent to pass no file count (#1178)"
else
  err "$S0 does not say the agent supplies no count — the parameter gets re-introduced by the next author who reads only the stage text"
fi

# --- both branches still pass the SHIPPED payload validator ----------------
python3 - "$work" <<'PY'
import json, os, sys
sys.path.insert(0, "scripts")
import draft_gates as dg
json.dump(dg.sources_gate(repo_root=sys.argv[1] + "/host"),
          open(os.path.join(sys.argv[1], "counted.json"), "w"))
json.dump(dg.sources_gate(), open(os.path.join(sys.argv[1], "blind.json"), "w"))
PY
for g in counted blind; do
  if python3 scripts/validate-proposal-payload.py --require-render "$work/$g.json" \
      >/dev/null 2>"$work/$g.err"; then
    ok "the $g sources payload passes the shipped validator (budgets included)"
  else
    err "the $g sources payload is blocked: $(head -2 "$work/$g.err" | tr '\n' ' ')"
  fi
done

if [ "$fail" -eq 0 ]; then printf '\nPASSED.\n'; else printf '\nFAILED.\n' >&2; fi
exit "$fail"
