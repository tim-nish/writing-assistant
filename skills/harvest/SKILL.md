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
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-writing-sources.py files
```

(In a checkout run via `claude --plugin-dir`, `${CLAUDE_PLUGIN_ROOT}` is that
checkout.) This list is the **only** material in scope. It already:

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
  without `@sha` is not accepted.
- **KIND** ∈ {result, decision, number, quote, event}.
- A `quote` entry's CLAIM is the source text **verbatim** — never paraphrased or
  normalized.
- Every file pointer resolves inside a **declared** repo (Story 3.1 scope); a
  pointer into an undeclared repo is unsourceable.

A claim you cannot pin to a resolvable SOURCE does **not** go on the fact sheet —
it routes to the needs-owner list (Story 3.3). Validate the emitted sheet with:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-fact-sheet.py <fact-sheet>
```

Every entry must pass; the rejects are exactly what the needs-owner list captures.

## Fact-sheet output contract

Identical whether invoked standalone or as pipeline stage 1, so the pipeline
consumes it unchanged:

```markdown
# Fact sheet: {subject}

- Throughput rose 2x on the 10k-scenario suite / bench/results.md:42@a1b2c3d / result
- Chose JAX over PyTorch for vmap composability / a1b2c3d / decision
- p99 latency 180ms / metrics/latency.csv:7@a1b2c3d / number
- "we deliberately leak no test scenarios" / README.md:88@a1b2c3d / quote
- v0.3.0 tagged and released / a1b2c3d / event
```

Every entry is `CLAIM / SOURCE / KIND` with a resolvable, commit-pinned SOURCE;
no entry appears without one.
