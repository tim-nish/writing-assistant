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

## Development mode (run skills before packaging)

The plugin's skills run as plain local skills **before any `plugin.json` /
`marketplace.json` exists** — packaging is purely additive, so these commands
keep working after Stories 6.1/6.2 add the manifests. Neither mode copies files
into the host repo.

**Mode A — `--plugin-dir` (no linking).** From inside the repo you're writing
about, point Claude at this checkout:

```sh
# prints the exact command, with this checkout's absolute path:
scripts/dev-link.sh plugin-dir-cmd
# e.g.
claude --plugin-dir /path/to/writing-assistant
```

The `harvest`, `draft-article`, and `review-article` skills are then invocable
in that host repo (as `/writing-assistant:<skill>` once a manifest names the
plugin, or `/<skill>` in local mode).

**Mode B — symlink into the host's `.claude/skills/`.** Auto-loads with no flag:

```sh
scripts/dev-link.sh link   ../my-host-repo    # symlink each skills/<name> in
scripts/dev-link.sh status ../my-host-repo    # show link state
scripts/dev-link.sh unlink ../my-host-repo    # remove only this plugin's links
```

`link` creates `../my-host-repo/.claude/skills/<name>` as a **symlink** back to
this checkout — edits here take effect immediately, and nothing is copied. It
refuses to clobber a pre-existing non-symlink skill of the same name.

**Asset paths.** Skills reference their own bundled files (`frameworks/`,
`review-prompts.md`, `scripts/`) via **`${CLAUDE_SKILL_DIR}`**, which resolves to
the skill's own directory in both modes and regardless of cwd — so a symlinked
skill still finds its assets. Use **`${CLAUDE_PROJECT_DIR}`** for the host repo
root.

**In dev mode the normal rules still apply:** identity resolves from
`~/.config/writing-assistant/user-config.yaml` (not this repo's working tree),
and harvest reads only the sources declared in the host repo's
`writing-sources.yaml`. See [`config/README.md`](config/README.md).

Packaging (`plugin.json` + `marketplace.json`) is finalized in Epic 6 once
dogfooding proves the skills out.
