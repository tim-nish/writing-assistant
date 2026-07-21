#!/usr/bin/env sh
# check-frameworks.sh — verify the shared framework conventions, config-bound
# frontmatter, and shared pointer block (Story 2.1). POSIX shell + stdlib Python.
#
# Maps to the four ACs: (1) conventions documented; (2) frontmatter is config-
# bound and renders both canonical and mode:external with no hardcoded site
# schema; (3) the pointer block is drawn from config with state-dependent /
# conditional lines and is byte-identical from one shared template; (4) an
# unfilled GATE (evidence or pointer block) reads as not-publishable.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

CONV="skills/draft-article/frameworks/CONVENTIONS.md"
RPB="scripts/render-pointer-block.py"
RFM="scripts/render-frontmatter.py"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }
has() { if grep -q -- "$1" "$2"; then ok "$3"; else err "missing $3"; fi; }

# 0. Renderers compile.
for s in "$RPB" "$RFM"; do
  python3 -c "import py_compile; py_compile.compile('$root/$s', doraise=True)" 2>/dev/null \
    && ok "compiles: $s" || { err "syntax error: $s"; }
done

# AC1: conventions documented.
[ -f "$CONV" ] && ok "present: $CONV" || err "missing $CONV"
has '{slot}'   "$CONV" "slot syntax {slot}"
has '(prompt)' "$CONV" "prompt convention *(prompt)*"
has 'targets, not limits' "$CONV" "lengths are targets not limits"
has 'GATE'     "$CONV" "GATE marking"
has 'not publishable' "$CONV" "unfilled GATE = not publishable rule"

# --- fixture config (mirrors the example structure; distinct identity) ------
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
cat > "$work/cfg.json" <<'JSON'
{"owner":{"name":"Ada","site_name":"ada.dev","site_url":"https://ada.dev","focus_areas":"engines"},
 "pointer_block":{"template":"---\n*I write about {focus_areas} — more at [{site_name}]({site_url}).*\n*{related_line}*\n*{newsletter_line}*\n{counterpart_line}\n",
   "newsletter":{"status":"coming-soon","rss_url":"https://ada.dev/rss","follow_url":"https://ada.dev/follow","capture_url":"https://ada.dev/sub"},
   "lines":{"related":"Related: [{title}]({url})","newsletter_coming_soon":"RSS [{rss_url}] follow [{follow_url}]","newsletter_live":"Subscribe [{capture_url}]","ja_counterpart":"日本語版は Zenn: {url}","en_counterpart":"English: [{title}]({url})"}},
 "frontmatter":{"schema":["slug","title","date","mode","language","summary","topics","related"],"related_keys":["projects","publications","products"]},
 "syndication":{"policy":{"en":{"mode":"canonical","variants":["devto"]},"ja":{"mode":"external","variants":["zenn"]}},"variants":{"devto":{"canonical_url_base":"https://ada.dev/articles"},"zenn":{"external_record_max_lines":20}}}}
JSON
RPBX="python3 $root/$RPB --config-json $work/cfg.json"
RFMX="python3 $root/$RFM --config-json $work/cfg.json"

# AC2: config-bound frontmatter, both modes, no hardcoded site schema.
$RFMX --language en > "$work/fm_en"
grep -q '^mode: canonical' "$work/fm_en" && ok "frontmatter EN: mode canonical" || err "EN mode wrong"
grep -q '^syndication:' "$work/fm_en" && ok "frontmatter EN: syndication block present" || err "EN syndication missing"
grep -q 'canonical_url: https://ada.dev/articles/{slug}' "$work/fm_en" \
  && ok "frontmatter EN: canonical_url from config (not hardcoded)" || err "EN canonical_url not config-derived"
$RFMX --language ja > "$work/fm_ja"
grep -q '^mode: external' "$work/fm_ja" && ok "frontmatter JA: mode external" || err "JA mode wrong"
grep -q 'body forbidden' "$work/fm_ja" && ok "frontmatter JA: body-forbidden note" || err "JA note missing"
# fields come from config.schema, in order
printf 'slug\ntitle\ndate\nmode\nlanguage\nsummary\ntopics\nrelated\n' > "$work/want_fields"
grep -oE '^(slug|title|date|mode|language|summary|topics|related):' "$work/fm_en" | sed 's/:$//' > "$work/got_fields"
[ "$(cat "$work/got_fields")" = "$(cat "$work/want_fields")" ] \
  && ok "frontmatter fields + order come from config schema" || err "frontmatter fields diverge from config schema"

# AC3: pointer block from config, state-dependent + conditional, shared template.
$RPBX --language en > "$work/pb_cs"
grep -q 'I write about engines' "$work/pb_cs" && ok "pointer: identity from config" || err "pointer identity wrong"
grep -q 'RSS \[https://ada.dev/rss\]' "$work/pb_cs" && ok "pointer: coming-soon newsletter line" || err "coming-soon line wrong"
$RPBX --language en --newsletter-status live > "$work/pb_live"
grep -q 'Subscribe \[https://ada.dev/sub\]' "$work/pb_live" && ok "pointer: live newsletter line (state-dependent)" || err "live line wrong"
grep -q 'RSS ' "$work/pb_live" && err "live variant still shows RSS line" || ok "pointer: live suppresses RSS line"
# related + counterpart are conditional
grep -q 'Related:' "$work/pb_cs" && err "related line shown with no related input" || ok "pointer: related omitted when absent"
$RPBX --language en --related-title T --related-url http://u --counterpart-url http://z > "$work/pb_full"
grep -q 'Related: \[T\](http://u)' "$work/pb_full" && ok "pointer: related emitted when supplied" || err "related missing when supplied"
grep -q '日本語版は Zenn: http://z' "$work/pb_full" && ok "pointer: EN draft -> JA counterpart line" || err "counterpart line wrong"
$RPBX --language ja --counterpart-url http://e > "$work/pb_ja"
grep -q 'English: ' "$work/pb_ja" && ok "pointer: JA draft -> EN counterpart line" || err "JA->EN counterpart wrong"
# byte-identical shared template: the first two lines (separator + identity) match across drafts
h1=$(sed -n '1,2p' "$work/pb_cs"); h2=$(sed -n '1,2p' "$work/pb_full")
[ "$h1" = "$h2" ] && ok "pointer: shared template renders byte-identical header across drafts" || err "pointer header drifted"

# AC4: unfilled GATE reads as not-publishable.
# (a) pointer GATE with missing identity
set +e
out=$(printf '{"owner":{},"pointer_block":{"template":"x"}}' | python3 "$root/$RPB" --config-json -); rc=$?
set -e
{ [ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q 'NOT PUBLISHABLE'; } \
  && ok "unfilled pointer GATE -> NOT PUBLISHABLE marker + exit 3" || err "pointer GATE not flagged"

# (a2) unconsumed STANDING line: template drops the always-standing newsletter
# line (no {newsletter_line} placeholder) -> NOT PUBLISHABLE + exit 3, never a
# silent drop (spec §3; #493).
NEWS_DROP='{"owner":{"focus_areas":"e","site_name":"s","site_url":"u"},"pointer_block":{"template":"---\n*{focus_areas}*\n","newsletter":{"status":"coming-soon","rss_url":"r","follow_url":"f"},"lines":{"newsletter_coming_soon":"RSS {rss_url}"}}}'
set +e
out=$(printf '%s' "$NEWS_DROP" | python3 "$root/$RPB" --config-json -); rc=$?
set -e
{ [ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q 'NOT PUBLISHABLE'; } \
  && ok "unconsumed newsletter line -> NOT PUBLISHABLE + exit 3 (no silent drop)" || err "dropped newsletter line not GATEd"

# (b2) unconsumed SUPPLIED related line: template lacks {related_line} but a
# related title+url are supplied (making related a standing line) -> GATE.
REL_DROP='{"owner":{"focus_areas":"e","site_name":"s","site_url":"u"},"pointer_block":{"template":"---\n*{focus_areas}*\n*{newsletter_line}*\n","newsletter":{"status":"coming-soon","rss_url":"r","follow_url":"f"},"lines":{"newsletter_coming_soon":"RSS {rss_url}","related":"Related {title} {url}"}}}'
set +e
out=$(printf '%s' "$REL_DROP" | python3 "$root/$RPB" --config-json - --related-title T --related-url http://u); rc=$?
set -e
{ [ "$rc" -eq 3 ] && printf '%s' "$out" | grep -q 'NOT PUBLISHABLE'; } \
  && ok "unconsumed supplied related line -> NOT PUBLISHABLE + exit 3" || err "dropped supplied related line not GATEd"

# (c2) same template as (b2), but related NOT supplied: the conditional line
# resolved to empty and its placeholder is legitimately absent -> NO gate.
set +e
out=$(printf '%s' "$REL_DROP" | python3 "$root/$RPB" --config-json -); rc=$?
set -e
{ [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q 'NOT PUBLISHABLE' && printf '%s' "$out" | grep -q 'RSS r'; } \
  && ok "empty conditional line (absent placeholder) -> no gate (verified vs rendered output)" || err "empty conditional line wrongly GATEd"

# (d2) the shipped-shape template (mirrors user-config.example.yaml; carries
# {newsletter_line}) renders with no new gate — unchanged behaviour.
grep -q 'NOT PUBLISHABLE' "$work/pb_cs" && err "example-shape template spuriously GATEd" \
  || ok "example-shape template (has {newsletter_line}) renders with no new gate"

# (b) an evidence GATE still showing its prompt is detectable by inspection
printf '## GATE {Evidence}\n{(A result... This slot empty = not publishable.)}\n' > "$work/draft.md"
grep -Eq '## GATE \{[^}]+\}' "$work/draft.md" && grep -q '{(' "$work/draft.md" \
  && ok "unfilled evidence GATE identifiable from marked slot + retained prompt" || err "evidence GATE not detectable"

if [ "$fail" -eq 0 ]; then
  printf '\nAll framework checks passed.\n'; exit 0
else
  printf '\nframework checks FAILED.\n' >&2; exit 1
fi
