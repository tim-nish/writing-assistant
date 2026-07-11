# Plugin storage & footprint — architecture decision

**Status:** accepted (owner, 2026-07-11) · **Date:** 2026-07-11
**Drives:** amendments to SPEC-writing-assistant, SPEC-article-draft-pipeline
(pipeline-stages); closes `docs/harness-architecture.md` open question 4
**Evidence:** `docs/dogfood-findings.md` — 2026-07-11 "plugin footprint on the
target repository" (both friction findings)

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
- **The seam:** every storage path — config lookup, state root, run
  workspaces — resolves through **one path-resolver helper** (stdlib-only
  Python, per the no-JS constraint; e.g. `scripts/resolve-paths.py`). No
  other script, skill, or prompt may contain a storage-path literal. The
  resolver is the architecture; the directory scheme behind it is an
  implementation detail with exactly one migration point. Every refinement
  below — and every future one (cache split, key scheme, GC, config
  migration) — is a resolver-internal change.

### D2 — Run workspaces for all intermediates

Every pipeline invocation gets a workspace:

```
<state-root>/<repo-key>/runs/<run-id>/
```

All intermediates live there: the harvest fact sheet and NEEDS-OWNER list,
interview answers, the provenance map (closing harness OQ4), quality-gate
judge output, and any scratch the run needs. Properties this buys:

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
3. **Cross-run artifacts** — if dogfooding surfaces state that must outlive
   a run (e.g. a reusable fact-sheet cache), it forces the state/cache
   split D2 skipped; that is the signal to revisit, not before.
