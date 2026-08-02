#!/usr/bin/env sh
# parallel-safe
# covers: scripts/denial-list-inventory.txt scripts/pin-denial-lists.py scripts/terrain_directions.py scripts/validate-proposal-payload.py
# check-denial-list-growth.sh — extending an enumerated denial list is REFUSED
# as the response to a register leak (Story 20.27, #862;
# SPEC-writing-assistant, owner-surface register, property (a)).
#
# WHY THIS EXISTS. Six rounds of one fix class — #233, #646, #673, #790, #842
# and the 2026-07-28 terrain dogfood — each extended an enumerated denial list
# scoped to the surface where the last leak appeared, with the recurrence count
# climbing throughout. Of the three leaks measured on 2026-07-28, 0 of 3 were
# catchable by ANY extension of these lists. Persistence through fixes is
# evidence about the attribution, not about the dose. The spec now prohibits
# the remedy; spec text alone is advisory, so this is its carrier at the layer
# where the rule is actually broken — the diff.
#
# WHAT THIS IS NOT. It is not a per-surface lint and it inspects no owner
# output. It runs ONCE over the denial lists' own definitions, so it adds
# nothing to the per-surface accretion the umbrella issue names as the pattern
# to stop. It also adds no entry to any list — a check that fought the remedy
# shape by using the remedy shape would be the joke that writes itself.
#
# THE ADMITTING PATH. The lists are DEMOTED, not deleted: they remain the cheap
# deterministic first pass for the sub-class they were built for — coined
# identifiers like `F1` and `GATE`, the 2026-07-16 origin instances. So a
# genuinely correct addition is admitted by an adjacent, human-written
#   # register-exemption: <which leak, and why it is a coined identifier>
# on the entry's own line. What is removed is the SILENT extension.
#
# (The exemption marker is developer-facing source vocabulary, not owner-facing
# surface vocabulary, so the codebook rule of Story 20.26 does not bind it.)
# POSIX shell only — the loop's gate runs every check as `sh "$t"`
# (`~/.tanuki/scenarios/writing-assistant.scenarios.json`, key `loop.test_cmd`),
# so `set -o pipefail`, here-strings and process substitution are unavailable:
# a bash-only check fails the gate on `main` rather than guarding anything (#866).
set -u
cd "$(dirname "$0")/.."
fail=0
ok()  { echo "ok:   $1"; }
bad() { echo "FAIL: $1" >&2; fail=1; }

PIN=scripts/denial-list-inventory.txt
MARKER='# register-exemption:'

[ -f "$PIN" ] || { bad "the pinned inventory $PIN is missing — nothing to compare against"; exit 1; }

TAB=$(printf '\t')
CUR=$(mktemp); trap 'rm -f "$CUR" "$CUR.now" "$CUR.pin" "$CUR.added"' EXIT
python3 scripts/pin-denial-lists.py > "$CUR" 2>/dev/null || { bad "could not read the denial lists"; exit 1; }

grep -v '^#' "$CUR" | sort > "$CUR.now"
grep -v '^#' "$PIN" | sort > "$CUR.pin"

# --- the prohibition -------------------------------------------------------
added=$(comm -23 "$CUR.now" "$CUR.pin")
if [ -z "$added" ]; then
  ok "no denial list has grown since the pin"
else
  # Redirected from a FILE, never piped: a pipeline runs the loop in a
  # subshell, so `fail=1` would be set and then discarded — the check would
  # print FAIL and still exit 0.
  printf '%s\n' "$added" > "$CUR.added"
  while IFS="$TAB" read -r list entry; do
    [ -z "${entry:-}" ] && continue
    # An addition is admitted ONLY by an adjacent, human-written exemption on
    # the entry's own source line. Deny, never warn — and name the entry.
    # Story 20.81 (#1030): the files searched here must be the ones
    # scripts/pin-denial-lists.py declares as SOURCES — INTERNAL_VOCAB travelled
    # to terrain_directions.py with `lint_owner_lines`, so an exemption written
    # on its own source line was no longer visible to this grep and a legitimate
    # addition would have been denied.
    src=$(grep -rn -F -- "$entry" scripts/terrain_directions.py scripts/validate-proposal-payload.py 2>/dev/null \
          | grep -F "$MARKER" | head -1)
    if [ -n "$src" ]; then
      ok "$list gained '$entry' with an adjacent register-exemption naming its leak"
    else
      bad "$list gained '$entry' with no register-exemption — extending an enumerated denial list is prohibited as the response to a register leak (SPEC-writing-assistant, owner-surface register, property (a)). A denial list's non-member fallback is admit; the defect is the shape, not the contents. If this entry really is a coined identifier, add an adjacent '$MARKER <which leak, and why>' and re-pin with scripts/pin-denial-lists.py."
    fi
  done < "$CUR.added"
fi

# --- removals are fine, and worth saying ------------------------------------
removed=$(comm -13 "$CUR.now" "$CUR.pin")
if [ -n "$removed" ]; then
  echo "note: entries removed since the pin (allowed — demotion is the direction of travel):" >&2
  echo "$removed" >&2
  bad "the pin is stale — re-run scripts/pin-denial-lists.py to record the removal"
else
  ok "the pin matches the lists' current contents"
fi

# --- this check is not itself the prohibited remedy -------------------------
if grep -qE '^[[:space:]]*(INTERNAL_VOCAB|FORBIDDEN_MARKERS)[[:space:]]*=' "$0"; then
  bad "this check defines a denial list of its own — the prohibited remedy shape"
else
  ok "this check defines no denial list and extends none"
fi

# --- NEGATIVE TEST: prove the check can fail --------------------------------
# A check nobody has seen fail is indistinguishable from one that cannot.
probe_pin=$(mktemp)
grep -v '^#' "$PIN" | sort | sed '$d' > "$probe_pin"   # pin missing one entry
if [ -n "$(comm -23 "$CUR.now" "$probe_pin")" ]; then
  ok "negative test: an entry absent from the pin is detected as growth"
else
  bad "negative test did NOT detect growth — the check cannot fail"
fi
rm -f "$probe_pin"

[ $fail -eq 0 ] && echo "All denial-list growth checks passed." \
                || echo "denial-list growth checks FAILED." >&2
exit $fail
