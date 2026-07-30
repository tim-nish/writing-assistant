#!/usr/bin/env sh
# parallel-safe
# tier: full — measured over the inner ceiling (#913); end-to-end/scenario class
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
generated_by: writing-assistant@0.1.0+abc1234
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

# 1b. A draft with NO frontmatter names the FULL required schema in one finding (#143),
#     from the config schema (not hardcoded), so a fresh draft learns the set here.
printf '## Just a body\n\nNo frontmatter at all.\n' > "$work/nofm.md"
nofm=$(python3 "$LINT" "$work/nofm.md" --config-json "$work/cfg.json" 2>/dev/null || true)
printf '%s\n' "$nofm" | grep -qi 'required frontmatter fields:' \
  && ok "no-frontmatter draft names the required frontmatter set (#143)" \
  || err "no-frontmatter draft did not name the required set"
printf '%s\n' "$nofm" | grep -q 'slug' && printf '%s\n' "$nofm" | grep -q 'related' \
  && ok "the named set is the full config schema (slug…related)" \
  || err "named set is not the full schema"

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
generated_by: writing-assistant@0.1.0+abc1234
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

# 5. #160: link-shaped syntax inside inline code spans / fenced blocks is NOT a
#    dead link, while a real dead link in prose still is (surgical exemption).
cat > "$work/codelinks.md" <<'EOF'
---
slug: codelinks
title: "Code-span links are not dead links"
date: 2026-07-09
mode: canonical
language: en
summary: s.
topics: [a]
related: { projects: [], publications: [], products: [] }
generated_by: writing-assistant@0.1.0+abc1234
---

## H

Use the pattern `[one_liner](ideas/<slug>.md)` to link an idea. Fenced too:

```
see [example](fenced-missing.md)
```

But this real one is broken: [the notes](./prose-missing.md).

More at [example.com](https://example.com).
EOF
clout=$(python3 "$LINT" "$work/codelinks.md" --config-json "$work/cfg.json" 2>/dev/null || true)
printf '%s\n' "$clout" | grep -q 'prose-missing.md' \
  && ok "#160: a real dead link in prose is still flagged" \
  || err "#160: real prose dead link not flagged"
if printf '%s\n' "$clout" | grep -Eq 'ideas/<slug>.md|fenced-missing.md'; then
  err "#160: link syntax inside code (span/fence) flagged as a dead link"
else
  ok "#160: link syntax inside inline code + fenced blocks is exempt from the dead-link check"
fi

# 6. Birth record (hub 2026-07-16): an otherwise-clean canonical draft that is
#    missing the immutable `generated_by` record is a generation defect the lint
#    surfaces; a well-formed record lints clean.
cat > "$work/nobirth.md" <<'EOF'
---
slug: nobirth
title: "This draft never recorded how it was born"
date: 2026-07-09
mode: canonical
language: en
summary: s.
topics: [a]
related: { projects: [], publications: [], products: [] }
---

## H

Body more at [example.com](https://example.com).
EOF
if python3 "$LINT" "$work/nobirth.md" --config-json "$work/cfg.json" 2>/dev/null | grep -q '\[birth-record\].*generated_by'; then
  ok "missing generated_by birth record is flagged at lint"
else
  err "missing generated_by not flagged"
fi
# A malformed birth record (not <tool>@<version>+<commit>) is flagged too.
cat > "$work/badbirth.md" <<'EOF'
---
slug: badbirth
title: "This draft recorded a malformed birth record today"
date: 2026-07-09
mode: canonical
language: en
summary: s.
topics: [a]
related: { projects: [], publications: [], products: [] }
generated_by: not-a-birth-record
---

## H

Body more at [example.com](https://example.com).
EOF
if python3 "$LINT" "$work/badbirth.md" --config-json "$work/cfg.json" 2>/dev/null | grep -q '\[birth-record\]'; then
  ok "malformed generated_by is flagged at lint"
else
  err "malformed generated_by not flagged"
fi

# Trailer-vs-content consistency (Story 18.104, #695): a canonical claiming an
# attestation that disagrees with its own content is a named defect; a canonical
# carrying no trailer is out of scope; the finding is never schema-class, so the
# completion gate's #674 partition can never route it to the hard-error bucket.
cat > "$work/trailer.md" <<'EOF'
---
slug: trailer
title: "A stale attestation breaks the idempotent re-persist"
date: 2026-07-25
mode: canonical
language: en
summary: s.
topics: [a]
related: { projects: [], publications: [], products: [] }
generated_by: writing-assistant@1.0.0+abc1234
---

## H

Body more at [example.com](https://example.com).
EOF
cp "$work/trailer.md" "$work/trailer-clean.md"
# A correct attestation over this exact content: computed, never hardcoded.
python3 - "$work/trailer-clean.md" <<'EOF'
import hashlib, sys
p = sys.argv[1]
body = open(p, encoding="utf-8").read().rstrip("\n") + "\n"
sha = hashlib.sha256(body.encode("utf-8")).hexdigest()
open(p, "a", encoding="utf-8").write(
    f"\n<!-- writing-assistant: canonical-sha256={sha} -->\n")
EOF
if python3 "$LINT" "$work/trailer-clean.md" --config-json "$work/cfg.json" 2>/dev/null \
     | grep -q '\[trailer\]'; then
  err "a trailer that matches its content was flagged"
else
  ok "a matching canonical-sha256 trailer is clean (#695)"
fi
# Falsify the attestation only; the content is untouched.
sed 's/canonical-sha256=[0-9a-f]*/canonical-sha256=0000000000000000000000000000000000000000000000000000000000000000/' \
  "$work/trailer-clean.md" > "$work/trailer-stale.md"
out_trailer=$(python3 "$LINT" "$work/trailer-stale.md" --config-json "$work/cfg.json" 2>/dev/null || true)
if printf '%s' "$out_trailer" | grep -q '\[trailer\].*stale'; then
  ok "a stale canonical-sha256 trailer is flagged (#695)"
else
  err "stale trailer not flagged: $out_trailer"
fi
if printf '%s' "$out_trailer" | grep 'trailer claims' | grep -q '\[schema\]\|\[title\]'; then
  err "trailer drift reported as schema/title class — the completion gate would hard-error on it"
else
  ok "trailer drift is not schema/title class, so completion only warns (#695/#674)"
fi
# Lint reports, never repairs.
before_stale=$(cat "$work/trailer-stale.md")
python3 "$LINT" "$work/trailer-stale.md" --config-json "$work/cfg.json" >/dev/null 2>&1 || true
[ "$before_stale" = "$(cat "$work/trailer-stale.md")" ] \
  && ok "lint never auto-fixes the trailer it flags (#695)" \
  || err "lint rewrote the draft it was asked to check"
# No trailer at all ⇒ out of scope (only a claimed attestation can be wrong).
if python3 "$LINT" "$work/trailer.md" --config-json "$work/cfg.json" 2>/dev/null \
     | grep -q '\[trailer\]'; then
  err "a trailer-less canonical was flagged for trailer drift"
else
  ok "a canonical with no trailer emits no trailer finding (#695)"
fi

# --- claim-verb test is language-keyed (Story 18.108, #701) -------------------
# The heuristic was an English verb set, so it reported EVERY Japanese title as a
# bare noun phrase — including one carrying the verb 言わせる. The test is now
# declaration data; a language declaring none is skipped WITH DISCLOSURE.
mk_titled() {   # $1 basename  $2 title  $3 language
  cat > "$work/$1.md" <<EOF
---
slug: $1
title: "$2"
date: 2026-07-25
mode: canonical
language: $3
summary: s.
topics: [a]
related: { projects: [], publications: [], products: [] }
generated_by: writing-assistant@1.0.0+abc1234
---

## H

Body more at [example.com](https://example.com).
EOF
}
mk_titled ja-title "自動化に「わからない」と言わせる4つの仕組み" ja
mk_titled en-noverb "Retry configuration and setup notes" en
mk_titled en-verb "Retry storms doubled our token spend" en

ja_out=$(python3 "$LINT" "$work/ja-title.md" --config-json "$work/cfg.json" 2>"$work/ja.err" || true)
printf '%s' "$ja_out" | grep -q '\[title\].*bare noun phrase' \
  && err "#701: a JA title was still reported as a bare noun phrase" \
  || ok "#701: a JA title emits no claim-verb finding"
grep -q 'claim-verb check skipped' "$work/ja.err" \
  && ok "#701: the skip is DISCLOSED, not silent" \
  || err "#701: the skipped check was not disclosed: $(cat "$work/ja.err")"
python3 "$LINT" "$work/ja-title.md" --config-json "$work/cfg.json" >/dev/null 2>&1 \
  && ok "#701: the disclosure is not a defect (clean draft still exits 0)" \
  || err "#701: a disclosed skip made a clean draft fail"

python3 "$LINT" "$work/en-noverb.md" --config-json "$work/cfg.json" 2>/dev/null \
  | grep -q '\[title\].*bare noun phrase' \
  && ok "#701: the EN test still fires on a bare noun phrase (declaration read as data)" \
  || err "#701: the EN claim-verb check stopped working"
python3 "$LINT" "$work/en-verb.md" --config-json "$work/cfg.json" >/dev/null 2>&1 \
  && ok "#701: an EN title with a claim verb still passes" \
  || err "#701: a valid EN title was flagged"

# The length bound is language-independent: it still fires on a long JA title.
long_ja=$(python3 -c "print('自動化に'*20)")
mk_titled ja-long "$long_ja" ja
python3 "$LINT" "$work/ja-long.md" --config-json "$work/cfg.json" 2>/dev/null \
  | grep -q '\[title\].*chars (> 70)' \
  && ok "#701: the 70-char bound still applies to a JA title" \
  || err "#701: the length bound was language-scoped by mistake"

# A language whose test IS declared gets judged by it — proving the mechanism is
# data-driven rather than an en-only special case.
cat > "$work/conv.yaml" <<'EOF'
languages:
  ja:
    register: です/ます
    terminology: technical terms kept in English
    title_claim_verb:
      suffixes: [ます, せる, った]
      words: [なぜ]
EOF
python3 "$LINT" "$work/ja-title.md" --config-json "$work/cfg.json" \
  --conventions "$work/conv.yaml" >/dev/null 2>"$work/ja2.err" \
  && ok "#701: a JA title passes its OWN declared verb test (言わせる matches せる)" \
  || err "#701: a declared JA test did not judge the title: $(cat "$work/ja2.err")"
grep -q 'claim-verb check skipped' "$work/ja2.err" \
  && err "#701: a declared test still reported itself as skipped" \
  || ok "#701: no skip disclosed once the language declares a test"
mk_titled ja-nouny "自動化の設定と手順のメモ" ja
python3 "$LINT" "$work/ja-nouny.md" --config-json "$work/cfg.json" \
  --conventions "$work/conv.yaml" 2>/dev/null \
  | grep -q '\[title\].*bare noun phrase' \
  && ok "#701: under a declared JA test, a verbless JA title IS flagged" \
  || err "#701: the declared JA test never fires (a test that cannot fail is not a test)"

# The shipped declaration is what the default resolution finds — and it must
# survive the repo's stdlib YAML SUBSET parser WHOLE. Adding the verb list as a
# multi-line flow list truncated it and swallowed the `ja` entry after it, so
# adaptation reported "language 'ja' declares no register/terminology": a
# declaration file is only a declaration if the parser reads all of it.
python3 - <<'PY' && ok "#701: the shipped conventions file parses WHOLE (verb data + every language's conventions)" || err "#701: the shipped conventions declaration does not fully parse"
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ruc", "scripts/resolve-user-config.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
langs = (m.load_yaml(open("config/language-conventions.yaml", encoding="utf-8").read())
         or {}).get("languages") or {}
problems = []
if not langs.get("en", {}).get("title_claim_verb", {}).get("words"):
    problems.append("en declares no title_claim_verb words")
# Every declared language keeps the adaptation stage's own required keys — the
# regression the truncation caused was in THIS property, not in the verb data.
for code, entry in langs.items():
    for key in ("register", "terminology"):
        if not (entry or {}).get(key):
            problems.append(f"{code} lost its {key} declaration")
for p in problems:
    print("  " + p, file=sys.stderr)
sys.exit(1 if problems else 0)
PY

if [ "$fail" -eq 0 ]; then
  printf '\nAll lint-article checks passed.\n'; exit 0
else
  printf '\nlint-article checks FAILED.\n' >&2; exit 1
fi
