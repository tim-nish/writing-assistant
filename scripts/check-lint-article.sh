#!/usr/bin/env sh
# check-lint-article.sh — verify the zero-token lint script (Story 5.1):
# schema/title/pointer/heading-density/dead-link/[VERIFY] checks against the
# config `article` schema, a clean draft passing, and a seeded-defect draft
# reporting every defect kind with file/line. POSIX shell + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

LINT="$root/scripts/lint-article"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

python3 -c "import py_compile; py_compile.compile('$LINT', doraise=True)" 2>/dev/null \
  && ok "lint script compiles" || { err "lint syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

[ -x "$LINT" ] && ok "lint script is executable" || err "lint script not executable"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

cat > "$work/cfg.json" <<'EOF'
{"owner":{"site_url":"https://example.com"},
"frontmatter":{"schema":["slug","title","date","mode","language","summary","topics","related"],
"enums":{"mode":["canonical","external"],"language":["en","ja"]},
"related_keys":["projects","publications","products"]}}
EOF

# 1. A clean draft passes with exit 0 and touches no network (http link, no --check-http).
cat > "$work/clean.md" <<'EOF'
---
slug: retry-storms
title: "Retry storms doubled our token spend"
date: 2026-07-09
mode: canonical
language: en
summary: How an innocuous retry policy doubled load and what we changed.
topics: [llm-ops, reliability]
related: { projects: [], publications: [], products: [] }
---

## The retry storm

We shipped a retry policy that doubled token spend. See [dev.to](https://dev.to).

## Pointer

---
*I write about llm-ops — more at [example.com](https://example.com).*
EOF
if python3 "$LINT" "$work/clean.md" --config-json "$work/cfg.json" >"$work/clean.out" 2>"$work/clean.err"; then
  ok "clean draft lints clean (exit 0)"
else
  err "clean draft reported defects: $(cat "$work/clean.out")"
fi

# 2. A draft with one seeded defect of each kind — every kind must be reported.
#    Seeds: missing `date` (schema), bare-noun title, no site_url (pointer),
#    a >250-word heading gap, a dead relative link, a remaining [VERIFY] marker,
#    and un-stripped framework-template residue (issue #121).
cat > "$work/dirty.md" <<'EOF'
---
slug: x
title: Retry configuration and setup notes
mode: canonical
language: en
summary: A short summary.
topics: [a]
related: { projects: [], publications: [], products: [] }
---

Intro paragraph with no heading at all.

See [the notes](./does-not-exist.md) for details.

This claim is unsupported [VERIFY: no source yet] and stays in the body.

## GATE {What actually happened}                    (~120 words) [SKIP: blocker]
{(The surprise, WITH the artifact.)}
*(The shared pointer block — rendered from user config.)*
NOT PUBLISHABLE
EOF
python3 -c "print('lorem ipsum dolor '*90)" >> "$work/dirty.md"

set +e
out=$(python3 "$LINT" "$work/dirty.md" --config-json "$work/cfg.json" 2>/dev/null)
code=$?
set -e

[ "$code" -eq 1 ] && ok "seeded-defect draft exits non-zero" || err "expected exit 1, got $code"

check_code() {
  if printf '%s\n' "$out" | grep -q "\[$1\]"; then ok "reports $2 defect"; else err "missing $2 defect ([$1])"; fi
}
check_code schema   "schema (missing required field)"
check_code title    "title (bare noun phrase)"
check_code pointer  "pointer-block (site_url absent)"
check_code headings "heading-density (>250-word gap)"
check_code links    "dead-link"
check_code markers  "[VERIFY] marker"
check_code template "template residue (unfilled GATE slot)"

# 2b. Each residue form is individually reported, and code markup is exempt.
res_count=$(printf '%s\n' "$out" | grep -c '\[template\]')
[ "$res_count" -ge 5 ] && ok "all residue forms reported ({slot}, *(prompt)*, [SKIP], (~N words), NOT PUBLISHABLE)" \
  || err "expected >=5 [template] findings, got $res_count"

cat > "$work/codeok.md" <<'EOF'
---
slug: slots
title: "Slot syntax beats ad-hoc templates"
date: 2026-07-09
mode: canonical
language: en
summary: s.
topics: [a]
related: { projects: [], publications: [], products: [] }
---

## H

A filled draft may mention `{slot}` and `*(prompt)*` in inline code, or fenced:

```
## GATE {Evidence} (~120 words) [SKIP: blocker]
NOT PUBLISHABLE
```

Body more at [example.com](https://example.com).
EOF
if python3 "$LINT" "$work/codeok.md" --config-json "$work/cfg.json" 2>/dev/null | grep -q '\[template\]'; then
  err "template residue inside code markup should not be flagged"
else
  ok "code-markup slot syntax is exempt from the template check"
fi

# 3. Every reported defect carries a file:line location.
if printf '%s\n' "$out" | grep -vq "^$work/dirty.md:[0-9][0-9]*:"; then
  err "a finding is missing a file:line location"
else
  ok "every finding is reported with file:line"
fi

# 4. Schema enum enforcement: an out-of-enum value is caught.
cat > "$work/badmode.md" <<'EOF'
---
slug: y
title: "This ships a broken mode value today"
date: 2026-07-09
mode: bogus
language: en
summary: s.
topics: [a]
related: { projects: [], publications: [], products: [] }
---

## H

Body more at [example.com](https://example.com).
EOF
if python3 "$LINT" "$work/badmode.md" --config-json "$work/cfg.json" 2>/dev/null | grep -q '\[schema\].*mode'; then
  ok "out-of-enum mode value flagged"
else
  err "out-of-enum mode value not flagged"
fi

if [ "$fail" -eq 0 ]; then
  printf '\nAll lint-article checks passed.\n'; exit 0
else
  printf '\nlint-article checks FAILED.\n' >&2; exit 1
fi
