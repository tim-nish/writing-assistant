# Review article — entry & setup

Companion of [`SKILL.md`](../SKILL.md) (the dispatcher). Read on entry to the
**entry phase**: invocation forms, the draft picker, the starter template,
proposal conventions, footprint, the pre-review checkpoint, and stage-0
configuration validation.

Take a framework-complete draft from "review requested" to "publishable" with a
fixed, small number of passes:

```
review article [<host-repo> | <draft>]
```

- **no argument, or a host repo** — the normal form (SPEC-review-ux CAP-1,
  Story 13.31): the owner never types a resolver-internal workspace path.
  Enumerate the candidates through the resolver and present a **picker**:

  ```
  python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py list-drafts --root <host-repo>
  ```

  plus any emitted variants at the resolved `output.drafts` location
  (`resolve-writing-sources.py draft-location`). Show each candidate with its
  metadata — title, article type (**the intent label, never the internal
  id**), created/updated time, and pipeline status (in-progress / complete /
  reviewed). The listing is read-only: it never mutates run state or advances
  a checkpoint. **Exactly one candidate → confirm it and proceed** (confirm,
  never auto-pick). **Zero candidates → report where the pipeline would have
  put one** (the resolver's runs location and the resolved `output.drafts`)
  **and point at draft-article** — never present an empty picker.
- **draft** — a direct path to a framework-complete draft: the expert bypass,
  unchanged (the unit of review is a filled draft, never an outline or idea).

After arbitration completes, how the run closes depends on whether the round
applied any accepted finding:

- **Zero applied edits** (every finding rejected): no re-entry work runs — the
  draft, its provenance map, and any emitted variants are unchanged and no
  stale marking occurs. Checkpoint the review by hand so the picker's status
  column can say "reviewed" on later runs:

  ```
  printf '%s' '{"next_stage": "done", "reviewed": true, "stage": "review"}' | \
    python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py checkpoint --ws "$WS" -
  ```

- **≥1 applied edit**: the edited draft re-enters the gate regime — follow
  *Post-arbitration re-entry* below. The `review-reentry` subcommand writes
  the done/reviewed checkpoint itself; **never hand-write the checkpoint after
  edits** — the subcommand refuses to checkpoint over invalid evidence (an
  invalid provenance map, or for a derived canonical an ancestry pin that does
  not resolve — #704), and hand-writing would bypass exactly that refusal
  (#362).

(Only when the draft came from a run workspace; a direct-path review of an
external draft has no workspace to mark.)

## Starting from a blank repo — the starter template

Reviewing needs a draft, and on a fresh repo there is none. Rather than
hand-writing a schema-valid draft from scratch just to exercise review, copy the
shipped **starter template** — it carries valid `article` frontmatter (`slug`,
`title`, `date`, `mode`, `language`, `summary`, `topics`, `related`) plus the
mandatory pointer block, and it passes `lint-article` **unchanged**, so the shape
is authoritative rather than aspirational:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-writing-sources.py draft-location --root <host-repo>
mkdir -p <resolved output.drafts>
cp ${CLAUDE_PLUGIN_ROOT}/skills/review-article/starter-article.md \
   <resolved output.drafts>/my-first-article.md
```

On a fresh repo the resolved `output.drafts` directory does not exist yet —
resolve it first (there is no default; the command above prints the absolute
location, which may be an external private articles repo, #213), then create it
as shown. It is the one place review-article writes into the
host tree; everything else stays in the run workspace.

Then fill in the frontmatter and replace each section with your own content. The
pointer block in the template uses the example-config site; regenerate it for
your own identity with:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/render-pointer-block.py --language en
```

Run `lint-article` (pass 1 below) on the result before spending a model pass.

## Owner-facing proposals

**Finding class — writing-problem vs missing-input (Story 13.62).** Orthogonal
to severity, each structure/prose/cold-read finding is classified by what can
repair it. A **writing-problem** finding is fixable in the draft and carries a
`Fix:`; a **missing-input** finding diagnoses a source-material gap prose
cannot fill, is marked `[missing-input]`, and names an **upstream remediation**
(`Upstream: re-harvest <target>` or `Upstream: ask <question>`) instead of a
prose fix — it is blocker-eligible and routes to the bounded missing-input
repair hop (SPEC-article-draft-pipeline), never a prose edit. The exact formats
and criteria live in
[`review-prompts.md`](review-prompts.md). Validate an assembled findings block
against the class contract before arbitration — the two shapes are mutually
exclusive:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-review-findings.py <findings-block>
```

A non-zero exit means a finding mixed the shapes (a `[missing-input]` with only
a prose `Fix:`, or a writing-problem carrying an `Upstream:`) — the review pass
that raised it owns the classification; re-author and re-validate.

Arbitration hands each finding to the owner to accept or reject; that
presentation follows the shared
[**owner-facing proposal contract**](../owner-facing-proposal-contract.md)
(`${CLAUDE_PLUGIN_ROOT}/skills/owner-facing-proposal-contract.md`): **where** the
finding sits in the article, **why** it is raised, and accept/reject **choices
whose labels state their concrete effect** on the article — never a shorthand
label the owner must decode. This skill references that one convention rather than
defining its own wording.

The design goal is **maximum defect yield per pass** at a fixed, small cost: the
mechanical checks cost zero tokens, each LLM pass runs **once per draft version**
on a cheap-tier model, and the owner arbitrates all findings in a single round.

## Host-repo footprint (leave nothing behind)

Review **writes no files into the host working tree** — findings are reported to
the owner, never saved as artifacts in the repo. If a pass needs to persist
anything (scratch, a findings log), it goes to the run's **workspace outside the
host repo**, resolved by the path resolver
(`docs/storage-architecture.md` D1–D2), never a path you compose yourself:

```
WS=$(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py new-run)
```

After a review run the host repo's `git status` shows **nothing new** — no
`scratch/`, no stray intermediate. The plugin's only host-tree footprint across
the whole pipeline is the declared draft products at `output.drafts`.

## Review start — pre-review checkpoint proposal (CAP-6)

Arbitration edits the canonical draft **in place** at `output.drafts`, so unless
the pre-review text lives somewhere the owner is meant to look, judging *what
review did* is impossible (#495). Git is that surface — but only if the draft is
already committed. **At review start, check whether the canonical draft is
untracked or dirty in its destination repo** and, if so, surface a one-line
**checkpoint proposal** so the owner can commit the pre-review state:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py review-checkpoint-proposal \
  --draft <output.drafts>/<slug>.md --slug <slug>
```

The command runs **read-only git** (`rev-parse`, `status`) and
**never writes the destination repo** — the pipeline PROPOSES, the owner COMMITS (the ratified
pipeline-proposes/owner-commits stance, hub `topics/articles.md` 2026-07-18;
footprint invariant, `docs/storage-architecture.md` D1). When
`checkpoint_proposed` is true (an **untracked or dirty** draft), present its
`proposal` one-liner to the owner in-conversation as a single offered choice —
its concrete effect stated (owner-facing proposal contract): "commit the
pre-review draft so git is your before/after surface / skip". **Declining is
allowed** — the run's in-conversation before/after diff (below) still shows this
run's edits regardless. A **clean** (committed, unmodified) draft already holds
the pre-review state in git, so no proposal is surfaced; the offer is made
**exactly once**, at review start.

**Before applying any accepted finding, snapshot the pre-arbitration draft into
the run workspace** — this machine-state snapshot is the BEFORE side the report's
diff is computed from, and it is the run-workspace copy the design keeps out of
the host tree:

```
cp <output.drafts>/<slug>.md "$WS/pre-arbitration-<slug>.md"
```

## Stage 0 — configuration validation

Before any review pass, validate the resolved configuration (CAP-5):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-config.py
```

It **halts** on any unresolved placeholder, malformed URL (e.g. a double-slash
`canonical_url`), or missing required key with a **per-key report naming the file**
(`user-config.yaml` / `writing-sources.yaml`) and the fix — so a configuration
defect is caught up front, before any review work, never surfaced as a late
article-quality finding. A clean config passes **silently**.

