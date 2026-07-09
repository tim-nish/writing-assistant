# writing-assistant

A Claude Code plugin that turns a repository's own specs, docs, and git history
into publishable articles: a **harvest** step gathers source-pointed facts, a
**draft** pipeline fills a chosen framework, and a **review** workflow checks the
result. Installable per-repository so it runs *inside* the repo it writes about.

> **Status: skeleton.** This repository is being built story-by-story from its
> spec. The layout below is in place; skill content, config examples, scripts,
> and packaging land in later stories. See the full installation and usage guide
> (Story 6.3) for how to install and run the plugin once packaged.

## Layout

```
.claude-plugin/    plugin.json + marketplace.json (repo-as-marketplace packaging)
skills/
  draft-article/   harvest → interview → framework fill → variants; frameworks/ assets
  review-article/  lint → structure → prose → cold read
  harvest/         source-pointed fact sheet (used by draft-article, invocable alone)
scripts/           stdlib-only Python / POSIX-shell helpers (no JS/TS)
config/            user-config + writing-sources examples (identity/engine split)
specs/             canonical specs: this one + the vendored article specs
```

The authoritative layout and rationale live in
[`specs/spec-writing-assistant/plugin-layout.md`](specs/spec-writing-assistant/plugin-layout.md)
and [`specs/spec-writing-assistant/SPEC.md`](specs/spec-writing-assistant/SPEC.md).

## BMAD / hand-written separation

This repo is BMAD-managed. BMAD's footprint is confined to exactly `_bmad/`,
`_bmad-output/`, and `.claude/skills/bmad-*` (all git-ignored); hand-written
project specs live only under `specs/`. Release stripping is therefore a
mechanical removal of those three paths. `scripts/check-skeleton.sh` verifies
these invariants.

## Development

During development the plugin content runs as plain local skills
(`claude --plugin-dir` against this repo, or symlinked into a host repo's
`.claude/`). Packaging (`plugin.json` + `marketplace.json`) is additive.
