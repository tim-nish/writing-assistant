---
slug: my-first-article
title: "How I cut our CI pipeline from 40 minutes to 6"
date: 2026-01-01
mode: canonical
language: en
summary: A worked starter draft that passes lint-article unchanged — replace every field and section with your own before running review, then swap the pointer block for your rendered one.
topics: [ci, testing, developer-experience]
related: { projects: [], publications: [], products: [] }
---

<!--
STARTER TEMPLATE (Story 13.16). Copy this file into your output.drafts
directory (default articles/drafts/), rename it, and replace the frontmatter
and every section below with your own content. It ships lint-clean so the shape
is authoritative, not aspirational — run it through the lint (pass 1 of review)
to see a clean draft, then edit in place:

  python3 scripts/lint-article <your-draft>

(use the CLAUDE_PLUGIN_ROOT-prefixed path when running from outside this repo).

Frontmatter fields come from your config frontmatter.schema (slug, title, date,
mode, language, summary, topics, related) plus the pointer block below. Keep
mode to canonical or external and language to en or ja; keep summary at or under
240 characters and the title at or under 70 characters with a claim verb.
-->

Our CI took 40 minutes, so every pull request waited most of a coffee break for
a green check. After three changes — cache restore, test sharding, and dropping
a redundant build step — the same suite finishes in 6. This is how each change
paid off, and what I would skip if I did it again.

## The problem: a 40-minute wait tax

Describe the concrete problem your reader shares. Lead with the pain and a number
the reader can feel, not with your project's history. One paragraph is enough —
the reader stays because the problem is theirs, not because you warmed up.

## What changed

Walk through the one idea of the article, in the reader's order: problem, then
solution, then evidence. Keep each section earning its place; cut anything that
does not advance the single claim in the title.

- **Cache restore** — the dependency install dominated cold runs; restoring it
  cut the median build by a third.
- **Test sharding** — splitting the suite across four runners turned a serial
  25-minute test phase into a parallel 7-minute one.
- **Dropping a redundant build** — one job rebuilt an artifact a prior job had
  already produced; deleting it removed 4 minutes of pure duplication.

## The evidence

Show the numbers that back the claim, pointed at a source your reader can check.
Replace this with your own before/after measurement — a table, a benchmark, a
linked run — so the result is verifiable, not asserted.

## What I would skip

State the limit honestly: sharding added flakiness we spent a week taming, and
the caching only helps repositories whose dependency set changes rarely. Naming
the tradeoff earns more trust than another win would.

---
*I write about your-topic, another-topic — more at [example.com](https://example.com).*
*New posts via [RSS](https://example.com/rss.xml) or [follow](https://example.com/follow).*
