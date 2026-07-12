---
name: harvest
description: >
  Gather source-pointed facts from a repository into a fact sheet. Use when the
  owner asks to "harvest" facts, or as stage 1 of the draft-article pipeline.
  Reads only the sources declared in the host repo's writing-sources.yaml; every
  fact carries a resolvable source pointer (file:line, commit, or URL).
---

# Harvest

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

- includes **only** the paths declared in the host repo's `writing-sources.yaml`
  (the host repo `.` and any sibling checkouts such as `../research-notes`);
- applies each source's `include:` globs as an allowlist;
- prunes `.git/` and refuses any symlink or `..` that escapes a declared root.

**Read nothing outside this list.** Do not traverse a sibling directory because
it is adjacent on disk, and do not fall back to scanning the whole repo or
filesystem. An undeclared repository is never read.

## 2. Fail closed

If the command prints no files — `writing-sources.yaml` is missing, malformed,
or declares only non-existent paths — **stop and read nothing**. Report that no
sources are declared and point the owner at
`config/writing-sources.example.yaml`. Never widen scope to compensate.

## 3. Extract facts, each as `CLAIM / SOURCE / KIND`

Read the in-scope files and extract facts. Every entry is one line —
`CLAIM / SOURCE / KIND`:

- **SOURCE** is a resolvable pointer: `path:line@sha` (a file line PINNED to the
  commit it came from, so it survives later edits that shift line numbers), a
  commit `sha`, or a URL for a declared external source. A bare `path:line`
  without `@sha` is not accepted. For every KIND **except `quote`**, SOURCE names
  a **single** commit-pinned line — `path:line@sha`, **not** a range (`12-19` is
  rejected; split it into per-line pointers).
- **KIND** ∈ {result, decision, number, quote, event}.
- A `quote` entry's CLAIM is the source text **verbatim and ONLY the source text**
  — no label, attribution, or prefix (not "Decision from batch 16: …"), and never
  paraphrased or normalized. A CLAIM carrying anything beyond the quoted words is
  rejected. Its SOURCE pins the exact physical line(s): `path:line@sha` for a
  single-line quote, or `path:line1-line2@sha` when the quoted text genuinely
  spans consecutive physical lines (e.g. a wrapped markdown-table cell). Never
  fold in unrelated adjacent text to force a single-line match — pin the real
  boundary.
- Every file pointer resolves inside a **declared** repo (Story 3.1 scope); a
  pointer into an undeclared repo is unsourceable.

A claim you cannot pin to a resolvable SOURCE does **not** go on the fact sheet —
it routes to the **NEEDS-OWNER** list below. Validate the emitted sheet with:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-fact-sheet.py <harvest-doc> --root <host-repo>
```

(`--root` defaults to the git top-level of cwd; the validator errors if the
resolved host has no `writing-sources.yaml`, rather than mass-rejecting every
pointer against an empty source list.)

Every entry must pass; the rejects are exactly what the NEEDS-OWNER list captures.

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
```

Pass that `$WS/fact-sheet.md` path as `<harvest-doc>` to the validators above.
Never compose a storage path yourself, and never write the fact sheet, the
NEEDS-OWNER list, or any scratch into the host working tree — only declared
products land in the host repo (at `output.drafts`), and harvest produces none.

## Harvest output contract

Identical whether invoked standalone or as pipeline stage 1, so the pipeline
consumes it unchanged — the fact sheet followed by the always-present
NEEDS-OWNER list:

```markdown
# Fact sheet: {subject}

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
— **informational notes** (e.g. fact-sheet and NEEDS-OWNER counts), **publish
blockers**, **optional cleanup** — then an explicit **next step** ("review the
fact sheet, or run draft-article to turn it into a draft"). A **standalone harvest
omits the reading-time estimate**: it produces a fact sheet, not an article body,
so there is nothing to measure.
