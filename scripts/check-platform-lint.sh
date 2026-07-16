#!/usr/bin/env sh
# check-platform-lint.sh — verify the profile-parameterized platform lint
# (Story 16.6, SPEC-platform-variants CAP-5): a mechanical, zero-LLM lint of an
# emitted variant against its platform profile, reporting each defect file/line;
# validator convergence with the emitter; the layout-existence check against the
# output.drafts destination repo; lint output in $WS. POSIX sh + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

LINT="$root/scripts/lint-platform-variant"
DP="$root/scripts/draft-pipeline.py"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$LINT', doraise=True)" 2>/dev/null \
  && ok "lint compiles" || { err "lint syntax error"; printf '\nFAILED.\n' >&2; exit 1; }
[ -x "$LINT" ] && ok "lint is executable" || err "lint not executable"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
export XDG_CONFIG_HOME="$work/xdg"
mkdir -p "$work/host"
repo_key=$(python3 scripts/resolve-paths.py repo-key --root "$work/host")
ppdir="$work/xdg/writing-assistant/repos/$repo_key/platform-profiles"
mkdir -p "$ppdir"
cp config/platform-profiles/devto.example.yaml "$ppdir/devto.yaml"
cp config/platform-profiles/zenn.example.yaml "$ppdir/zenn.yaml"

cat > "$work/cfg.json" <<'EOF'
{"frontmatter":{"schema":["slug","title","language"],"related_keys":["projects","publications","products"]},
"syndication":{"policy":{"en":{"mode":"canonical","variants":["devto"]},
"ja":{"mode":"external","variants":["zenn"]}},
"variants":{"devto":{"canonical_url_base":"https://example.com/articles"}}}}
EOF
cat > "$work/en.md" <<'EOF'
---
slug: retry-storms
title: A real claim about retries
date: 2026-07-09
mode: canonical
language: en
summary: A short summary.
topics: [llm-ops, reliability]
---
# Body

A claim.
EOF

mkdir -p "$work/o"

# 1. Validator convergence (#206/NFR18): a variant the pipeline emits passes its
#    own lint — the packaging step and the lint read the same profile values.
python3 "$DP" variants "$work/en.md" --config-json "$work/cfg.json" \
  --root "$work/host" --out "$work/o" --platforms devto >/dev/null
if python3 "$LINT" "$work/o/retry-storms.devto.md" --root "$work/host" --ws "$work" >/dev/null 2>&1; then
  ok "a pipeline-emitted variant passes its own lint (validator convergence)"
else
  err "emitted variant failed its own lint: $(python3 "$LINT" "$work/o/retry-storms.devto.md" --root "$work/host" 2>&1)"
fi

# 1b. Lint output lands in $WS.
[ -f "$work/platform-lint.devto.json" ] \
  && ok "lint output lands in \$WS" || err "no lint output in \$WS"

# 2. Seeded defect: tags over the profile cap → reported with file/line.
sed 's/^tags:.*/tags: a, b, c, d, e/' "$work/o/retry-storms.devto.md" > "$work/toomany.devto.md"
out=$(python3 "$LINT" "$work/toomany.devto.md" --root "$work/host" 2>&1 || true)
printf '%s' "$out" | grep -Eq 'toomany.devto.md:[0-9]+: tags has 5 entries; profile caps at 4' \
  && ok "seeded tag-cap defect reported with file/line" || err "tag-cap defect wrong: $out"

# 3. Frontmatter schema: a missing profile-declared field is a defect.
grep -v '^canonical_url:' "$work/o/retry-storms.devto.md" > "$work/nocu.devto.md"
python3 "$LINT" "$work/nocu.devto.md" --root "$work/host" 2>&1 \
  | grep -q "missing profile-declared field 'canonical_url'" \
  && ok "missing frontmatter field reported" || err "missing-field check wrong"

# 4. Malformed canonical_url reported.
sed 's#^canonical_url:.*#canonical_url: not-a-url#' "$work/o/retry-storms.devto.md" > "$work/badcu.devto.md"
python3 "$LINT" "$work/badcu.devto.md" --root "$work/host" 2>&1 \
  | grep -q "not a well-formed" && ok "malformed canonical_url reported" || err "canonical_url check wrong"

# 5. Visual treatment: a Zenn variant with a RAW (un-commented) Mermaid fence
#    fails; the packaging step's HTML-commented output passes.
cat > "$work/raw.zenn.md" <<'EOF'
---
title: "x"
emoji: "📝"
type: "tech"
topics: ["a"]
published: false
---

body

```mermaid
graph TD; A-->B
```
EOF
python3 "$LINT" "$work/raw.zenn.md" --root "$work/host" 2>&1 \
  | grep -q 'not HTML-commented' && ok "raw Mermaid in a html-comment-blocked profile is a defect" \
  || err "visuals check wrong"

# 6. Layout existence against the output.drafts DESTINATION repo (never the host):
#    a declared target dir absent from the destination is a defect naming the
#    profile; present → no defect (repo structure is authoritative).
python3 "$LINT" "$work/o/retry-storms.devto.md" --platform zenn --root "$work/host" \
  --dest-repo "$work/nodest" 2>&1 | grep -q 'absent from the destination repo' \
  && ok "missing layout dir in the destination repo is a defect (profile is the defect)" \
  || err "layout-existence defect wrong"
mkdir -p "$work/dest/articles"; cp "$work/o/retry-storms.devto.md" "$work/dest/ok.zenn.md"
if python3 "$LINT" "$work/dest/ok.zenn.md" --root "$work/host" --dest-repo "$work/dest" 2>&1 \
     | grep -q 'target directory'; then
  err "layout dir present but still flagged"
else
  ok "present layout dir passes (destination repo structure is authoritative)"
fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll platform-lint checks passed.\n'; exit 0
else
  printf '\nplatform-lint checks FAILED.\n' >&2; exit 1
fi
