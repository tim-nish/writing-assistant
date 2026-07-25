#!/usr/bin/env sh
# check-delivered-basename.sh — verify the DELIVERED basename comes from the
# profile's declared mapping, that every basename join still resolves, and that
# an illegal delivered slug is a named publish blocker (Story 18.115, #715;
# SPEC-platform-variants "The delivered basename is the platform's to constrain,
# and the profile declares the mapping"). POSIX sh + stdlib Python; every
# fixture write lands under mktemp -d.
#
# The point of the story is NOT the rename. It is that a rename alone silently
# breaks three joins that key on `<slug>.<platform>.md`, which is why the layout
# spec requires a replacement discovery mechanism rather than a partial fix
# (consulted: product-lab@34a6119 topics/articles.md:14). So the load-bearing
# assertions here are the DISCOVERY and LINT cases: they fail against a naive
# rename, and pass only because resolution is forward (slug -> name) at every
# consumer.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

DP="$root/scripts/draft-pipeline.py"
LINT="$root/scripts/lint-platform-variant"

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export XDG_CONFIG_HOME="$work/xdg"
mkdir -p "$work/host" "$work/ws"

dest="$work/articles"; mkdir -p "$dest/drafts"
git init -q "$dest" 2>/dev/null || { printf 'FAIL: cannot git init fixture dest\n' >&2; exit 1; }
cat > "$work/host/writing-sources.yaml" <<YAML
sources:
  - path: .
output:
  drafts: $dest/drafts/
YAML
repo_key=$(python3 scripts/resolve-paths.py repo-key --root "$work/host")
ppdir="$work/xdg/writing-assistant/repos/$repo_key/platform-profiles"
mkdir -p "$ppdir"
cp config/platform-profiles/devto.example.yaml "$ppdir/devto.yaml"   # NO mapping
cp config/platform-profiles/zenn.example.yaml "$ppdir/zenn.yaml"     # declares one
grep -hoE '^\s+[a-z_]+:\s+[a-z0-9_/-]+/?$' "$ppdir"/*.yaml | awk '{print $2}' \
  | grep -E '^[a-z0-9_-]+/?$' | while read -r d; do mkdir -p "$dest/$d"; done
# Review evidence for every fixture slug, so #716's blocker never confuses the
# assertions below (this suite is about the basename, not about review).
mkdir -p "$dest/reviews"

cat > "$work/cfg.json" <<'EOF'
{"frontmatter":{"schema":["slug","title","language"]},
 "syndication":{"policy":{"en":{"mode":"canonical","variants":["devto"]},
                          "ja":{"mode":"canonical","variants":["zenn"]}},
 "variants":{"devto":{"canonical_url_base":"https://example.com/articles"},
             "zenn":{"canonical_url_base":"https://example.com/articles"}}}}
EOF

# canonical <slug> <language> <audience>
canonical() {
  cat > "$dest/drafts/$1.md" <<EOF
---
slug: $1
title: "タイトル"
date: 2026-07-09
mode: canonical
language: $2
audience: $3
audience_id: $3
generated_by: writing-assistant@0.0.0-test+deadbee
summary: "要約です。"
topics: [llm-ops]
related: { projects: [], publications: [], products: [] }
---

## 結論

本文です。
EOF
  printf '# panel\n' > "$dest/reviews/$1-panel-2026-07-25.md"
}

emit() { # emit <slug> <platform> <outfile>
  python3 "$DP" variants --slug "$1" --root "$work/host" \
    --config-json "$work/cfg.json" --platforms "$2" --ws "$work/ws" \
    > "$3" 2>"$work/e-emit"
}

# --- 1. the declared mapping produces the delivered name --------------------
canonical retry-storms.ja ja ja-practitioner
emit retry-storms.ja zenn "$work/e1.json" \
  || { err "mapped emission failed: $(cat "$work/e-emit")"; printf '\nFAILED.\n' >&2; exit 1; }
python3 - "$work" "$dest" <<'PY' || fail=1
import json, os, sys
work, dest = sys.argv[1], sys.argv[2]
o = json.load(open(work + "/e1.json"))
bad = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: bad.append(msg)
p = o["emitted"][0]["path"]
check(os.path.basename(p) == "retry-storms-ja.md",
      "the delivered basename is the mapped name (retry-storms-ja.md)")
check(os.path.basename(os.path.dirname(p)) == "articles",
      "it lands in the profile's declared projection dir")
check(os.path.isfile(p), "the mapped file exists on disk")
check(not os.path.exists(os.path.join(dest, "articles", "retry-storms.ja.zenn.md")),
      "the OLD dotted delivery name is not written")
check(not os.path.exists(os.path.join(dest, "drafts", "retry-storms.ja.zenn.md")),
      "the drafts/ co-located name is not written either (delivery only)")
check("publish_blockers" not in o,
      "a legal mapped basename reports no publish blocker")
sys.exit(1 if bad else 0)
PY

# --- 2. a profile with NO declared mapping is unchanged ---------------------
canonical retry-storms en en-practitioner
emit retry-storms devto "$work/e2.json" \
  || { err "devto emission failed: $(cat "$work/e-emit")"; }
python3 - "$work" <<'PY' || fail=1
import json, os, sys
o = json.load(open(sys.argv[1] + "/e2.json"))
b = os.path.basename(o["emitted"][0]["path"])
cond = b == "retry-storms.devto.md"
print(("ok:   " if cond else "FAIL: ") +
      "a profile declaring no mapping still delivers <slug>.<platform>.md",
      file=sys.stdout if cond else sys.stderr)
sys.exit(0 if cond else 1)
PY

# --- 3. DISCOVERY: staleness finds the mapped delivery ---------------------
# Vacuity guard: the mapped file must exist and the dotted one must not, or the
# assertion cannot distinguish a working join from an empty scan.
[ -f "$dest/articles/retry-storms-ja.md" ] \
  || err "fixture guard: the mapped delivery is missing"
[ ! -f "$dest/articles/retry-storms.ja.zenn.md" ] \
  || err "fixture guard: a dotted delivery exists and would mask the test"
# Change the canonical so the emitted variant becomes stale, then require the
# staleness pass to SEE it. A naive rename reports zero variants here.
printf '\n本文を追記しました。\n' >> "$dest/drafts/retry-storms.ja.md"
python3 "$DP" variant-staleness --root "$work/host" > "$work/stale.json" 2>"$work/e-stale" \
  || { err "variant-staleness failed: $(cat "$work/e-stale")"; }
python3 - "$work" <<'PY' || fail=1
import json, os, sys
o = json.load(open(sys.argv[1] + "/stale.json"))
names = [os.path.basename(v.get("path", "")) for v in (o.get("publish_blockers") or [])]
cond = "retry-storms-ja.md" in names
msg = ("staleness discovery FINDS the profile-mapped delivery "
       "(the join a naive rename would break)")
print(("ok:   " if cond else "FAIL: ") + msg + f" -- saw {names}",
      file=sys.stdout if cond else sys.stderr)
sys.exit(0 if cond else 1)
PY

# --- 4. LINT: platform resolves from the projection dir --------------------
# `|| lint_rc=$?` and not a bare call: under `set -e` a non-zero lint would abort
# the whole suite before this case could grade it, silently dropping every case
# below. The lint exits 1 on findings and 2 when it cannot resolve a platform —
# only the latter is this case's failure.
lint_rc=0
python3 "$LINT" "$dest/articles/retry-storms-ja.md" --root "$work/host" \
  --profiles-dir "$ppdir" --dest-repo "$dest" > "$work/lint.out" 2>"$work/e-lint" \
  || lint_rc=$?
if [ "$lint_rc" -eq 2 ]; then
  err "the lint could not resolve the platform for a mapped basename: $(cat "$work/e-lint")"
else
  ok "the lint resolves the platform from the projection dir for a mapped basename"
fi
grep -q "cannot infer platform" "$work/e-lint" 2>/dev/null \
  && err "the lint still tries to parse the platform out of the basename" \
  || ok "no 'cannot infer platform' error on a mapped delivery"

# --- 5. an illegal delivered basename is a named blocker ------------------
# 5a. too short: `ab.ja` -> `ab-ja` (5 chars, below the 12 minimum)
canonical ab.ja ja ja-practitioner
emit ab.ja zenn "$work/e5a.json" \
  || { err "short-name emission must not refuse: $(cat "$work/e-emit")"; }
# 5b. illegal charset: an uppercase letter survives the mapping
canonical retry-Storms-longer.ja ja ja-practitioner
emit retry-Storms-longer.ja zenn "$work/e5b.json" \
  || { err "charset-case emission must not refuse: $(cat "$work/e-emit")"; }
python3 - "$work" <<'PY' || fail=1
import json, sys
work = sys.argv[1]
bad = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: bad.append(msg)

a = json.load(open(work + "/e5a.json"))
pa = [b for b in (a.get("publish_blockers") or [])
      if b.get("blocker") == "illegal-delivered-slug"]
check(len(pa) == 1, "a too-short delivered basename reports illegal-delivered-slug")
check(pa and "below the 12 minimum" in pa[0]["detail"],
      "the length failure names the minimum it missed")
check(pa and "illegal character" not in pa[0]["detail"],
      "a length-only failure does not also claim a charset failure")
check(a.get("written") is True,
      "an illegal delivered basename is DISCLOSED, not refused (still written)")

b = json.load(open(work + "/e5b.json"))
pb = [x for x in (b.get("publish_blockers") or [])
      if x.get("blocker") == "illegal-delivered-slug"]
check(len(pb) == 1, "an illegal-charset delivered basename reports illegal-delivered-slug")
check(pb and "illegal character" in pb[0]["detail"],
      "the charset failure says so")
check(pb and "minimum" not in pb[0]["detail"],
      "a charset-only failure does not also claim a length failure")
check(pb and pb[0].get("delivered_basename") == "retry-Storms-longer-ja",
      "the blocker names the offending delivered basename")
sys.exit(1 if bad else 0)
PY

# --- 6. the two real article names map to legal Zenn slugs ---------------
python3 - "$root" <<'PY' || fail=1
import importlib.util, re, sys
spec = importlib.util.spec_from_file_location("dp", sys.argv[1] + "/scripts/draft-pipeline.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
prof = {"packaging": {"layout": {"dir": "articles/", "basename": {
    "rule": "slug-dots-to-hyphens", "slug_pattern": r"^[a-z0-9_-]{12,50}$"}}}}
bad = []
for slug, want in (("tanuki-honest-automation.ja", "tanuki-honest-automation-ja"),
                   ("tanuki-engineering-lessons.ja", "tanuki-engineering-lessons-ja")):
    got = m._delivered_stem(slug, "zenn", prof)
    legal = bool(re.match(r"^[a-z0-9_-]{12,50}$", got))
    cond = got == want and legal
    print(("ok:   " if cond else "FAIL: ") +
          f"{slug} -> {got} ({len(got)} chars, legal={legal})",
          file=sys.stdout if cond else sys.stderr)
    if not cond: bad.append(slug)
sys.exit(1 if bad else 0)
PY

# --- 7. an unknown declared rule is an error, never a silent fallback ----
sed 's/rule: slug-dots-to-hyphens/rule: some-future-rule/' "$ppdir/zenn.yaml" \
  > "$work/zenn-bad.yaml" && mv "$work/zenn-bad.yaml" "$ppdir/zenn.yaml"
grep -q "some-future-rule" "$ppdir/zenn.yaml" \
  || err "fixture guard: the unknown-rule profile edit did not apply"
if emit retry-storms.ja zenn "$work/e7.json"; then
  err "an unknown basename rule must NOT silently fall back to the illegal name"
else
  grep -q "unknown packaging.layout.basename.rule" "$work/e-emit" \
    && ok "an unknown declared rule is refused, naming the rule" \
    || err "wrong error for an unknown rule: $(cat "$work/e-emit")"
fi

# --- 8. both discovery sites union in the forward-resolved paths ---------
python3 - "$root" <<'PY' || fail=1
import ast, sys
src = open(sys.argv[1] + "/scripts/draft-pipeline.py", encoding="utf-8").read()
tree = ast.parse(src)
lines = src.splitlines()
bad = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: bad.append(msg)
# Exact AST ranges, not text slicing: a module-level match must not be credited
# to a function that happens to sit near it.
# `_staleness_report` is the shared discovery helper `cmd_variant_staleness`
# calls; the join lives there, not in the command wrapper.
want = {"_staleness_report": False, "cmd_review_reentry": False}
for node in tree.body:
    if isinstance(node, ast.FunctionDef) and node.name in want:
        body = "\n".join(lines[node.lineno - 1:node.end_lineno])
        want[node.name] = "_delivered_variant_paths" in body
for name, found in want.items():
    check(found, f"{name} unions in the forward-resolved delivered paths")
sys.exit(1 if bad else 0)
PY

# --- 8. the identity_from_basename discriminator (#719) ------------------
python3 - "$root" <<'PY' || fail=1
import importlib.util, sys
spec = importlib.util.spec_from_file_location("dp", sys.argv[1] + "/scripts/draft-pipeline.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
bad = []
def check(cond, msg):
    print(("ok:   " if cond else "FAIL: ") + msg, file=sys.stdout if cond else sys.stderr)
    if not cond: bad.append(msg)

def prof(**layout):
    return {"packaging": {"layout": layout}}

# The discriminator is the DECLARED flag, never the presence of `dir:`. All
# four shipped profiles declare a dir; only zenn's target is externally
# imposed, so keying on the directory would report the other three falsely.
for d in ("devto/", "newsletter/", "articles/"):
    p = prof(dir=d)
    check(m._undeclared_basename_findings("x.zenn", "devto", p) == [],
          f"a profile declaring only dir: {d} reports nothing")
    check(m._delivered_slug_findings("x.zenn", "devto", p) == [],
          f"legality stays silent for dir: {d} with no identity claim")

# Identity-bearing target, no mapping: both findings, and still written.
p = prof(dir="articles/", identity_from_basename=True)
und = m._undeclared_basename_findings("tanuki-x.ja.zenn", "zenn", p)
check(len(und) == 1 and und[0]["blocker"] == "undeclared-delivered-basename",
      "identity-bearing target with no mapping reports undeclared-delivered-basename")
check(und and und[0].get("delivered_basename") == "tanuki-x.ja.zenn",
      "the disclosure names the literal basename being delivered")
cd_ = m._delivered_slug_findings("tanuki-x.ja.zenn", "zenn", p)
check(len(cd_) == 1 and cd_[0]["blocker"] == "delivered-slug-cannot-determine",
      "legality with no declared pattern is cannot-determine, not a pass")
check(cd_ and "not a pass" in cd_[0]["detail"],
      "the cannot-determine finding says so in words")

# Identity-bearing target WITH a mapping: #715 behaviour, unchanged.
p = prof(dir="articles/", identity_from_basename=True,
         basename={"rule": "slug-dots-to-hyphens",
                   "slug_pattern": r"^[a-z0-9_-]{12,50}$"})
check(m._undeclared_basename_findings("tanuki-xyz-ja", "zenn", p) == [],
      "a declared mapping silences the undeclared-basename disclosure")
check(m._delivered_slug_findings("tanuki-xyz-ja", "zenn", p) == [],
      "a legal name under a declared pattern still passes clean")
check(m._delivered_stem("tanuki-xyz.ja", "zenn", p) == "tanuki-xyz-ja",
      "the mapped stem is unchanged by this story")
sys.exit(1 if bad else 0)
PY

# --- 9. the shipped examples declare the flag exactly where it is true ----
if grep -q "identity_from_basename: true" "$root/config/platform-profiles/zenn.example.yaml"; then
  echo "ok:   the shipped zenn example declares identity_from_basename"
else
  err "the shipped zenn example must declare identity_from_basename"
fi
for other in devto newsletter-email web-archive; do
  if grep -q "identity_from_basename" "$root/config/platform-profiles/$other.example.yaml"; then
    err "$other must NOT declare identity_from_basename (its dir is our own choice)"
  else
    echo "ok:   $other does not claim an identity-bearing target"
  fi
done

if [ "$fail" -eq 0 ]; then
  printf '\nAll delivered-basename checks passed.\n'
else
  printf '\nFAILED.\n' >&2
fi
exit "$fail"
