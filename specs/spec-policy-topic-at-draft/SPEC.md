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
  article — "track-matched" per **CAP-5** (the optional per-repo
  `track_topics` mapping when present, otherwise intent-driven judgment) —
  recommendation drafted from the chosen article intent and the
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
- **CAP-5 — optional per-repo `track_topics` mapping seeds the proposal**
  (added 2026-07-21, #525). "Track-matched" in CAP-2 is given a concrete,
  consumer-owned mechanism: a host repo may declare an optional
  `policy_source.track_topics` mapping in `writing-sources.yaml`
  (SPEC-policy-source-seam CAP-1) — articles-repo **track name** → hub
  **topic name(s)**. When the article's backlog item carries a `track:`
  frontmatter value with a mapping entry, that entry becomes the CAP-2
  **default recommendation** for the ≤2-topic proposal; when it is absent
  (no mapping, or no matching entry, or a track-less draft), CAP-2 falls
  back to intent-driven judgment exactly as today. The mapping only
  *parameterizes which topics the recommendation names* — it never widens
  the ≤2 cap, never bypasses the code-enforced whitelist, and never applies
  silently: the owner still approves/overrides under the proposal contract
  (a mapping is a smarter default, not an auto-selection). **Ownership &
  precedence:** track names are owned by the articles repo (its backlog
  `track:` frontmatter is the API — no new upstream schema artifact, per the
  ratified deferral, topics/articles.md:20); hub topic files are
  authoritative for topic existence. A mapped topic that resolves to no hub
  topic file is a **consumer-config defect** (topic-existence lint,
  SPEC-policy-source-seam CAP-1); a mapping track absent from every backlog
  `track:` value is a **warning** (stale mapping), not an error. Absent
  mapping = zero behavior change (generic and intent-driven modes both
  unchanged).

## Constraints

- The reader's whitelist stays code-enforced; per-run selection widens *which
  two* topic files, never *how many* or *what else* is readable. The CAP-5
  `track_topics` mapping is subject to this same bound — it seeds *which*
  topics the proposal names, never *how many* or *what else*.
- A run where the owner declines topic selection reads GLOSSARY + LESSONS
  only — still policy-seeded, just track-less; recorded as such.
- Zero new interaction when `policy_source` is unset (generic mode
  unchanged, CAP-6 of the seam).
