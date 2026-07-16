# Writing Assistant repository layout

Target structure of the new standalone repo (working name: `writing-assistant`):

```
writing-assistant/
  .claude-plugin/
    plugin.json              # plugin manifest: name, version, skills/commands exposed
    marketplace.json         # makes this repo its own marketplace (/plugin marketplace add <owner>/writing-assistant)
  skills/
    draft-article/           # CAP-3: harvest → interview → framework fill → quality gate → variants
      SKILL.md
      frameworks/            # CAP-5: F1–F4 templates from SPEC-article-frameworks
      quality-rubric.md      # stage 3→4 gate rubric (SPEC-article-draft-pipeline CAP-7) — versioned asset; exemplar-derived threshold tuning edits this file, not the specs
    review-article/          # CAP-4: lint → structure → prose → cold read
      SKILL.md
      review-prompts.md      # ported from spec-article-review companion
    harvest/                 # CAP-2: fact sheet with source pointers (used by draft-article, invocable alone)
      SKILL.md
  scripts/
    lint-article.(sh|py)     # pass 0 of review: zero-token mechanical checks — POSIX shell or stdlib-only Python, no JS/TS
    resolve-paths.py         # THE path resolver (docs/storage-architecture.md D1): config lookup, state root, run workspaces — the only place storage paths live
  config/
    user-config.example.yaml # CAP-6: identity — name, site URL, pointer block, canonical policy, frontmatter schema
    writing-sources.example.yaml
  specs/                     # canonical home for implementation specs: this spec, the vendored article specs, spec-article-visuals (accepted 2026-07-10), and the deferred specs (spec-article-restructure, spec-article-index — trigger-gated, see their frontmatter)
  _bmad/                     # BMAD install (installer-managed; stripped at release via bmad-clean)
  _bmad-output/              # BMAD planning/implementation artifacts — epics, stories (stripped at release)
  README.md
```

## Per-repo configuration (machine-global — never in the host repo)

> **Amended 2026-07-15 (#211, storage O1 resolved).** `writing-sources.yaml`
> moved out of the host repo: repository boundaries follow publication
> boundaries, and a host repo that is (or may become) public must never commit
> a file carrying private pointers (`policy_source`, private article
> destinations). The resolver owns the lookup (storage D1), so the move is
> resolver-internal; the previous in-repo contract is retired.

```
~/.config/writing-assistant/repos/<repo-key>/writing-sources.yaml
                                   # CAP-2: declared sources for one host repo;
                                   # <repo-key> is the same path slug the state
                                   # root uses (docs/storage-architecture.md D3)
```

```yaml
# writing-sources.yaml
sources:
  - path: .                        # the host repo itself
  - path: ../research-notes        # sibling checkout
    include: ["notes/**", "specs/**"]
output:
  drafts: ~/articles/drafts/       # where drafts + platform variants land — an
                                   # external (private) articles repo by default,
                                   # never required to be inside the host repo
```

Draft output location comes from `output.drafts` — there is no fixed `drafts/`
default. If the key is missing, the pipeline asks once and offers to write the
key into the machine-global file. No writing-assistant file is created inside a
host repo; the host-repo footprint is exactly the declared products at
`output.drafts` — and only when `output.drafts` itself points inside the host.

User identity config resolves from `~/.config/writing-assistant/user-config.yaml` (machine-global, since identity is per-person not per-repo), overridable by a repo-local file.

## Machine-side storage (resolver-internal — `docs/storage-architecture.md`)

All state and intermediates live outside host repos, resolved exclusively by `scripts/resolve-paths.py`:

```
$XDG_STATE_HOME/writing-assistant/   # default ~/.local/state/writing-assistant
  <repo-key>/                        # path slug of the repo's git toplevel
    runs/<run-id>/                   # per-invocation workspace: fact sheet, NEEDS-OWNER, interview answers, provenance map, gate output, scratch
```

This layout is not contractual: specs reference the footprint invariant and the resolver; the scheme evolves inside the resolver (D3).

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
