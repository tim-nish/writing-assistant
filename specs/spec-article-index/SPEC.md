---
id: SPEC-article-index
status: deferred            # do not build, plan, or generate stories until the trigger fires
build-trigger: >
  5 articles published via the pipeline, or the first observed instance of
  re-explaining a concept a previous article covered — whichever comes first.
relates:
  - ../spec-writing-assistant/SPEC.md   # extends the identity/engine split: index location is user config
sources:
  - ../../q_a/q1.md      # dogfooding Q&A round 1, traceability only
  - ../../q_a/a1.md      # dogfooding Q&A round 1, traceability only
---

> **Deferred contract.** This spec exists so the build decision is pre-made and fires mechanically on evidence: the dogfood findings log and the published-article count are the tripwires. Until the `build-trigger` in frontmatter is met, this spec generates no epics, stories, or code.

# Article Index

## Why

Articles correctly live in the repos they were harvested from — proximity to
sources keeps every pointer resolvable. But years-scale capabilities (avoid
repetition, cross-article contradiction detection, coverage tracking,
follow-up suggestions, an article graph) are queries over article *metadata*,
not prose. A single machine-global index of pointers-and-claims — never
content — serves those queries while leaving the storage architecture intact.

## Capabilities

- **CAP-1** (index record)
  - **intent:** At the end of a pipeline run, with author approval, append one
    record to the index: slug, title, platform(s) + canonical URL, framework,
    topic tags, key claims as one-liners, source repo + commit, date. Records
    contain pointers and one-line claims only — never article bodies.
  - **success:** Every published pipeline article has exactly one record;
    grepping the index for article prose returns nothing.
- **CAP-2** (index location via user config)
  - **intent:** The index location is a key in `user-config.yaml` (recommended
    target: a directory in the owner's website/publishing repo, git-versioned);
    the engine has no default path and never assumes one.
  - **success:** Changing the config key relocates all index reads/writes with
    zero skill edits; absent the key, index features are silently skipped and
    the pipeline runs exactly as pre-index.
- **CAP-3** (harvest/draft consultation)
  - **intent:** Pipeline start consults the index read-only and surfaces:
    prior-coverage notes ("article Y covered X — link instead of
    re-explaining"), potential claim contradictions, and follow-up candidates
    — as informational proposals the author may ignore.
  - **success:** A run on a topic adjacent to an indexed article surfaces the
    overlap before framework fill; ignoring every suggestion changes nothing
    downstream.

## Constraints

- Optional by construction: no index, no behavior change (CAP-2). The plugin
  must remain fully functional for a user who never configures one.
- Append-only record format, one file per article or one flat file —
  greppable plaintext (YAML/markdown), no database.
- Claim entries are one line each; contradiction detection compares claim
  lines, not article content.

## Non-goals

- No article content storage, mirroring, or syndication from the index.
- No automated topic selection or backlog management (standing non-goal).
- No cross-user/team index in v1.

## Success signal

With ~10 indexed articles, starting a draft on an overlapping topic surfaces
the prior article before the interview stage, and the owner links back instead
of re-explaining — observed in a real run, not a test.
