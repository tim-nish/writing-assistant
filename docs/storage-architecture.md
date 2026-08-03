# Plugin storage & footprint — architecture decision

**Status:** accepted (owner, 2026-07-11) · **Date:** 2026-07-11
**Drives:** amendments to SPEC-writing-assistant, SPEC-article-draft-pipeline
(pipeline-stages); closes `docs/harness-architecture.md` open question 4
**Evidence:** `docs/dogfood-findings.md` — 2026-07-11 "plugin footprint on the
target repository" (both friction findings)

> **Dated note added 2026-08-02 (Story 20.150, #1223).** This record describes
> the **pre-reorder** pipeline, in which `harvest` ran before the interview and
> built a fact sheet. It is retired: the feasibility read is `probe` (a verdict
> plus anchors) and grounding happens per claim at `examine` during fill
> (#1182, #1220/#1223). The record is left **unrewritten on purpose** — it is a
> dated decision with an accepted status, and editing it to match the present
> would destroy the thing it exists to preserve. Read every "harvest" below as
> naming the stage that then occupied slot 1.


This document decides where the plugin's configuration, state, and
intermediate artifacts live, fixing the dogfooded pollution of host
repositories. It deliberately decides *less* than it could: the owner's
direction (2026-07-11) is to lock only the invariant and the seam that makes
everything else evolvable, and to let further dogfooding settle the rest —
in particular the long-term model for `writing-sources.yaml` (O1).

---

## Context

The pipeline touches three kinds of data with different lifetimes:

1. **Per-repo configuration** — `writing-sources.yaml` (declared sources,
   drafts path). Long-lived, human-edited.
2. **Run intermediates** — fact sheets, provenance maps, interview answers,
   harvest scratch files. Machine-written, per-run, disposable once the
   draft lands.
3. **Products** — drafts and platform variants. These *intentionally* land
   in the host repo at `output.drafts`; they are project assets, not
   footprint.

(Machine-global identity is already placed: `user-config.yaml` at
`~/.config/writing-assistant/`, per `plugin-layout.md`.)

Dogfooding found the plugin polluting host repos on both of the first two:
`writing-sources.yaml` is *required* in the host root by contract, and
harvest intermediates land in the host working tree (`scratch/…`) because no
contract says where they go — the executing agent defaults to the current
directory. The harness decision (`docs/harness-architecture.md` OQ4) added a
third artifact awaiting a home: the provenance map.

Candidates compared (2026-07-11, in-session): XDG config/state/cache trio;
single repo-keyed root; run workspaces; in-repo-but-git-invisible. The last
is rejected outright — files still appear in the working tree and the
accidental-commit risk is the very finding being fixed. The XDG trio forces
a state-vs-cache classification per artifact *now*, which is exactly the
kind of call dogfooding should make. What follows is the deliberately
un-optimized composite: XDG-compatible where that is free, unclassified
where classifying would be premature.

---

## Decisions

### D1 — The resolver is the only contract

- **Invariant (spec-level):** the plugin never writes **state or
  intermediate artifacts** into the host repository's working tree. The
  only files it creates there are declared products at `output.drafts`.
  Where an intermediate lands is a stated contract resolved through D2 —
  never an agent default.
  - *Scope note:* configuration placement is exempt until O1 resolves —
    `writing-sources.yaml` currently lives in the host root by the existing
    contract, and this document does not change that (see O1). The
    invariant covers what dogfooding showed agents *defaulting* into the
    tree; it does not pre-decide the config model.
  - *Destination-repo write surface (amended 2026-07-23, #611; the Terrain
    View REMOVED 2026-07-28, #874):* the `output.drafts` **destination**
    repository's permitted surface is the two GATED products plus **exactly
    one regenerated NON-GATING view** — `INDEX.md`. A non-gating
    view qualifies only if it is fully regenerated per invocation, never read
    back as an input, and gates no decision; the surface is **enumerated
    exhaustively** in `scripts/check-footprint-invariant.sh`, so a write
    outside the set fails there and is named.
    **The Terrain View is no longer a member** (owner ruling — 2026-07-28):
    Terrain is a writing-assistant feature, so its outputs belong in the
    writing-assistant repository, and writing the View into the articles repo
    was incorrect. The set shrinks back to one; the check shrinks with it, in
    the same sitting, per the named-class rule below.
    **This is a named class, not a hatch.** "Human-facing" does not exempt a
    file from the footprint invariant: a new member is added by amending this
    list and the check together, in the sitting that adds it — never by a
    caller deciding its own output is human-facing. Everything else the
    plugin produces (state, caches, journals, per-run intermediates,
    resumable state) stays in machine-state directories, resolved through the
    seam below.
- **The seam:** every storage path — config lookup, state root, run
  workspaces — resolves through **one path-resolver helper** (stdlib-only
  Python, per the no-JS constraint; e.g. `scripts/resolve-paths.py`). No
  other script, skill, or prompt may contain a storage-path literal. The
  resolver is the architecture; the directory scheme behind it is an
  implementation detail with exactly one migration point. Every refinement
  below — and every future one (cache split, key scheme, GC, config
  migration) — is a resolver-internal change.

### D2 — Run workspaces for all intermediates

**Amended 2026-07-28 (#874), owner ruling.** Terrain's outputs *and its debug
artifacts* belong in the writing-assistant repository — the repo the human
works in for this feature — not in a machine-state directory. The state root
below is therefore no longer the destination for this feature's workspaces;
the **resolver** owns the change (D1), so the scheme moves and nothing that
calls it does.

Three consequences are stated here because they were the ruling's cost, not
objections to it:

- **The tree must not be able to publish them.** This repository is public and
  a run's `map.json` carries verbatim hub renderings and `<hub>@<sha>` pins,
  which in a state directory sat outside every repository. Relocation is
  therefore paired with a **committed** ignore entry (this is the tool's own
  output, not a personal ignore pattern, so it ships rather than living in
  `.git/info/exclude`) **and** a guard that fails if such an artifact is ever
  staged. The boundary is not defended by remembering.
- **Growth stops being deferrable.** Nothing auto-deletes runs today, which
  was tolerable in a state directory nobody reads; inside a working tree it is
  not. A retention rule is owed with the move.
- **"The writing-assistant repo" is one place only when the plugin runs from
  a working tree.** Installed, it is a marketplace clone the owner does not
  work in — so the resolver, not a literal, decides, and where no working tree
  is resolvable the state root remains the fallback rather than a clone
  nobody looks at.

**Amended 2026-07-30 (#935): the 2026-07-28 ruling is narrowed to the
owner-facing OUTPUT, and intermediates return here.** The ruling above is
right about the deliverable and reached one clause too far past it. Two
classes, split at the resolver:

| class | where | why |
|---|---|---|
| Terrain's **View** (`terrain-view.md`) — the owner-facing full report | the writing-assistant working tree | a human opens it to read; it is the deliverable |
| **run workspaces** (`runs/<run-id>/`) and **debug artifacts** | the machine state root | machine-readable intermediates, caches and resumable state, which a human never opens by intent |
| the **check ledger** (`run-checks.sh`'s per-invocation JSONL record) | the machine state root | machine-readable capture written as a side effect of running, never opened by hand — the row above governs its siting and this row adds only what that row does not settle. **It is NOT GC-eligible on clutter grounds** (#1354): the open question below defers GC on the premise that state-root artifacts are debug clutter, and the #1355 governance rules falsify that premise for this one by making it the catch record a retirement review reads. A bound placed on it later is a decision about what such a review is entitled to see, never a disk-space cleanup. The **report** over it stores nothing — it recomputes on demand, because primary capture is permitted where a stored derived tally is not |
| the **brief** (`brief.json` and its recompositions) | the run workspace, in the machine state root | machine-read state — the durable record of a selection decision, re-opened *through* `brief-open` and never by a human editing it. **The owner condition is part of this row and not a footnote to it: no owner act may require the owner to identify or type its filename.** The gate offers the continuation; a brief is named to a person by a DERIVED label (date, member set, thesis first words), never by a stored name and never by its path. The file does **not** move — it is machine-read state, and putting it where a human works would invite the hand-editing its lifecycle exists to replace (Story 20.93, #1048/#1049) |

**Amended 2026-08-03 (#1331/#1342, SPEC-terrain amendments): the brief row's
"the file does not move" is SUPERSEDED — the Brief has a durable home in a
repository, addressed by a stable id.** What the row got right survives whole:
the Brief is re-opened *through* `brief-open`, never by hand-editing, and no
owner act may require the owner to identify or type a filename. What it got
wrong is where that leaves the artifact — a per-run workspace keyed by
recency, which this pipeline already distrusts in its own words (`brief_source`
records **pins first** "because the path is a state-dir location that goes
stale by relocation while still looking authoritative"). So:

| class | where | why |
|---|---|---|
| the **Brief**, addressed by its **stable id** (a digest of its pin and composition) | `<terrain-repo-dir>/briefs/<id>.json` in the writing-assistant working tree — `resolve-paths.py terrain-briefs-dir` | it is the owner's DECISION and is re-opened by design, which is the same property that put the View in a working tree. The **directory listing IS the enumeration**: no index file is written, because an index over a directory is a derived second ledger holding what is recomputable from the directory itself |
| the **workspace copy** (`brief.json` and its recompositions) | unchanged, in the run workspace | the within-sitting iteration chain lives there (`--from`/`--out`). Both copies are written by the one sanctioned writer from one record, so they are identical in content; **nothing is deleted**, and a Brief found in the old location is copied into the home with the migration stated, never silently |

The split is the one already stated portfolio-wide — human-facing artifacts in
the working repo, intermediates and resumable state in machine-state dirs
(owner decision record — 2026-07-16 (artifacts live where the human works)).
The resolver already drew a boundary of exactly this kind (the draft
pipeline's harvest caches, plan fallbacks and stage checkpoints never moved),
so this **relocates** that boundary rather than inventing one, and per D1 no
caller changes.

What the amendment costs, stated rather than assumed:

- **the ignore entry and the staged-artifact guard stay.** Their subject
  shrinks to one file, and that file still carries verbatim hub renderings and
  pins, so the publication boundary is as live as before over a smaller
  surface.
- **the retention rule owed above is discharged by relocation, not by GC.**
  Growth became non-deferrable *because* runs sat inside a working tree; back
  in the state root it is ordinary state growth, deferred as it always was.
  Two things this does **not** discharge: the accumulation already on disk (a
  one-time deletion, owned by no code), and test or dogfood runs keying a real
  repository — the latter is structural once every run resolves through this
  seam.

Every pipeline invocation gets a workspace, resolved through D1's seam:

```
<state-root>/<repo-key>/runs/<run-id>/            # pipeline runs
<state-root>/<repo-key>/terrain-runs/<run-id>/    # terrain runs
```

Corrected 2026-07-31 (#991): this block still read
`<terrain-output-root>/<repo-key>/runs/<run-id>/` — the **pre-relocation**
shape, drifted from story 20.52 (#943), which is precisely the shape whose
appearance in a working tree the relocation forbids. No code read the stale
line, but it contradicted the shipped resolver and stood to mislead the next
reader investigating exactly that leak — as it did.
`<terrain-output-root>` remains real and is documented above; what it no
longer holds is run workspaces. The View file is the only thing that lands
there now.

All intermediates live there: the harvest fact sheet and NEEDS-OWNER list,
interview answers, the provenance map (closing harness OQ4), quality-gate
judge output, **per-stage checkpoint state** (added 2026-07-12, triage #118 —
the state a re-invocation reads to resume from the last completed stage), and
any scratch the run needs. Properties this buys:

- one run = one debuggable, resumable unit;
- garbage collection is "delete old run directories" (policy deferred —
  nothing is auto-deleted in v1);
- the host working tree stays clean by construction, not by agent
  discipline.

No state-vs-cache split inside the workspace: everything per-run is treated
as one lifetime until dogfooding shows an artifact that needs to outlive its
run.

### D3 — Starting layout and repo keying (evolvable, behind D1)

- **State root:** `$XDG_STATE_HOME/writing-assistant`, defaulting to
  `~/.local/state/writing-assistant`.
- **Repo key:** path slug of the repo's git toplevel (the scheme Claude
  Code itself uses for its project directories) — stdlib-trivial and
  debuggable by eye. Moving a repo orphans its old entries; acceptable,
  since run contents are disposable and nothing durable is keyed yet. If
  that ever changes, keying evolves inside the resolver (e.g. to
  first-commit hash).
- **Run id:** timestamp-based slug, unique per invocation.

None of D3 is contractual beyond "the resolver implements it": specs
reference the invariant and the resolver, not these literals.

---

## O1 — `writing-sources.yaml` placement stays open (owner-directed)

> **Resolved 2026-07-15 (#211): candidate 2 — machine-global
> `~/.config/writing-assistant/repos/<repo-key>/writing-sources.yaml`, no
> in-repo file.** The tripwire fired as config-placement friction against a
> maybe-public host: the file carries private pointers (`policy_source`,
> article destinations) and articles are private assets, so any in-repo
> placement crosses the publication boundary; `output.drafts` should target an
> external private articles repo for the same reason. Executed via the resolver
> seam (D1) exactly as designed below. The section is preserved as the decision
> record; the candidate list below is historical.

The long-term model for per-repo configuration is **explicitly not decided**
(owner, 2026-07-11): one dogfooded repo is not enough signal, and a
machine-global default with per-repo overrides — though appealing — may be
premature optimization. Until dogfooding decides:

- The **current contract stands unchanged**: `writing-sources.yaml` in the
  host repo root, as `plugin-layout.md` and the harvest/pipeline specs
  already state. No spec amendment, no migration, no new lookup order.
- The resolver still owns the lookup (D1), so whichever model wins is a
  resolver-internal migration.
- Candidate models to evaluate against future dogfood evidence:
  1. stays in-repo, reframed as project metadata the owner may version;
  2. machine-global `repos/<key>/writing-sources.yaml` under
     `~/.config/writing-assistant/`, no in-repo file;
  3. machine-global default with opt-in in-repo override;
  4. no per-repo file at all — interactive on first run, cached under the
     config root.
- **Tripwire:** the next `docs/dogfood-findings.md` entry that records
  config-placement friction (or a second host repo coming online) triggers
  the O1 decision.

---

## Consequences — spec amendments this decision drives

| Spec | Amendment |
|---|---|
| **SPEC-writing-assistant** | New constraint: the footprint invariant + resolver seam (D1). Host-repo footprint is exactly `output.drafts` products plus — pending O1 — the existing `writing-sources.yaml` contract. |
| **SPEC-article-draft-pipeline** | `pipeline-stages.md`: harvest outputs (fact sheet, NEEDS-OWNER) and the provenance map land in the run workspace — replaces the "location decided together with the plugin-footprint fix" placeholder. Constraint: intermediates resolve through the path resolver, never agent defaults. |
| **plugin-layout.md** | `scripts/resolve-paths.py` added; short storage-layout section (state root, repo key, run workspaces) marked resolver-internal. |
| **docs/harness-architecture.md** | OQ4 annotated as answered by this document (run workspace). |

Deliberately *not* amended: anything stating where `writing-sources.yaml`
lives (O1).

---

## Open questions

1. **O1 above** — the `writing-sources.yaml` model; tripwire-gated.
2. **GC policy** for old run workspaces — deferred until disk or clutter
   shows up in practice; candidate: keep last N runs per repo.
   **Bounded 2026-08-03 (#1354): the check ledger is carved out of this
   deferral and is not GC-eligible on clutter grounds** (see its row above).
   The deferral rests on the premise that state-root artifacts are debug
   clutter; that premise is false for a record a governance rule reads. The
   deferral itself stands for everything else, unchanged — this is a carve-out,
   not a reopening, and item 3 below is still the signal that would reopen it.
3. **Cross-run artifacts** — if dogfooding surfaces state that must outlive
   a run (e.g. a reusable fact-sheet cache), it forces the state/cache
   split D2 skipped; that is the signal to revisit, not before.
