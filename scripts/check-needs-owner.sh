#!/usr/bin/env sh
# parallel-safe
# tier: full — measured over the inner ceiling (#913); end-to-end/scenario class
# covers: scripts/fixtures/needs-owner/inline-subordinate-premise.md scripts/fixtures/needs-owner/tanuki-run-confabulated-premise.md scripts/gate_premise.py scripts/validate-fact-sheet.py scripts/validate-needs-owner.py
# check-needs-owner.sh — verify the NEEDS-OWNER list, its schema, and the strict
# partition from the fact sheet (Story 3.3). POSIX shell + stdlib Python.

set -eu

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
  printf 'FAIL: not inside a git repository\n' >&2; exit 1;
}
cd "$root"

VNO="scripts/validate-needs-owner.py"
VFS="scripts/validate-fact-sheet.py"
fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok()  { printf 'ok:   %s\n' "$1"; }

# 0. Validator compiles.
python3 -c "import py_compile; py_compile.compile('$root/$VNO', doraise=True)" 2>/dev/null \
  && ok "validator compiles" || { err "validator syntax error"; printf '\nFAILED.\n' >&2; exit 1; }

# 1./1a. The harvest-skill documentation assertions retired with the skill
# (#1182/Story 20.147) — the validator's own behavior below is the contract.

# --- fixtures --------------------------------------------------------------
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
NO() { python3 "$root/$VNO" "$1" >/dev/null 2>&1; }   # exit 0 = valid
reason() { python3 "$root/$VNO" "$1" 2>&1; }

cat > "$work/ok.md" <<'EOF'
# Fact sheet: demo
- Throughput rose 2x / bench.md:4@a1b2c3d / result
- Chose JAX / a1b2c3d / decision

# NEEDS-OWNER
- The win is what I would lead with / no artifact in declared sources / significance
- Reviewers keep asking about leakage / owner's framing / significance
EOF

# 2. A well-formed partitioned doc validates.
NO "$work/ok.md" && ok "valid harvest doc passes (schema + partition)" || err "valid doc rejected"

# 3. Schema: entries carry context (not bare strings); TOPIC is a closed set.
printf '# Fact sheet: x\n\n# NEEDS-OWNER\n- just a bare claim\n' > "$work/bare.md"
reason "$work/bare.md" | grep -q 'malformed' && ok "reject: bare string (needs CANDIDATE / REASON / TOPIC)" || err "bare string accepted"
printf '# Fact sheet: x\n\n# NEEDS-OWNER\n- A claim / a reason / musings\n' > "$work/topic.md"
reason "$work/topic.md" | grep -q 'invalid TOPIC' && ok "reject: TOPIC outside the interview categories" || err "bad TOPIC accepted"
# #145: tradeoff and audience are now valid TOPICs (they are the interview's q4/q5 topics).
printf '# Fact sheet: x\n\n# NEEDS-OWNER\n- what we gave up / owner framing / tradeoff\n- who this is for / owner framing / audience\n' > "$work/newtopics.md"
NO "$work/newtopics.md" && ok "accept: tradeoff + audience TOPICs (#145)" || err "tradeoff/audience TOPIC rejected"

# 4. Strict partition: a candidate cannot also be a fact-sheet CLAIM.
cat > "$work/overlap.md" <<'EOF'
# Fact sheet: x
- Chose JAX / a1b2c3d / decision

# NEEDS-OWNER
- Chose JAX / already sourced above / opinion
EOF
reason "$work/overlap.md" | grep -q 'double-counted' && ok "reject: candidate also on the fact sheet (mutual exclusion)" || err "double-count allowed"

# 5. No duplicate candidates within NEEDS-OWNER.
printf '# Fact sheet: x\n\n# NEEDS-OWNER\n- Dup / r1 / opinion\n- Dup / r2 / warning\n' > "$work/dup.md"
reason "$work/dup.md" | grep -q 'duplicate' && ok "reject: duplicate NEEDS-OWNER candidate" || err "duplicate allowed"

# 6. Stable contract: section must exist even when empty.
printf '# Fact sheet: x\n- A / a1b2c3d / event\n' > "$work/missing.md"
reason "$work/missing.md" | grep -q 'section missing' && ok "reject: NEEDS-OWNER section absent" || err "absent section accepted"
printf '# Fact sheet: x\n- A / a1b2c3d / event\n\n# NEEDS-OWNER\n' > "$work/empty.md"
NO "$work/empty.md" && ok "empty NEEDS-OWNER (heading only) is valid (stable contract)" || err "empty section rejected"

# 7. Consumable by the gap interview: groupable by TOPIC.
python3 "$root/$VNO" "$work/ok.md" --group | grep -q '\[significance\]' \
  && ok "--group buckets items by TOPIC for the interview" || err "--group did not group by topic"

# 8. Section-awareness: the fact-sheet validator ignores the NEEDS-OWNER section.
# (validate-fact-sheet requires a writing-sources.yaml at --root since #122's fail-loud change.)
printf 'sources:\n  - path: .\n' > "$work/writing-sources.yaml"
n=$(python3 "$root/$VFS" "$work/ok.md" --root "$work" 2>/dev/null | grep -c 'entries,' || true)
python3 "$root/$VFS" "$work/ok.md" --root "$work" 2>/dev/null | grep -q '^2 entries,' \
  && ok "fact-sheet validator reads only the fact-sheet section (2, not 4)" || err "fact-sheet validator leaked into NEEDS-OWNER"

# 9. No confabulated premise (#526): a declared factual premise must be
#    pointer-backed or `premise: unverified`, else a NAMED rejection. The grammar
#    gate runs WITHOUT --root (the check harness has no hub).
# 9a. The exact #526 tanuki-run confabulation (committed regression fixture) is
#     rejected with the confabulated-premise class.
FIX="$root/scripts/fixtures/needs-owner/tanuki-run-confabulated-premise.md"
grep -q 'described internally as "the Tanuki demo" for personal-policy influence' "$FIX" \
  && ok "regression fixture reproduces the exact #526 tanuki-run line" || err "fixture drifted from the #526 line"
reason "$FIX" | grep -q 'confabulated-premise' \
  && ok "reject: #526 confabulated premise (prose asserted as fact)" || err "confabulated premise accepted"

# 9b. `premise: unverified` — an open question, not a claim — passes.
printf '# Fact sheet: x\n\n# NEEDS-OWNER\n- Why did we frame it that way / owner framing / significance / premise: unverified\n' > "$work/prem-unverified.md"
NO "$work/prem-unverified.md" && ok "accept: premise: unverified (open question, not fact)" || err "premise: unverified rejected"

# 9c. A pinned `premise: path:line@sha` passes the structural grammar (no --root).
printf '# Fact sheet: x\n\n# NEEDS-OWNER\n- Why this design / owner framing / opinion / premise: docs/a.md:12@a1b2c3d\n' > "$work/prem-pinned.md"
NO "$work/prem-pinned.md" && ok "accept: premise: path:line@sha (fact-sheet SOURCE grammar)" || err "pinned premise pointer rejected"

# 9d. An unpinned `premise: path:line` (no @sha) is rejected — same rule as a SOURCE.
printf '# Fact sheet: x\n\n# NEEDS-OWNER\n- Why this design / owner framing / opinion / premise: docs/a.md:12\n' > "$work/prem-unpinned.md"
reason "$work/prem-unpinned.md" | grep -q 'unpinned-premise-pointer' \
  && ok "reject: unpinned premise pointer (path:line with no @sha)" || err "unpinned premise pointer accepted"

# 9e. An item with NO premise clause still parses byte-identically — passes.
printf '# Fact sheet: x\n\n# NEEDS-OWNER\n- A bare unsourceable question / not in declared sources / other\n' > "$work/prem-none.md"
NO "$work/prem-none.md" && ok "accept: no premise clause (bare unsourceable question, AC3)" || err "no-premise item rejected"

# --- Story 18.50 (#567): the rule is shared, and it reaches PROSE clauses -----

# 10a. The engine-wide rule has ONE implementation; this validator is a call
#      site of it, not a second copy.
GP="$root/scripts/gate_premise.py"
[ -f "$GP" ] && grep -q 'gate_premise' "$root/scripts/validate-needs-owner.py" \
  && ok "premise rule lives in the shared gate_premise.py; the validator calls it" \
  || err "premise rule is not shared (gate_premise.py missing or not consumed)"

# 10b. THE #567 REGRESSION FIXTURE: correct top-level disclosure (`not in
#      declared sources` in the REASON) plus an unsourced premise in a
#      SUBORDINATE CLAUSE of the candidate prose. Top-level candour is not a
#      defence — this must FAIL. Pre-#567 it passed, because the grammar only
#      ever saw a declared `premise:` clause.
FIX567="$root/scripts/fixtures/needs-owner/inline-subordinate-premise.md"
grep -q 'not in declared sources' "$FIX567" \
  && grep -q 'originally built for scenario replay' "$FIX567" \
  && ok "fixture reproduces the #567 shape (honest top level, invented subordinate clause)" \
  || err "the #567 fixture drifted from its shape"
reason "$FIX567" | grep -q 'confabulated-premise' \
  && ok "reject: a premise smuggled into a subordinate prose clause (#567)" \
  || err "inline subordinate premise accepted — top-level candour treated as a defence"

# 10c. The same assertion GROUNDED AT THE POINT OF USE passes, both ways.
printf '# Fact sheet: x\n\n# NEEDS-OWNER\n- Why framed as a demo, given it was originally built (unverified — no declared source) for replay? / owner framing / significance\n' > "$work/inline-marked.md"
NO "$work/inline-marked.md" \
  && ok "accept: inline \`unverified —\` marker at the point of use" \
  || err "inline unverified marker rejected"
printf '# Fact sheet: x\n\n# NEEDS-OWNER\n- Why framed as a demo, given it was originally built for replay (README.md:12@abc1234)? / owner framing / significance\n' > "$work/inline-pinned.md"
NO "$work/inline-pinned.md" \
  && ok "accept: inline pinned pointer at the point of use" \
  || err "inline pinned premise rejected"

# 10d. Marker SPELLING is fixed: a hyphen lookalike is a named rejection, not a
#      silent miss — the likeliest way one spelling drifts back into two.
printf '# Fact sheet: x\n\n# NEEDS-OWNER\n- Why framed as a demo, given it was originally built (unverified - no source) for replay? / owner framing / significance\n' > "$work/inline-hyphen.md"
reason "$work/inline-hyphen.md" | grep -q 'marker-spelling' \
  && ok "reject: hyphen lookalike of the \`unverified —\` marker (em dash is the spelling)" \
  || err "hyphen marker variant silently accepted"

# 10e. A marker in a DIFFERENT clause does not ground the assertion — that is
#      the footnote the point-of-use rule exists to forbid.
printf '# Fact sheet: x\n\n# NEEDS-OWNER\n- Why framed as a demo, given it was originally built for replay; unverified — see note / owner framing / significance\n' > "$work/inline-footnote.md"
reason "$work/inline-footnote.md" | grep -q 'confabulated-premise' \
  && ok "reject: marker in a different clause (a footnote is not point-of-use)" \
  || err "a distant marker grounded the assertion"

# 10f. (The #567 skill-side lockstep assertion retired with the harvest skill
# — #1182/Story 20.147; the validator behavior above is the enforcement.)

if [ "$fail" -eq 0 ]; then
  printf '\nAll NEEDS-OWNER checks passed.\n'; exit 0
else
  printf '\nNEEDS-OWNER checks FAILED.\n' >&2; exit 1
fi
