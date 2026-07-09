---
name: draft-article
description: >
  Draft a technical article from a repository's own material. Invoke as
  "draft article <F1-F4> from <sources>" to run the pipeline: harvest → gap
  interview → framework fill → verification → platform variants. Frameworks are
  F1 (project intro), F2 (engineering lessons), F3 (evaluation methodology),
  F4 (research survey); sources are paths, globs, or commit ranges.
---

# Draft article

One invocation kicks off the whole harvest-to-variant flow:

```
draft article <framework> from <sources>
```

- **framework** — one of `F1`, `F2`, `F3`, `F4` (see
  `${CLAUDE_PLUGIN_ROOT}/skills/draft-article/frameworks/`).
- **sources** — any mix of paths, globs (`src/**/*.py`), and commit ranges
  (`HEAD~20..HEAD`).

## Stage 0 — start the run

Validate the framework and record the run with:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py start <framework> <sources...>
```

- The framework is checked against the **closed set {F1, F2, F3, F4}**. An
  invalid name is rejected — the command reports the valid set, exits non-zero,
  and **nothing starts** (no harvest, no partial run state). Relay that and stop.
- On success it prints the **run-state** JSON — the chosen framework, its
  framework file, and the **raw sources verbatim** plus their classification
  (path / glob / commit-range). Carry this record into the next stage unchanged.

## Stage 1 — harvest (proceed)

Hand the run to the `harvest` skill to produce the source-pointed fact sheet and
NEEDS-OWNER list. The stage-0 sources are a **selection**, not a scope widener:
harvest enumerates the writing-sources-declared files
(`resolve-writing-sources.py files`) and **intersects** this selection with them,
so a path passed on the command line can only narrow what is read — never add an
undeclared repo. Reconciliation against `writing-sources.yaml` happens there.

## Later stages

Stage 2 (gap interview), stage 3 (framework fill with `[VERIFY]` markers), stage
4 (owner verification), and stage 5 (platform variants) are Stories 4.2–4.6. Each
consumes the prior stage's output; the framework's slots and the shared pointer
block come from `frameworks/` and user config (never hardcoded here).
