# Writing Assistant repository layout

Target structure of the new standalone repo (working name: `writing-assistant`):

```
writing-assistant/
  .claude-plugin/
    plugin.json              # plugin manifest: name, version, skills/commands exposed
    marketplace.json         # makes this repo its own marketplace (/plugin marketplace add <owner>/writing-assistant)
  skills/
    draft-article/           # CAP-3: harvest → interview → framework fill → variants
      SKILL.md
      frameworks/            # CAP-5: F1–F4 templates from SPEC-article-frameworks
    review-article/          # CAP-4: lint → structure → prose → cold read
      SKILL.md
      review-prompts.md      # ported from spec-article-review companion
    harvest/                 # CAP-2: fact sheet with source pointers (used by draft-article, invocable alone)
      SKILL.md
  scripts/
    lint-article.(sh|py)     # pass 0 of review: zero-token mechanical checks — POSIX shell or stdlib-only Python, no JS/TS
  config/
    user-config.example.yaml # CAP-6: identity — name, site URL, pointer block, canonical policy, frontmatter schema
    writing-sources.example.yaml
  specs/                     # canonical home for implementation specs: this spec + the vendored article specs
  _bmad/                     # BMAD install (installer-managed; stripped at release via bmad-clean)
  _bmad-output/              # BMAD planning/implementation artifacts — epics, stories (stripped at release)
  README.md
```

## Per-host-repo files (created on first use in a repo, not shipped)

```
<host-repo>/writing-sources.yaml   # CAP-2: declared sources
```

```yaml
# writing-sources.yaml
sources:
  - path: .                        # the host repo itself
  - path: ../research-notes        # sibling checkout
    include: ["notes/**", "specs/**"]
output:
  drafts: articles/drafts/         # where the pipeline writes drafts + platform variants in this repo
```

Draft output location comes from `output.drafts` — there is no fixed `drafts/` default. If the key is missing, the pipeline asks once and offers to write the key into `writing-sources.yaml`.

User identity config resolves from `~/.config/writing-assistant/user-config.yaml` (machine-global, since identity is per-person not per-repo), overridable by a repo-local file.

## Development and distribution flow

- During development the plugin content runs as plain local skills/commands: `claude --plugin-dir` against this repo, or symlinks into a host repo's `.claude/`. Packaging (`plugin.json` + `marketplace.json`) is additive and finalized once dogfooding proves the skills out.
- Distribution needs no Community Marketplace: users run `/plugin marketplace add <owner>/writing-assistant` then `/plugin install writing-assistant@<marketplace>`. Community listing is an optional later step for discoverability.
- Release stripping is mechanical: remove exactly `_bmad/`, `_bmad-output/`, and `.claude/skills/bmad-*`. Hand-written content never lives in those paths (specs stay in `specs/`). If git history must be excluded from an OSS release, publish via a fresh public repo or squashed export.

## Port mapping from existing specs

| Existing contract | Lands as |
|---|---|
| SPEC-article-frameworks + `article-frameworks.md` | `skills/draft-article/frameworks/` |
| SPEC-article-draft-pipeline + `pipeline-stages.md` | `skills/draft-article/SKILL.md`, `skills/harvest/SKILL.md` |
| SPEC-article-review + `review-prompts.md` | `skills/review-article/SKILL.md`, `scripts/lint-article` |

The site-specific frontmatter/pointer-block details inside those specs move into `user-config.example.yaml` during the port (CAP-6); their pipeline logic is preserved verbatim.
