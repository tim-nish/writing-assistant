# SPEC — policy topic selection at draft time (`policy_source` split)

**Status: RATIFIED (2026-07-15, owner, via /triage-gh on #230) — decomposed into stories 13.34–13.36; amendment notes placed in SPEC-policy-source-seam and SPEC-repo-onboarding.**
Origin: owner feedback after the 2026-07-15 QSB F1 run. Setup froze
`track: benchmark-engineering` into the machine-global config at onboarding,
but different articles from the same repository need different policy
contexts (article 1 → benchmark-engineering, article 2 → agent-engineering,
article 3 → both). The seam already bounds topics per *read* (≤2), not per
repo — the config just has no way to vary them per run.

## Problem

`policy_source` conflates two decisions with different lifetimes:

- **Where the policy repo is** (`path`) — a per-repository fact, correctly
  captured once at setup.
- **Which policy context this article needs** (`track` / `topics`) — a
  per-article editorial decision, wrongly frozen at setup.

Result: every draft from a host repo reads the same topic slice regardless of
what the article is about, and changing it requires re-running setup.

This supersedes the SPEC-policy-source-seam assumption "one host repo maps
to one backlog track, so `policy_source.track` is a per-repo config value
rather than a per-invocation argument" — dogfood round 2 falsified it (three
planned articles from one repo need three different topic slices). On
ratification, that assumption line in the seam spec gets an amendment note
pointing here; the seam's read-time contracts (≤2 cap, code-enforced
whitelist, CAP-6 degradation) are untouched.

## Capabilities

- **CAP-1 — setup writes `path` only.** The `setup` skill's policy-source
  offer (skill Stage B item 3; SPEC-repo-onboarding CAP-1 step 2) proposes
  and writes only `policy_source.path`. It no longer asks for or writes
  `track`/`topics`. The consequence statement is unchanged (declining =
  generic interview).
- **CAP-2 — per-run topic selection in draft-article.** Stage 2's policy
  probe becomes a two-step: (1) the reader lists available topic files under
  `policy_source.path/topics/` (names only — a whitelist listing, not a
  content read); (2) the pipeline proposes ≤2 track-matched topics for THIS
  article — recommendation drafted from the chosen article intent and the
  host repo, owner approves/overrides under the proposal contract — and
  passes the approved selection to the reader at read time
  (`read-policy-source.py read --topics a.md [b.md]` — a new input that
  *builds* the whitelist, distinct from the existing `--only`, which filters
  within an already-computed whitelist). The ≤2 cap and the code-enforced
  whitelist (GLOSSARY, LESSONS, chosen topics) are unchanged.
- **CAP-3 — config keys demoted to per-run defaults, then removed.** An
  existing `track`/`topics` config value is honored as the *default
  recommendation* in CAP-2's question (never silently applied). Setup stops
  writing these keys; once no owned repo config carries them, the keys,
  their validation, and the `set-policy-source --track/--topics` writer
  flags (SPEC-repo-onboarding CAP-2) are removed together (no permanent
  dead compat path — no-single-use-tooling).
- **CAP-4 — audit unchanged.** The `consulted:` line already records which
  files seeded which questions at which pin; per-run selection needs no new
  audit grammar — the selected topics simply appear (or close as
  `(no conflict)` in review).

## Constraints

- The reader's whitelist stays code-enforced; per-run selection widens *which
  two* topic files, never *how many* or *what else* is readable.
- A run where the owner declines topic selection reads GLOSSARY + LESSONS
  only — still policy-seeded, just track-less; recorded as such.
- Zero new interaction when `policy_source` is unset (generic mode
  unchanged, CAP-6 of the seam).
