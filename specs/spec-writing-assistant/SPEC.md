---
id: SPEC-writing-assistant
companions:
  - plugin-layout.md
  - ../spec-article-frameworks/SPEC.md
  - ../spec-article-draft-pipeline/SPEC.md
  - ../spec-article-review/SPEC.md
  - ../spec-article-visuals/SPEC.md      # accepted 2026-07-10 (q_a/a1.md)
sources:
  - ../../../website/q_a/3/question.md  # external: website repo (sibling checkout), traceability only
  - ../../q_a/q1.md                     # dogfooding Q&A round 1, traceability only
  - ../../q_a/a1.md                     # dogfooding Q&A round 1, traceability only
  - ../../docs/dogfood-findings.md      # dogfood evidence behind the 2026-07-10 amendments
  - ../../docs/harness-architecture.md  # 2026-07-11 article-quality harness decision behind the 2026-07-11 amendments
  - ../../docs/storage-architecture.md  # 2026-07-11 storage & footprint decision behind the footprint invariant
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate. Source documents listed in frontmatter are for traceability only — consult them only if you need narrative rationale or prose color this contract intentionally omits.

# Writing Assistant plugin repository

## Why

An opportunity to capture plus a vision to realize: the article specs already produced in this repo (frameworks, draft pipeline, review) are valuable beyond the website repo, but as `.claude/skills` candidates inside one repo they can serve only that repo. Extracting them into a standalone repository packaged as a Claude Code plugin makes the assistant installable per-repository — so drafting an article about QuantScenarioBench runs *inside* QuantScenarioBench with direct access to its specs, docs, and git history (which is where the draft pipeline's harvest step needs to be). The engine/identity split keeps an open-source release cheap if dogfooding on research-notes proves the tool out.

## Capabilities

- **CAP-1**
  - **intent:** The assistant is a standalone git repository installable as a Claude Code plugin on a per-repository basis; the repo serves as its own marketplace via `.claude-plugin/marketplace.json` (`/plugin marketplace add <owner>/<repo>` + `/plugin install`), with Community Marketplace listing an optional later step for discoverability only.
  - **success:** Installing the plugin in a fresh clone of QuantScenarioBench makes the drafting/review commands available there without copying files into that repo and without any marketplace submission or review.
- **CAP-2**
  - **intent:** A harvest step gathers facts from the host repo and any additional sources declared in a per-repo `writing-sources.yaml` (local paths, sibling repos such as research-notes), with every fact carrying a source pointer (file/line, commit, or URL).
  - **success:** A harvest run against QuantScenarioBench with research-notes declared as a source produces a fact sheet whose every entry resolves to an exact location in one of the two repos; undeclared repos are never read.
- **CAP-3** (amended 2026-07-11 per `docs/harness-architecture.md`)
  - **intent:** The draft pipeline (SPEC-article-draft-pipeline: harvest → ≤5-question interview → framework fill with `[VERIFY]` markers → article-quality gate → platform variants) runs as a plugin skill inside the host repo.
  - **success:** The pipeline's existing success criterion holds when run from a non-website repo: draft in ≤10 minutes of owner attention, zero unmarked invented claims, and the draft passes the article-quality gate (SPEC-article-draft-pipeline CAP-7).
- **CAP-4**
  - **intent:** The review workflow (SPEC-article-review: lint → structure → prose → cold read, capped severity-tagged findings) runs as a plugin skill against a draft file in the host repo.
  - **success:** Each pass runs once per draft version and emits findings, not rewrites, per that spec's contract.
- **CAP-5**
  - **intent:** The four article frameworks (SPEC-article-frameworks) ship as plugin assets the pipeline fills verbatim.
  - **success:** A produced draft's structure matches the chosen framework template slot-for-slot.
- **CAP-6**
  - **intent:** Owner identity (name, site URL, pointer-block content, canonical/syndication policy, frontmatter schema of the target site) lives in a user config file, not in skill prompts, so the engine is generic.
  - **success:** Deleting the owner's config and supplying a different user's config produces drafts carrying the new identity with zero skill-file edits; grepping the skills for `tim-nish.dev` returns nothing.

## Constraints

- Must run inside any host repository without assuming the website repo's layout; all host-specific knowledge enters via `writing-sources.yaml` and the user config.
- Draft output location is declared per host repo in `writing-sources.yaml`; the pipeline never assumes a fixed `drafts/` path.
- This repo is self-contained: the three adopted article specs are vendored under `specs/`, the canonical home for implementation specs. Changes to the adopted specs are made in the vendored copies here; the website-repo originals are superseded for this project.
- The three article specs are adopted contracts: this repo ports them to plugin form but does not redesign their internals; behavioral changes go through their own spec updates first.
- No JavaScript/TypeScript anywhere in the plugin: skills, commands, and templates are Markdown; helper scripts are Python (stdlib-only — host repos guarantee no venv or installed dependencies) or POSIX shell. Invoking `npx bmad-method install` as an external tool does not violate this.
- The repository is BMAD-managed from day one (specs + epics + stories), since the owner implements via BMAD.
- BMAD artifacts and hand-written content stay strictly separated: BMAD's footprint is exactly `_bmad/`, `_bmad-output/`, and `.claude/skills/bmad-*`; project specs live only under `specs/`. Release stripping is then a mechanical removal of those three paths with no judgment calls — nothing hand-written may ever land in a BMAD directory, and no BMAD output may land in `specs/`.
- Dogfooding gate: OSS release decisions wait until the plugin has produced real published articles for research-notes/QuantScenarioBench; releasing is a separate later decision, not part of this build. If working-note history must not ship, release happens via a fresh public repo (or squashed export), keeping this BMAD-managed repo private.
- **Host-repo footprint invariant** (engine-wide; added 2026-07-11 from dogfood findings, `docs/storage-architecture.md` D1–D2): the plugin never writes state or intermediate artifacts into the host repository's working tree — the only files it creates there are declared products at `output.drafts`. All storage paths (config lookup, state root, per-run workspaces) resolve through a single stdlib-Python path-resolver helper; no other script, skill, or prompt carries a storage-path literal, so the layout behind the resolver is an implementation detail with one migration point. `writing-sources.yaml` placement is the one deliberate exemption — its current in-repo contract stands unchanged pending `docs/storage-architecture.md` O1 (dogfood-tripwire-gated).
- **Owner-facing proposal contract** (engine-wide; added 2026-07-10 from dogfood findings): every prompt that asks the owner to approve, modify, or decline something — gap-interview questions, owner-verification items, review-arbitration findings, visual proposals, and any future proposal surface — must show (a) **where** the item lands in the artifact (outline/section context, with a short preview of the current content when one exists), (b) **why** it is being asked, and (c) choices whose labels state their **concrete effect on the artifact** — never shorthand labels that require inferring the generation logic. A first-time user must be able to answer from repository knowledge alone, without already understanding the generated draft. Stage specs reference this contract; they do not restate it.

## Non-goals

- No publishing automation (dev.to/Zenn APIs) — the owner publishes, per SPEC-article-draft-pipeline.
- No topic selection or idea backlog.
- No web UI or service component — Claude Code plugin only.
- No multi-user/team features in v1; single-owner config.
- No BMAD workflow meta-commands in the plugin surface: `/bmad-setup` and `/bmad-epics` are owner-workflow tooling and live in the owner's global `~/.claude/commands`, not in this repo's capabilities.

## Success signal

- After research-notes exists, the owner installs the plugin there, runs the pipeline on real material, and hands a schema-valid draft to review in one session — the first dogfooded article that never touched the website repo's tooling.

## Assumptions

- Claude Code's plugin mechanism (`.claude-plugin` layout, repo-as-marketplace) is the distribution vehicle; during development the same content runs as plain local skills/commands (`claude --plugin-dir`, or symlinked into a host repo's `.claude/`), so packaging is additive and no submodule/`npx` bootstrap fallback is anticipated.
- Cross-repo harvest reads sibling checkouts on local disk (paths in `writing-sources.yaml`); no GitHub API scraping is needed in v1.

## Deferred specs (trigger-gated, not part of the current build)

Written 2026-07-10 (`q_a/a1.md`) so the build decisions are pre-made; each fires mechanically when its frontmatter `build-trigger` is met, with `docs/dogfood-findings.md` as the tripwire. They are deliberately **not** companions: companions are the current build contract.

- [`../spec-article-restructure/SPEC.md`](../spec-article-restructure/SPEC.md) — intent-changing re-outline + fact-preserving re-fill. Trigger: ≥3 logged runs with whole-section post-review manual edits.
- [`../spec-article-index/SPEC.md`](../spec-article-index/SPEC.md) — machine-global metadata index (pointers + one-line claims, never bodies). Trigger: 5 published pipeline articles, or first observed self-repetition.

## Open Questions

- Should the plugin also manage the website's `mode: external` article records (open question inherited from SPEC-article-draft-pipeline), which would reintroduce a website-repo dependency into one optional skill?
