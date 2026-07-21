---
name: harvest
description: >
  Gather source-pointed facts from a repository into a fact sheet. Use when the
  owner asks to "harvest" facts, or as stage 1 of the draft-article pipeline.
  Reads only the sources declared in the repo's writing-sources.yaml (resolved
  from the machine-global per-repo config, #211); every fact carries a
  resolvable source pointer (file:line, commit, or URL).
---

# Harvest

**Name the target repository first (#309).** Before reading any scope, print the
resolved target as the flow's first owner-visible line:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py target --root <host-repo>
```

Relay it as `Operating on host repo: <path>`. A wrong-target run is otherwise
only discoverable after the work is paid for. When an explicit `--root`
disagrees with the session's cwd the resolver notes both on stderr — relay that
line too; `--root` still wins.


Produce a **fact sheet** from a repository's own material. Invocable two ways,
with the **same output contract** both times:

- **Standalone** — the owner runs it to get a fact sheet without the rest of the
  pipeline.
- **Pipeline stage 1** — the draft-article skill calls it and consumes the fact
  sheet as its input.

## 1. Resolve the read scope (a hard boundary — never guess)

Enumerate the exact set of files you may read by running:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-writing-sources.py files --root <host-repo>
```

(In a checkout run via `claude --plugin-dir`, `${CLAUDE_PLUGIN_ROOT}` is that
checkout.) Every plugin script that resolves the host repo takes
`--root <host-repo>`; when omitted it defaults to the git top-level of the
current directory and **errors if cwd is not inside a git repo** — it never
silently resolves against cwd. Pass `--root` explicitly whenever the session's
working directory might not be the host repo. This list is the **only**
material in scope. It already:

- includes **only** the paths declared in the repo's `writing-sources.yaml`
  (the host repo `.` and any sibling checkouts such as `../research-notes`) —
  the file itself lives in the **machine-global per-repo config, never in the
  host repo** (#211); resolve its location with
  `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py sources-file --root <host-repo>`;
- applies each source's `include:` globs as an allowlist;
- prunes `.git/` and refuses any symlink or `..` that escapes a declared root.

**Read nothing outside this list.** Do not traverse a sibling directory because
it is adjacent on disk, and do not fall back to scanning the whole repo or
filesystem. An undeclared repository is never read.

**Article plans are never harvest input (SPEC-article-plan; Story 13.56).** An
article plan (`plans/<slug>.md`, `kind: article-plan`) is a planning artifact,
not evidence — even when it sits inside a declared scope (e.g. the host repo is
also the articles repo). **Exclude any file carrying the `kind: article-plan`
frontmatter marker from fact extraction:** nothing in a plan may become a
fact-sheet entry, and no plan line may become a SOURCE pointer. The
`validate-fact-sheet.py` gate enforces this mechanically — a SOURCE resolving
into an article-plan file is **rejected** — so a plan pointer never reaches the
sheet even if a file is read. A reused idea from a prior plan is **re-grounded
on current evidence** (a fresh pin or an interview disposition), never carried
as a bare plan reference.

## 2. Fail closed

If the command prints no files — `writing-sources.yaml` is missing, malformed,
or declares only non-existent paths — **stop and read nothing**. Report that no
sources are declared, name the machine-global path where the file belongs
(`resolve-paths.py sources-file --root <host-repo>` prints it — never create it
in the host repo, #211), and point the owner at
`config/writing-sources.example.yaml`. Never widen scope to compensate.

## 2a. Cover every declared source — or disclose the omission (#514)

The resolved list from §1 is a **lower** bound as well as an upper bound: harvest
**visits every declared in-scope source or discloses that it did not**. Coverage
must never narrow silently as the corpus grows (the #514 failure: a ~4× corpus
growth collapsed a 106-entry/~15-file harvest to 33/5 with zero disclosure).

- **Emit a coverage manifest** at the top of the fact sheet (see the output
  contract below) built from the deterministic enumeration — the pin, the count
  of files `resolve-writing-sources.py files` matched, a `read: <file> (<count>)`
  line per file you extracted from, and either `skipped: none` or a
  `skipped: <file> (<reason>)` line per file you did not read. The accounting is
  **closed**: read files + skipped files must equal the matched count, so a file
  that is neither read nor disclosed as skipped is a validator rejection, not a
  silent gap.
- **At the read ceiling, behave deterministically — never silently sample.**
  When the declared corpus is larger than one pass can read within the
  turn/compute ceiling, either **chunk to completion** across resumed
  invocations (the per-source checkpoint below, #388) or **stop and surface the
  overflow as an owner decision** (which sources to prioritize or exclude),
  presented as the in-conversation CAP-6 choice / a publish blocker. Do **not**
  read an attention-bounded subset and present the result as a full harvest.

This section is enforced in lockstep with `scripts/validate-fact-sheet.py`
(`--require-coverage`); the governing contract is
`specs/spec-article-draft-pipeline/pipeline-stages.md`
§"Harvest coverage disclosure (stage 1)".

## 2b. Declared non-file sources — `github-issues` (Story 13.50)

Source entries carry an optional `type` (Story 13.49). Enumerate the typed
entries with:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-writing-sources.py typed-sources --root <host-repo>
```

A declared `github-issues` entry harvests the **host repo's own issue
tracker** — dogfood findings and owner-filed lessons become fact-sheet
evidence. The read is **read-only and one-way**: list issues (e.g. `gh issue
list --state all --json number,title,url,labels,state,body`, run against the
host repo); **nothing is ever written** to any issue — no comment, no label,
no state change. When the entry declares `labels:` patterns (e.g.
`"tanuki:*"`), keep **only** issues carrying at least one matching label
(shell-glob match against the label name); an unfiltered entry reads all
issues. Issues are the only thing this source reads — it never widens file
scope.

- **SOURCE is the issue URL** — the existing URL pointer form, one fact per
  claim: `- CLAIM / https://github.com/<owner>/<repo>/issues/<n> / KIND`.
- **Recurrence counts and owner dispositions are data, not judgments.** An
  issue stating a recurrence count or an owner disposition
  (accepted/dismissed) has those fields **quoted as data with the fact** —
  e.g. `- finding X, recurrence 4, dismissed by owner / <issue-url> / event` —
  never converted into a pipeline judgment and never used to amplify a
  claim's significance.
- **Routing:** a finding the owner already dispositioned is a sourced fact
  (fact sheet, URL SOURCE). An **open or deferred** finding is not yet owner
  knowledge the pipeline may assert — route it to **NEEDS-OWNER** like any
  other unconfirmed candidate, so the gap interview raises it.
- **Degrade, never fail:** with no `github-issues` entry declared, behavior
  is unchanged. With one declared but the API unreachable (no `gh`, offline,
  auth failure), log **one line** — `github-issues source skipped: <reason>`
  — and continue with the declared file sources. This source never turns a
  harvest into a failure.

## 2c. Declared non-file sources — `tanuki-den` (Story 13.51)

A declared `tanuki-den` entry harvests **Tanuki's findings ledger** for this
target — judged, deduped, recurrence-counted findings, the healthiest dogfood
evidence a repo has. The read is **read-only through a bounded reader**: read
the ledger for the declared target and **nothing else** under Tanuki's state —
**no write path exists**; nothing under Tanuki's state is created or modified,
and a run never touches the Den's history, queues, or scratch. Only a
**declared** entry is read: never fall back to reading undeclared producer
state because it happens to exist on disk.

- **SOURCE is `den:<ledger-id>@<run>`** — a new **pinned** pointer type
  (decided at the spec gate): the Den ledger is not a git-pinned tree, so a
  finding pins to the **run that judged it**, not a commit. `<ledger-id>` and
  `<run>` are `[A-Za-z0-9._-]`. A later audit resolves the pair back to the
  exact finding. An unpinned `den:<id>` is rejected by the validator, exactly
  as a `path:line` with no `@sha` is.
- **A finding's type, recurrence count, and disposition are data on the fact**
  — e.g. `- flaky gate, type friction, recurrence 4, accepted / den:f-19@r-208 / event`.
  The pipeline **never amplifies recurrence into significance** on its own: a
  count of 9 is quoted as a count, never rendered as "a major problem".
- **Routing (same triage rules as Story 13.50):** a **dispositioned** finding
  is a sourced fact and grounds recommended answers; an **open or deferred**
  finding routes to **NEEDS-OWNER** for the gap interview.
- **Degrade, never fail:** no Den for the target, or a ledger whose schema is
  unreadable → log **one line** (`tanuki-den source skipped: <reason>`) and
  continue with the declared file sources. Never a failure, and never a
  fallback to reading undeclared producer state.

## 3. Extract facts, each as `CLAIM / SOURCE / KIND`

**Extract one source at a time, under its budget, then merge deterministically
(#516, CAP-10).** Do **not** read the whole corpus in one attention-bounded pass
and skim — that is the mechanism behind the #514 coverage collapse and the
run-to-run variance CAP-10 exists to remove. Instead, walk the enumerated sources
(§1) **in enumeration order**, and for each file:

- **Check the blob-keyed cache first (#516 Story 18.31).** An unchanged source's
  extraction is reused verbatim across runs — so a re-harvest re-extracts only
  changed blobs, and unchanged files contribute **identical** entries:

  ```
  python3 ${CLAUDE_PLUGIN_ROOT}/scripts/harvest-cache.py get --root <host-repo> --path <file>
  # exit 0: prints the cached `- CLAIM / SOURCE / KIND` entries — append them to
  #         the sheet unchanged and SKIP extraction for this file (a cache hit).
  # exit 1: a miss — extract this file (below), then store the result:
  #   … extract entries … | python3 ${CLAUDE_PLUGIN_ROOT}/scripts/harvest-cache.py put --root <host-repo> --path <file>
  ```

  The cache key is `(path, blob-sha, extractor-version)` in the resolver's state
  root (never the host tree): a changed file (new blob-sha) or a changed
  extraction contract (bumped extractor-version — the hash of this SKILL §3 and
  the validator) yields a **different key**, so a stale extraction is never
  served — invalidation is structural, not a judgment call. A cold cache (fresh
  clone) simply misses every file and this is a first harvest under the budget.
- **Get the file's entry budget** from the budget contract (floors/caps live in
  code, never in this prompt):

  ```
  python3 ${CLAUDE_PLUGIN_ROOT}/scripts/harvest-budget.py --root <host-repo>
  # → one `budget: <file> <n>` line per source, in enumeration order (plus total-budget)
  ```

  The budget is **relative to the source's own size** (the product-lab
  corpus-intake scheme) — a soft extraction target for that one file, not a hard
  cap the validator enforces. Extract that file's facts up to its budget.
- **If a source's genuine facts exceed its budget, do not silently drop them —
  surface a diagnostic naming that source** (`harvest: <file> reached its
  entry budget (<n>); <k> candidate facts not extracted` in the completion
  summary's informational notes) so a budget-clipped source is disclosed, never presented
  as complete in the dark (boundedness-is-a-contract-not-curation). A source
  comfortably under budget needs no diagnostic.
- **Merge deterministically.** Append each source's entries to the fact sheet **in
  enumeration order, then in-file order**, and **dedupe on `(CLAIM, SOURCE,
  KIND)` identity** — never emit the same triple twice (the validator rejects a
  duplicate as a merge failure). Because enumeration order is fixed and the merge
  is mechanical, two runs over unchanged sources produce the **same** sheet.

This per-source discipline is what makes coverage reproducible at any corpus
size: growth adds sources (each with its own budget), it never silently shrinks
what an already-declared source contributes. The blob-keyed cache above makes
that reproducibility hold **across runs** — an unchanged source yields the same
entries every harvest — while the per-source budget and deterministic merge make
it hold **within** a run. The cache composes with the #388 per-source checkpoint
(intra-run resume) and the #514 coverage manifest (per-file disclosure): three
axes over the one enumeration, never in conflict — a cache **hit** still counts
toward the manifest's `read: <file> (<n>)` line exactly like a fresh extraction.

Read the in-scope files and extract facts. **Read every file you cite fresh with
a line-numbered tool (the `Read` tool) at harvest time, and take each line number
from what that tool shows you — never cite a line number from memory, from an
earlier turn's context, or from a summary.** A pointer's line number is only as
trustworthy as the read that produced it; a remembered number is how off-by-one
and fabricated pointers reach the sheet (the `pin-source.py` step below fixes the
`@sha`, not the line you chose). Every entry is one line — `CLAIM / SOURCE / KIND`:

- **SOURCE** is a resolvable pointer, one of the four pinned forms:
  - `path:line@sha` — a file line PINNED to the commit it came from, so it
    survives later edits that shift line numbers;
  - `sha` — a commit;
  - `https://…` — a URL for a declared external source (a `github-issues`
    entry's issue URL, section 2b);
  - `den:<ledger-id>@<run>` — a Tanuki Den finding from a declared
    `tanuki-den` entry (section 2c), pinned to the **run** that judged it
    rather than a commit, because the Den ledger is not a git tree.

  A bare `path:line` without `@sha` is not accepted, and neither is a bare
  `den:<id>` without `@<run>` — every pointer pins. For every KIND **except the
  span-eligible kinds** (`quote` + the four narrative kinds, #438), SOURCE names
  a **single** commit-pinned line — `path:line@sha`, **not** a range (`12-19` is
  rejected; split it into per-line pointers).
- **KIND** ∈ {result, decision, number, quote, event, chronology, motivation, cost, reversal} — the closed set of nine (#438): five atomic kinds plus four **narrative** kinds. This enumeration and `scripts/validate-fact-sheet.py`'s `KINDS` are the two enforcement copies of the closed set; they move in lockstep.
- **The four narrative kinds (#438) — record pointer-backed narrative material.**
  Material that was previously routed off the sheet into NEEDS-OWNER is now
  harvestable **when it carries a pointer**:
  - **`chronology`** — an ordered sequence / timeline of how something unfolded
    (a dogfood log or issue thread giving the order of failures and fixes).
  - **`motivation`** — the *why*: the problem/gap addressed, and **free-standing**
    reasoning behind work or a decision (a commit body "…because the retry
    deadlocked under load"; an issue's problem statement). **Refinement:**
    rationale **bound to a specific harvested `decision` fact may stay with the
    atomic `decision` kind** — do not force `motivation` where the atomic one
    already fits; use `motivation` for the free-standing why.
  - **`cost`** — a recorded price or tradeoff paid (a dogfood finding "the fixture
    rebuild added ~40s per run") — recorded, not opined.
  - **`reversal`** — a superseded position: a struck-through decision, a
    topic-thread Declined line, what an earlier choice reversed to.
  Like `quote`, a narrative kind may use a **span** SOURCE (`path:l1-l2@sha`)
  when the material is a multi-line passage (a rationale paragraph, a chronology
  block) — but **unlike `quote`, its CLAIM is your summary, not verbatim**, so it
  is not whitespace-matched; the span only has to resolve. Narrative kinds admit
  **only pointer-backed** material — unsourceable owner judgment (opinion,
  significance, surprise) still routes to **NEEDS-OWNER** (§4), never onto the
  sheet through a narrative kind.
- A `quote` entry's CLAIM is the source text **verbatim and ONLY the source text**
  — no label, attribution, or prefix (not "Decision from batch 16: …"), and never
  paraphrased. A CLAIM carrying anything beyond the quoted words is rejected.
  Matching is **whitespace-normalized (amended 2026-07-13, #154)**: the CLAIM
  matches when its text, with runs of whitespace and line breaks collapsed to a
  single space, is a **contiguous span** of the source text normalized the same
  way — so a real sentence that wraps across physical lines is quotable by its
  true boundary, while the no-extra-text rule above still holds (the CLAIM is a
  sub-span of the source, never more). Its SOURCE pins the physical line(s):
  `path:line@sha` for a single-line quote, or `path:line1-line2@sha` when the
  quoted text spans consecutive physical lines (e.g. a wrapped markdown-table
  cell). Never fold in unrelated adjacent text to force a match — pin the real
  boundary.
- Every file pointer resolves inside a **declared** repo (Story 3.1 scope); a
  pointer into an undeclared repo is unsourceable.

**Build file-pointer entries through the emitter — never re-type what a tool can
emit (validator convergence, #206).** You read a file at its current line
numbers; for every entry whose SOURCE is a file pointer, hand the `path:line`
(or `path:l1-l2` for a wrapped quote) to the pin helper's `--emit-entry` mode
and **copy its output line onto the sheet unchanged**:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/pin-source.py --root <host-repo> \
  --emit-entry README.md:88 bench/results.md:42-43
# non-quote KINDs: emit, then replace the placeholder CLAIM with your wording
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/pin-source.py --root <host-repo> \
  --emit-entry --kind number bench/results.md:42
# or pipe a column of pointers:
printf 'README.md:88\nbench/results.md:42\n' | \
  python3 ${CLAUDE_PLUGIN_ROOT}/scripts/pin-source.py --root <host-repo> --emit-entry
```

Each emitted line is a complete `- CLAIM / SOURCE / KIND` entry: the SOURCE is
commit-pinned (no new SOURCE grammar), and for a `quote` the CLAIM is the
verbatim source text the validator matches — so the verbatim rule above is
satisfied by copying, never by transcribing from memory. For non-`quote` KINDs
the emitted CLAIM is a placeholder (the helper says so on stderr): replace it
with your claim wording, keeping SOURCE and KIND as emitted. Resolution is
batched — one cached `git show HEAD:<file>` per file, bounded by file count,
not line count. A line you have not committed yet cannot be pinned — the helper
says so and skips it. (The bare pointer mode without `--emit-entry` still
exists when you only need the `path:line@sha` form.)

This is the **only sanctioned construction path** for file-pointer entries:
writing an entry free-hand and then repairing it against the validator is the
reject → guess → re-run loop that exhausted whole turn budgets (#118, #142,
#206) — the emitter exists so that loop never starts.

A claim you cannot pin to a resolvable SOURCE does **not** go on the fact sheet —
it routes to the **NEEDS-OWNER** list below. Then run the validator **once, as a
confirmation pass** over the emitted sheet:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-fact-sheet.py <harvest-doc> --root <host-repo> --require-coverage
```

(`--root` defaults to the git top-level of cwd; the validator errors if the
resolved host has no `writing-sources.yaml`, rather than mass-rejecting every
pointer against an empty source list.) `--require-coverage` makes the
`## Coverage` manifest (§2a, #514) mandatory and checks its accounting closes
(read + skipped == matched); a sheet that discloses nothing about coverage is
rejected just like an unsourced entry.

Every entry must pass; the rejects are exactly what the NEEDS-OWNER list captures.

**Repair is bounded at two validator passes — never a third.** A REJECT on the
confirmation pass is fixed by re-emitting the entry through `--emit-entry`
(wrong line cited, placeholder CLAIM left in place, stale pin), then the
validator runs once more. Entries still rejected after that second pass are
**unsourceable by definition**: move each to the NEEDS-OWNER list with its
REJECT reason as the REASON, surface the stage's **budget-triage signal**
naming what was rerouted, and proceed — the run never spends a third pass
converging on pointer syntax. List the rerouted entries in the completion
summary so the owner sees what fell off the sheet and why.

## 4. Collect unsourceable candidates into NEEDS-OWNER

A useful candidate you cannot attach a resolvable source to goes to the
**NEEDS-OWNER** list — never onto the fact sheet unmarked. Each entry is one line
— `CANDIDATE / REASON / TOPIC`:

- **REASON** — why it could not be sourced (e.g. "no artifact in declared
  sources", "owner's opinion", "unverified number") — enough context to seed the
  gap interview.
- **TOPIC** ∈ {surprise, significance, opinion, warning, tradeoff, audience,
  other} — the gap-interview categories, so items are groupable into ≤5
  questions (the cap is on questions asked, not on the topic set). Pick the one
  that best fits, using these one-line senses (amended 2026-07-13, #142):
  - **surprise** — something unexpected the owner learned while building it;
  - **significance** — why a result/number matters, which one counts most;
  - **opinion** — a stance the owner holds and would defend, not a fact;
  - **warning** — a caveat/limitation/pitfall a reader must know before adopting;
  - **tradeoff** — what a decision cost — what was given up to get it;
  - **audience** — who the piece is for and what they should do after reading;
  - **other** — a real gap that fits none of the above.

Partition rule: a candidate lands in **exactly one** of the fact sheet or
NEEDS-OWNER — never both. **Always emit the `# NEEDS-OWNER` heading**, even when
the list is empty, so the pipeline can rely on its presence. Validate with:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-needs-owner.py <harvest-doc>
```

## Where the harvest document lands (never the host repo)

The fact sheet + NEEDS-OWNER list is an **intermediate**, not a product: it is
written to the run's **workspace outside the host repo**
(`docs/storage-architecture.md` D2), never into the host working tree. Get the
workspace from the path resolver — in pipeline mode the draft-article skill
passes its run workspace in (`$WS` from its Stage 0); standalone, mint one:

```
WS=$(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py new-run --root <host-repo>)
# write the harvest document to "$WS/fact-sheet.md"
# (if fact-sheet.md already exists — a resumed or re-entered run — Read it
#  before writing: the Write tool refuses to overwrite an unread file)
```

Because this path lives **outside** the host repo (in the resolver's
machine-local state root — its layout is resolver-internal), a first-time user
has no way to guess it. **Print the resolved absolute
`$WS/fact-sheet.md` path to the user** — in the completion summary's
informational notes below (standalone runs), so "where is my fact sheet?" has a
copy-pasteable answer rather than a `$WS` the user cannot expand.

**Per-source progress recording (Story 13.83, #388) — pipeline-driven runs
only.** A large harvest must survive a mid-stage turn-ceiling death without
replaying sources already harvested. After each source's entries are extracted,
pinned, validated, and **appended to `$WS/fact-sheet.md`** — in that order, the
sheet write comes first — record the source as done (batch several in one
call):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py progress --ws "$WS" --stage harvest --done <source> [<source> …]
```

On a resumed run, the checkpoint's `progress.harvest.done` lists the sources
already harvested: **skip them** — their entries are in the fact sheet; do not
re-read, re-pin, or re-validate them — and continue with the first source not
listed. Standalone harvests (no pipeline `$WS` checkpoint) skip this recording;
the completion contract is unchanged either way.

Pass that `$WS/fact-sheet.md` path as `<harvest-doc>` to the validators above.
Never compose a storage path yourself, and never write the fact sheet, the
NEEDS-OWNER list, or any scratch into the host working tree — only declared
products land in the host repo (at `output.drafts`), and harvest produces none.

## Harvest output contract

Identical whether invoked standalone or as pipeline stage 1, so the pipeline
consumes it unchanged — the **coverage manifest**, then the fact sheet, then the
always-present NEEDS-OWNER list:

```markdown
# Fact sheet: {subject}

## Coverage
pin: a1b2c3d
matched: 3
read: bench/results.md (4)
read: README.md (1)
skipped: docs/appendix.md (over the read ceiling — surfaced to owner)

- Throughput rose 2x on the 10k-scenario suite / bench/results.md:42@a1b2c3d / result
- Chose JAX over PyTorch for vmap composability / a1b2c3d / decision
- p99 latency 180ms / metrics/latency.csv:7@a1b2c3d / number
- "we deliberately leak no test scenarios" / README.md:88@a1b2c3d / quote
- v0.3.0 tagged and released / a1b2c3d / event

# NEEDS-OWNER

- The token-bill win surprised us mid-project / no artifact in declared sources / surprise
- This matters because reviewers keep asking about leakage / owner's framing / significance
```

Fact-sheet entries are `CLAIM / SOURCE / KIND` (resolvable, commit-pinned, no
entry without a source). SOURCE is a **single** commit-pinned line
(`path:line@sha`, not a range) for every KIND except `quote`, whose SOURCE may
span consecutive physical lines (`path:line1-line2@sha`) when the quoted text
does. NEEDS-OWNER entries are `CANDIDATE / REASON / TOPIC`. A candidate never
appears in both.

## Completion summary

End every harvest run with the shared
[**completion summary**](../completion-summary.md)
(`${CLAUDE_PLUGIN_ROOT}/skills/completion-summary.md`): the three labelled buckets
— **informational notes** (e.g. fact-sheet and NEEDS-OWNER counts, and the
resolved fact-sheet path from above), **publish blockers**, **optional
cleanup** — then the explicit **next step as an in-conversation choice**
(interaction contract, CAP-6/#226): offer "**continue into draft-article** /
**stop here**", drafted from what this run produced (fact-sheet entry count,
NEEDS-OWNER count) so the owner decides by selecting, not by opening the fact
sheet. The path stays printed for reference — display is fine; requiring the
owner to navigate to it before continuing is the defect. A **standalone harvest
omits the reading-time estimate**: it produces a fact sheet, not an article body,
so there is nothing to measure.
