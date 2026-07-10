# Configuration

Two config files drive the plugin; both have a shipped `*.example.yaml` template.
Skills never hard-code identity — they read it from here (CAP-6).

| File | Answers | Scope | Home | Resolver |
|------|---------|-------|------|----------|
| `user-config.yaml` | **who is writing**: owner identity (name, site, pointer block, frontmatter schema, syndication policy) | machine-global, per-person | `~/.config/writing-assistant/` | `scripts/resolve-user-config.py` |
| `writing-sources.yaml` | **what this repo's articles draw from**: declared sources + draft output location | per host repo | host repo root | `scripts/resolve-writing-sources.py` |

## What the syndication / frontmatter sections are for

The two `user-config.yaml` sections that are least obvious on first setup:

- **`frontmatter` (the `article` schema)** — the YAML schema your target site
  expects on every article. Drafts emit frontmatter conforming to it, so a
  finished draft drops into your site unchanged and passes build validation.
- **`canonical` / syndication policy** — which platform hosts the *canonical*
  copy per language (e.g. EN: site-canonical with a dev.to copy carrying
  `canonical_url`; JA: Zenn-canonical). This determines which platform variants
  the pipeline emits and how each variant's `canonical_url` is composed.

Both are validated up front (SPEC-article-draft-pipeline CAP-5): example
placeholders, malformed URLs, and missing required keys are reported as
configuration errors before any generation, never as late article findings.

## User-config resolution order (the single documented order)

Every skill resolves owner identity through `scripts/resolve-user-config.py`, in
this exact order:

1. **machine-global** — `$WRITING_ASSISTANT_USER_CONFIG`, else
   `~/.config/writing-assistant/user-config.yaml`. Identity is per-person, so it
   lives outside any repo.
2. **repo-local override** — `<host-repo>/config/user-config.yaml`, applied over
   the machine-global file **when present**.

**Override semantics: deep per-key merge.** The repo-local file overrides
individual keys of the machine-global one — **maps are merged recursively**,
while **scalars and lists are replaced wholesale**. So a repo-local file that
sets only `owner.site_url` keeps every other machine-global value; a repo-local
`frontmatter.schema` list replaces the global list entirely rather than
appending.

**Empty path.** At least one of the two files must exist. If neither resolves,
the resolver errors and points you at the example — there is deliberately **no
baked-in default identity**, because a default would be owner-specific and defeat
the generic-engine guarantee.

The resolver emits the merged config as **JSON** (`resolved`) or a single value
(`get owner.site_url`), so downstream skills read identity with the stdlib `json`
module — no PyYAML, which host repos do not guarantee.

## YAML subset

Both resolvers parse a documented subset (host repos have no PyYAML): 2-space
nested maps, block scalars (`key: |`), inline lists (`[a, b]`), lists of scalars
(`- item`), and quoted / bare / integer / boolean scalars. Constructs outside the
subset (e.g. lists of maps in `user-config.yaml`) raise rather than misparse.

## Generic-engine guarantee

`config/*.example.yaml` is the *only* legitimate home for identity literals.
`scripts/check-generic-engine.sh` proves no shipped skill/command/template file
carries owner specifics (the site URL and other identity values), so swapping in
a different user's config yields their identity with zero skill-file edits.
