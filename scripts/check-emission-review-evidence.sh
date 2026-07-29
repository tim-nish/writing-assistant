#!/usr/bin/env sh
# tier: full — measured over the inner ceiling (#913); end-to-end/scenario class
# check-emission-review-evidence.sh — verify emission ASSERTS the "reviewed"
# half of its own "persisted, reviewed canonical" promise, as a DISCLOSURE
# (Story 18.114, #716; SPEC-platform-variants "Emission asserts the
# reviewed-canonical promise it makes"). POSIX sh + stdlib Python; every fixture
# write lands under mktemp -d.
#
# The promise is written in three spec places and only *persisted* was ever
# checked, so "reviewed" carried no mechanism (#534). This suite pins the
# mechanism AND its two hard edges:
#
#   1. It NEVER refuses. Emission exits 0 and writes the variant; the missing
#      evidence is a publish blocker, because "a promotion threshold gates what
#      surfaces by default, not what the human may act on"
#      (consulted: product-lab@<private-pin> LESSONS.md:68).
#   2. A PARENT'S review record does NOT satisfy its derivation. This is the
#      one that would silently reintroduce the defect: slugs nest
#      (`<slug>.<language>`), so a bare prefix test would accept the EN panel
#      record as the JA canonical's evidence, when "a JA canonical earns its own
#      review pass because it is a canonical, not a variant"
#      (consulted: product-lab@<private-pin> topics/articles.md:56).
#
# Also pinned: the wording is three-valued (cannot-determine, never
# "unreviewed"), and the run-workspace checkpoint's `review_evidence_class`
# (#704) is NOT consulted — it lives in a different invocation's $WS.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="$root/scripts/draft-pipeline.py"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export XDG_CONFIG_HOME="$work/xdg"
mkdir -p "$work/host" "$work/ws"

dest="$work/articles"; mkdir -p "$dest/drafts"
# The destination must be a git work tree: `_dest_repo_root` resolves the repo
# root via `git rev-parse --show-toplevel`, and the ratified layout puts
# `drafts/`, the projection dirs and `reviews/` as SIBLINGS at that root. A
# non-repo fixture would look for reviews/ inside drafts/ and grade nothing.
git init -q "$dest" 2>/dev/null || { printf 'FAIL: cannot git init the fixture destination\n' >&2; exit 1; }
cat > "$work/host/writing-sources.yaml" <<YAML
sources:
  - path: .
output:
  drafts: $dest/drafts/
YAML
repo_key=$(python3 scripts/resolve-paths.py repo-key --root "$work/host")
ppdir="$work/xdg/writing-assistant/repos/$repo_key/platform-profiles"
mkdir -p "$ppdir"
cp config/platform-profiles/devto.example.yaml "$ppdir/devto.yaml"
cp config/platform-profiles/zenn.example.yaml "$ppdir/zenn.yaml"
# Every layout dir the installed profiles declare must exist in the destination.
grep -hoE '^\s+[a-z_]+:\s+[a-z0-9_/-]+/?$' "$ppdir"/*.yaml | awk '{print $2}' \
  | grep -E '^[a-z0-9_-]+/?$' | while read -r d; do mkdir -p "$dest/$d"; done

cat > "$work/cfg.json" <<'EOF'
{"frontmatter":{"schema":["slug","title","language"]},
 "syndication":{"policy":{"en":{"mode":"canonical","variants":["devto"]},
                          "ja":{"mode":"canonical","variants":["zenn"]}},
 "variants":{"devto":{"canonical_url_base":"https://example.com/articles"},
             "zenn":{"canonical_url_base":"https://example.com/articles"}}}}
EOF

# --- the two persisted canonicals: an EN source and its JA derivation --------
cat > "$dest/drafts/retry-storms.md" <<'EOF'
---
slug: retry-storms
title: "Retry storms doubled our token spend"
date: 2026-07-09
mode: canonical
language: en
audience: en-practitioner
audience_id: en-practitioner
generated_by: writing-assistant@0.0.0-test+deadbee
summary: >
  How an innocuous retry policy tripled load and what we changed.
topics: [llm-ops, reliability]
related: { projects: [], publications: [], products: [] }
---

## The incident

The retry storm doubled token spend, and we caught it late.
EOF

cat > "$dest/drafts/retry-storms.ja.md" <<'EOF'
---
slug: retry-storms.ja
title: "リトライ暴走を止める"
date: 2026-07-09
mode: canonical
language: ja
audience: ja-practitioner
audience_id: ja-practitioner
generated_by: writing-assistant@0.0.0-test+deadbee
summary: "指数バックオフに上限を設け、予算アラートを追加した経緯をまとめました。"
topics: [llm-ops, reliability]
related: { projects: [], publications: [], products: [] }
---

## 結論

指数バックオフに上限を設け、予算アラートを追加しました。
EOF

emit() { # emit <slug> <platform> <outfile>
  python3 "$DP" variants --slug "$1" --root "$work/host" \
    --config-json "$work/cfg.json" --platforms "$2" --ws "$work/ws" \
    > "$3" 2>"$work/e-emit"
}

# --- 1. no reviews/ dir at all: blocker, no crash, emission SUCCEEDS ---------
[ ! -d "$dest/reviews" ] || err "fixture guard: reviews/ should not exist yet"
emit retry-storms.ja zenn "$work/e1.json" \
  || { err "emission must NOT refuse when review evidence is absent: $(cat "$work/e-emit")"
       printf '\nFAILED.\n' >&2; exit 1; }
ok "emission exits 0 with no reviews/ directory at all (disclosure, not refusal)"

python3 - "$work" "$dest" <<'PY' || fail=1
import json, os, sys
work, dest = sys.argv[1], sys.argv[2]
o = json.load(open(work + "/e1.json"))
bad = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: bad.append(msg)

pb = o.get("publish_blockers") or []
check(len(pb) == 1 and pb[0].get("blocker") == "review-evidence-not-found",
      "exactly one review-evidence-not-found publish blocker is reported")
check(pb and pb[0].get("slug") == "retry-storms.ja",
      "the blocker names the canonical's slug")
# It emitted anyway — the variant file exists and is reported written.
check(o.get("written") is True and len(o.get("emitted", [])) == 1,
      "the variant is still emitted and reported written")
check(os.path.isfile(o["emitted"][0]["path"]),
      "the emitted variant file exists on disk")

# Three-valued wording: cannot-determine, never a bare "unreviewed" claim.
d = (pb[0].get("detail") or "") if pb else ""
check("CANNOT-DETERMINE" in d.upper(),
      "the blocker states CANNOT-DETERMINE explicitly")
check("absence of a record is not absence of a review" in d,
      "the blocker says absence of a record is not absence of a review")
check("reviews" in d,
      "the blocker names where it looked")
sys.exit(1 if bad else 0)
PY

# --- 2. the DERIVATION'S OWN record clears the blocker ----------------------
mkdir -p "$dest/reviews"
printf '# panel\n' > "$dest/reviews/retry-storms.ja-panel-2026-07-25.md"
[ -f "$dest/reviews/retry-storms.ja-panel-2026-07-25.md" ] \
  || err "fixture guard: the derivation's own review record was not written"
emit retry-storms.ja zenn "$work/e2.json" \
  || { err "emission failed with evidence present: $(cat "$work/e-emit")"; }
python3 - "$work" <<'PY' || fail=1
import json, sys
o = json.load(open(sys.argv[1] + "/e2.json"))
cond = "publish_blockers" not in o
print(("ok:   " if cond else "FAIL: ") + "the derivation's own review record clears the blocker",
      file=sys.stdout if cond else sys.stderr)
sys.exit(0 if cond else 1)
PY

# --- 3. THE REGRESSION EDGE: a PARENT's record must NOT satisfy it ----------
# Remove the derivation's own record, leave only the EN parent's. A bare
# startswith(slug) test would wrongly accept it.
rm -f "$dest/reviews/retry-storms.ja-panel-2026-07-25.md"
printf '# panel\n' > "$dest/reviews/retry-storms-panel-2026-07-24.md"
# Vacuity guard: the fixture must genuinely hold the parent's record and NOT
# the derivation's, or the assertion below passes for the wrong reason.
[ -f "$dest/reviews/retry-storms-panel-2026-07-24.md" ] \
  || err "fixture guard: the parent's review record is missing"
[ ! -f "$dest/reviews/retry-storms.ja-panel-2026-07-25.md" ] \
  || err "fixture guard: the derivation's own record should have been removed"
emit retry-storms.ja zenn "$work/e3.json" \
  || { err "emission failed on the parent-record case: $(cat "$work/e-emit")"; }
python3 - "$work" <<'PY' || fail=1
import json, sys
o = json.load(open(sys.argv[1] + "/e3.json"))
pb = o.get("publish_blockers") or []
cond = len(pb) == 1 and pb[0].get("blocker") == "review-evidence-not-found"
msg = ("the EN parent's panel record does NOT satisfy its JA derivation "
       "(slug nesting must not be accepted as evidence)")
print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
sys.exit(0 if cond else 1)
PY

# --- 4. the parent itself IS cleared by its own record ----------------------
emit retry-storms devto "$work/e4.json" \
  || { err "EN emission failed: $(cat "$work/e-emit")"; }
python3 - "$work" <<'PY' || fail=1
import json, sys
o = json.load(open(sys.argv[1] + "/e4.json"))
cond = "publish_blockers" not in o
print(("ok:   " if cond else "FAIL: ") + "the EN canonical's own record clears its own emission",
      file=sys.stdout if cond else sys.stderr)
sys.exit(0 if cond else 1)
PY

# --- 5. the run-workspace checkpoint is NOT the substrate (#704/#716) -------
# A checkpoint asserting `reviewed: true` must NOT suppress the blocker: it
# belongs to a different invocation's workspace and emission never reads it.
cat > "$work/ws/checkpoint.json" <<'EOF'
{"stage":"review","next_stage":"done","reviewed":true,
 "review_evidence_class":"provenance-map"}
EOF
emit retry-storms.ja zenn "$work/e5.json" \
  || { err "emission failed with a checkpoint present: $(cat "$work/e-emit")"; }
python3 - "$work" <<'PY' || fail=1
import json, sys
o = json.load(open(sys.argv[1] + "/e5.json"))
pb = o.get("publish_blockers") or []
cond = len(pb) == 1 and pb[0].get("blocker") == "review-evidence-not-found"
msg = ("a workspace checkpoint claiming reviewed:true does NOT suppress the "
       "blocker (review_evidence_class is not the substrate)")
print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
sys.exit(0 if cond else 1)
PY

# --- 6. the predicate is stated where the check lives ----------------------
# The evidence convention is owner-owned and unwritten anywhere else, so the
# story requires it be stated at the check. Guard the statement, not prose.
python3 - "$root" <<'PY' || fail=1
import ast, sys
src = open(sys.argv[1] + "/scripts/draft-pipeline.py", encoding="utf-8").read()
tree = ast.parse(src)
fn = next((n for n in tree.body
           if isinstance(n, ast.FunctionDef) and n.name == "_review_evidence"), None)
bad = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: bad.append(msg)
check(fn is not None, "_review_evidence exists as the single evidence predicate")
doc = ast.get_docstring(fn) or ""
check("cannot-determine" in doc.lower(),
      "its docstring states that an empty result is cannot-determine")
# The separator constant must exist: it is what keeps nested slugs disjoint.
check("_REVIEW_RECORD_SEP" in src,
      "the record separator is a named constant, not an inline literal")
sys.exit(1 if bad else 0)
PY

if [ "$fail" -eq 0 ]; then
  printf '\nAll emission review-evidence checks passed.\n'
else
  printf '\nFAILED.\n' >&2
fi
exit "$fail"
