# writing-assistant

A Claude Code plugin that turns a repository's own specs, docs, and git history
into publishable articles: a **harvest** step gathers source-pointed facts, a
**draft** pipeline fills a chosen framework, and a **review** workflow checks the
result. Installable per-repository so it runs *inside* the repo it writes about.

## Install

The repo is **its own marketplace** — no Community Marketplace submission, and no
files are copied into the repo you're writing about. From inside a host repo (a
fresh clone of the project you want to write about), run:

```
/plugin marketplace add tim-nish/writing-assistant
/plugin install writing-assistant@writing-assistant
```

That makes the `harvest`, `draft-article`, and `review-article` skills available
in the host repo as `/writing-assistant:<skill>`. To develop against the plugin
without installing it, see [Development mode](#development-mode-run-skills-before-packaging).

**Updating.** Installation copies the plugin into Claude Code's cache
(`~/.claude/plugins/cache/writing-assistant/writing-assistant/<version>/`);
sessions run from that copy, **not** from this repo. **`/reload-plugins` does
not fetch or rebuild plugin files** — it reloads the existing on-disk snapshot
only. Which refresh you need depends on how the plugin is loaded:

- **Local development (`claude --plugin-dir <checkout>`)** — sessions run the
  checkout directly. Code changes are picked up by **restarting Claude Code**
  against the checkout (see
  [Development mode](#development-mode-run-skills-before-packaging));
  `/reload-plugins` does not refresh them.
- **Installed plugin (the cache above)** — sessions run a frozen copy. After
  pulling or merging plugin changes, **update or reinstall first** so the
  cache is re-copied — `/plugin marketplace update writing-assistant`, then
  update/reinstall via `/plugin` — and *then* run `/reload-plugins` to load
  the refreshed snapshot. Reloading without updating faithfully re-reads the
  old copy, with no warning.

**Diagnosing stale behavior** — check which snapshot the session is actually
running before debugging anything else. This one-liner prints each loaded
copy's path and content fingerprint, so you can tell a checkout from the
cache and confirm whether it matches this repo:

```sh
for d in ~/.claude/plugins/cache/writing-assistant/writing-assistant/*/ /path/to/writing-assistant; do
  [ -d "$d" ] && printf '%s  %s\n' "$(cat "$d"/scripts/*.py "$d"/skills/*/SKILL.md 2>/dev/null | md5sum | cut -c1-12)" "$d"
done
```

Matching fingerprints = the cache is current; a mismatch means the session is
running a pre-update snapshot (for a checkout, `git -C <path> rev-parse
--short HEAD` names the commit).

## Configure

**The supported first-run path is the `setup` skill** (SPEC-repo-onboarding):
ask for *"set up this repo for the writing assistant"* in a Claude Code session
and approve its proposals — it inspects the repo, drafts the source allowlist,
draft location, and the optional `policy_source`, writes the machine-global
config through sanctioned writer subcommands, and verifies the result. You
never open a config file; after a clean finish, `draft article` runs
immediately. Everything below documents what `setup` configures — read it to
understand the two files, or to hand-edit them as the escape hatch.

Two config files drive the plugin; **your identity lives in config, never in the
skills**, so the engine is generic (a different user's config produces a different
author with zero skill edits). The split, at a glance:

| | `user-config.yaml` | `writing-sources.yaml` |
|---|---|---|
| Answers | **who is writing**, and where it publishes | **what this repo's articles draw from**, and where drafts land |
| Scope | machine-global (per person, not per repo) | per host repo |
| Lives at | `~/.config/writing-assistant/` | `~/.config/writing-assistant/repos/<repo-key>/` |
| Set up | once per machine | once per repo you write about |

**1. Owner identity — machine-global (per person, not per repo).** Copy the
example to the resolved path and fill in your details:

```sh
mkdir -p ~/.config/writing-assistant
cp config/user-config.example.yaml ~/.config/writing-assistant/user-config.yaml
# then edit: name, site_url, pointer-block content, canonical/syndication
# policy, and your target site's `article` frontmatter schema.
```

Two of its sections are easy to skip past on first setup, so here is what they
are *for*:

- **`frontmatter` (the `article` schema)** — the YAML schema your target site
  expects on every article. The pipeline emits draft frontmatter conforming to
  it, which is what lets a finished draft drop into your site unchanged and pass
  its build validation.
- **`canonical` / syndication policy** — which platform hosts the *canonical*
  copy per language (e.g. EN: your site canonical, dev.to copy carries a
  `canonical_url` back to it; JA: Zenn canonical). This drives which platform
  variants the pipeline emits and how each variant's `canonical_url` is filled.

Values left as example placeholders are reported as configuration errors before
any drafting starts — fill them once and they never resurface.

Resolution order: `~/.config/writing-assistant/user-config.yaml` first, then an
optional repo-local `config/user-config.yaml` as a per-key override.

**2. Sources & draft location — per host repo, stored machine-globally.**
`setup` writes this file for you (via the `set-sources`, `set-draft-location`,
and `set-policy-source` writer subcommands — comment-preserving and
fail-closed); the format below is the contract, and hand-editing it is the
escape hatch. It lives in the **machine-global per-repo config — not in the
repo you're writing about** (a host repo may be public or become public
later, and this file can carry private pointers; see
[`config/writing-sources.example.yaml`](config/writing-sources.example.yaml)).
Print the exact destination for a repo with:

```
python3 scripts/resolve-paths.py sources-file --root <host-repo>
# → ~/.config/writing-assistant/repos/<repo-key>/writing-sources.yaml
```

```yaml
sources:
  - path: .                      # the host repo itself
  - path: ../research-notes      # sibling checkout (optional)
    include: ["notes/**", "specs/**"]
output:
  drafts: ~/work/articles/drafts/  # recommended: a private articles repo OUTSIDE the host
```

(A legacy in-repo `writing-sources.yaml` is still read during migration, with a
deprecation notice; when both exist the machine-global file wins.)

`harvest` reads **only** the declared `sources` (undeclared repos are never
read). For a whole-repo scope (`path: .`), add an **`include:` allowlist** so
harvest reads article material and skips tool/editor/build directories
(`.claude/`, `_bmad/`, `node_modules/`, …); without one, `path: .` sweeps the
whole tree and harvest **warns** about the noise it pulled in (the default scope
is never silently narrowed). **`output.drafts` has no default** — the pipeline
writes drafts and platform variants there; if the key is missing it asks once
and offers to write your choice back into `writing-sources.yaml`.

## Usage

```
setup                                          # once per repo: guided onboarding, no manual YAML
harvest                                        # standalone source-pointed fact sheet
draft article <article-type> from <sources>    # harvest → interview → fill → variants
review article <draft>                         # lint → structure → prose → cold read
```

- Article types are **intent labels**: "introduce the project", "share
  engineering lessons", "explain the evaluation methodology", "survey a
  research area". (`F1`–`F4` keep working as the internal/expert alias for the
  same four, in that order.)
- The draft pipeline marks every inferred claim with `[VERIFY]` and resolves them
  in a bounded owner pass; the review workflow emits capped, severity-tagged
  findings and never auto-edits — you arbitrate.

## Layout

```
.claude-plugin/    plugin.json + marketplace.json (repo-as-marketplace packaging)
skills/
  setup/           once-per-repo guided onboarding: sources, drafts, policy_source
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

## Documentation

Reader-facing guides, derived from the implementation and specs (the specs
remain the normative contracts):

- [`docs/pipeline-vocabulary.md`](docs/pipeline-vocabulary.md) — the pipeline's
  working vocabulary and data flow: what Stage 3 is, the closed nine-KIND fact
  sheet, and where information is narrowed or routed.
- [`docs/review-artifact-lifecycle.md`](docs/review-artifact-lifecycle.md) —
  what `review-article` writes and where (nothing into the host tree; accepted
  findings re-persist the canonical in place), and the commit-before-review
  convention.
- [`docs/owner-input-model.md`](docs/owner-input-model.md) — how the owner's
  requirements and opinions get into a draft: the gap interview is the channel,
  not post-hoc hand-editing.

## BMAD / hand-written separation

This repo is BMAD-managed. BMAD's footprint is confined to exactly `_bmad/`,
`_bmad-output/`, and `.claude/skills/bmad-*` (all git-ignored); hand-written
project specs live only under `specs/`. Release stripping is therefore a
mechanical removal of those three paths. `scripts/check-skeleton.sh` verifies
these invariants.

**Canonical-spec promotion (#188).** A BMAD-generated spec starts in
`_bmad-output/specs/` (git-ignored, next to its `.memlog.md`). When the epic
implementing it merges, the spec is **promoted**: copied into `specs/` with an
"Adopted — this copy is now the canonical version" header (the same adoption
pattern as the vendored article specs), relative links fixed, and the
`_bmad-output` copy marked superseded. The memlog stays with the BMAD
workspace — it is process state, not contract. Rationale: the canonical
contract for shipped code must be version-controlled; a spec that exists only
in an ignored directory dies with one machine.

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

## Issue triage

Open issues are classified with a `triage:*` label — `triage:direct` (small,
self-contained; implemented straight from the issue), `triage:story` (needs a
bound BMAD story), or `triage:spec` (changes an invariant; the governing spec is
amended first). Producer labels such as `tanuki` mark provenance, not queue
state.

**Story-lineage routing (#483).** Issue-routed work — anything picked up from a
GitHub issue via triage — **decomposes as triage-convention stories**
(`umbrella: <issue>`, under the current triage epic); **bmad-epics deltas are
for spec-corpus planning only**, never for issue-routed work. This line is the
authority for the routing rule: `/triage-gh` and the BMAD workflows honor it,
and specs (e.g. `SPEC-spec-sitting`) cite it rather than restating it.

**Epic-number allocation (#189).** Epic numbers are minted in two lanes —
`_bmad-output/planning-artifacts/epics.md` delta sections *and* triage-created
stories that never get an epics.md section (Epic 13 is such a bucket) — so the
file's own numbering is not the full picture. The rule: **next epic number =
max(epics.md epic list, story frontmatter `epic:` values, `epic-N` issue
labels) + 1**, checked with `~/.claude/tools/story-sync status` before any new
epic is cut. Every triage-lane epic also gets a one-line entry in epics.md's
Epic List naming it a triage bucket, so the list stays complete even when the
stories originated elsewhere.
