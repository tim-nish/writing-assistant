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

## 3. Extract facts, each with a source pointer

Read the in-scope files and extract facts. **Every fact carries a resolvable
pointer** back to where it came from — `path:line` for a file, a commit SHA, or
a URL for a declared external source. (The detailed extraction rules and the
needs-owner handling for unsourceable claims are Stories 3.2 and 3.3.)

## Fact-sheet output contract

The output is a Markdown fact sheet — identical whether invoked standalone or as
pipeline stage 1, so the pipeline can consume it unchanged:

```markdown
# Fact sheet: {subject}

- {fact} — `path/to/file:line`
- {fact} — `commit abc1234`
- {fact} — <https://declared.source/url>
```

Every entry is one fact plus exactly one pointer. Entries with no resolvable
pointer do not belong on the fact sheet (they route to the needs-owner list —
Story 3.3).
