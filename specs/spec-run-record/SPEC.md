---
id: SPEC-run-record
companions:
  - record-formats.md
sources:
  - ../../docs/storage-architecture.md   # D2 (run workspaces for machine-readable intermediates) — where the record lands
  - ../spec-article-draft-pipeline/SPEC.md # the pipeline whose blocks emit; block↔command table lives in the skill it fronts
---

> **Ratified 2026-08-02 (#1286, #1289), owner direction from the same day's
> debugging sitting.** The remedy shape is the standing one — *owner decision
> record — 2026-07-28 (constrain what the pipeline can produce, not what it can
> detect)*: emission becomes a side effect of running rather than a step an
> agent remembers. New amendments go to a companion `amendments.md` beside this
> file (the amendment-history companion decision, #829), newest-last, never
> into this document.

> **Canonical contract.** This SPEC and the files in `companions:` are the
> complete, preservation-validated contract for what to build, test, and
> validate. Source documents listed in frontmatter are for traceability only.

# The Run Record — per-block emission at block close (#1286, #1289)

## Why

`run-events.jsonl` is the only file that says what a run actually did, and it
**has never had a spec carrier**: its contract lives in `scripts/draft-pipeline.py`
(`cmd_run_event`, `:2597-2611`; the subcommand declared at `:4998-5005` and
dispatched at `:5346`) plus one line of skill prose
(`skills/draft-article/SKILL.md:140`), with a single downstream mention in
`skills/draft-article/stages/complete.md:158`. A file with no contract cannot be
wrong, which is why it went wrong quietly.

**What went wrong, measured on run `20260802T185710-622820`.** A ~50-minute run
with nine judge rounds recorded **three** events — probe start, probe end,
interview end. Nothing from the fill, nothing from the judging, nothing from the
quality gate where the run stopped. The cause is that emission is an agent act:
the skill *asks* the agent to call `run-event`, and an agent under load composes
instead. The cost block already concedes the gap in code — when no `judge-round`
event exists it falls back to **counting verdict files**
(`scripts/draft-pipeline.py:2647-2650`), an admission that the journal cannot be
relied on for the one number it exists to carry.

**The same defect from the other end (#1289).** The one line the interview block
*did* record was false. The journal wrote
`consulted: none (policy_source unset)` (`scripts/draft-pipeline.py:2846-2848`)
while the workspace held `policy-surface.txt` (57,885 bytes) and
`policy-surface.filtered.txt` — the source was set, read, and consumed; what was
absent was a seed→question mapping. The reason was **derived from the absence of
seeds and then reported as a fact about configuration**. A record naming the
wrong reason is worse than one naming none: it points the next debugger at a
config key when the actual fact is editorial. #1286 says a block's record must
carry the judgment actually made; #1289 is that rule broken on the one block that
recorded anything. They are one defect from two ends, and this spec carries both.

**Why a record and not better prompting.** The prompt-composed surface is the
known-defective one: five gates declared in `draft_gates.GATES`
(`scripts/draft_gates.py:227`) are composed from skill prose with no code
emitter, so `gate-inventory.py` reports `reached but never emitted`
(`scripts/gate-inventory.py:364-366`) and the interview journal names the loss as
`payload_capture_warning` (`scripts/draft-pipeline.py:2859`). The answer to a
surface that depends on remembering is never a better reminder.

## Capabilities

- **CAP-1** — the block's own mandatory command emits the block's record
  - **intent:** Every functional block of the draft pipeline has **exactly one
    mandatory command** — the block↔command table is already declared at
    `skills/draft-article/SKILL.md:149-155` (`start` → `stage0`, `probe` →
    `probe.py record`, `gap interview` → `interview`, `fill` → `provenance`,
    `quality gate` → `quality-gate`, `owner verification` → `verify`, `complete`
    → `complete`). That command **writes the block's record as a side effect of
    running**, in the shape `probe.py record` already cannot run without writing
    `probe.json`: no separate call, no agent step, nothing to remember. A block
    that ran has logged, by construction, and a block that did not run leaves an
    absence that means exactly that. Emission is unconditional on success — a
    command that exits non-zero still records, because a failed block is the case
    the record exists for.
  - **success:** A run driven with **zero** `run-event` invocations produces a
    journal carrying one open and one close record per block that ran; deleting
    every `run-event` line from the skill files changes the journal not at all.
    A replay of `20260802T185710-622820`'s block sequence yields records for the
    fill, the judging and the quality gate — the three the observed run lost.
- **CAP-2** — the record carries the JUDGMENT, not the occurrence
  - **intent:** A close record states **what the block decided**: the verdict or
    outcome, **the artifact it decided over** (the draft/map hash where one
    exists), and **the route by which it got there** (which branch, which
    fallback, which degradation). The shape is **copied, not invented** — the
    provenance attestation already models exactly this join of verdict to
    artifact-hash (`attestation: draft-sha256=<hex64>` plus the `graded:` set,
    parsed at `scripts/verify-provenance.py:213-241`), and the record's
    verdict-side fields conform to it rather than paraphrasing it. Fields and
    their validation live in `record-formats.md`. A record whose block produced a
    verdict and whose `verdict` field is absent is **invalid**, not empty:
    "the block ran" without "what it concluded" is the occurrence-only record
    this capability exists to make unrepresentable.
  - **success:** A fixture close record missing the verdict, missing the artifact
    hash, or missing the route is rejected by the validator with the reason
    named; a well-formed one passes; the quality gate's record identifies which
    cycle failed and over which draft hash, without reading any other file.
- **CAP-3** — a partially-run block SAYS SO: the record is three-valued
  - **intent:** `ran` / `ran-partially` / `did-not-run` are three distinct
    states, and a `ran-partially` record **names which sub-obligation was
    skipped and why**. This is the same discipline
    `specs/spec-writing-assistant/SPEC.md` clause (b) binds checks to — *"a
    failed corpus precondition reports DISTINCTLY … neither a pass nor a
    failure"* — applied one level up, to the block. The motivating instance is
    the observed quality gate, which ran with its per-section evidence-type check
    **silently skipped**; that check's own repair is **#1288's** and is not
    touched here. What this spec owns is that the skip must be *expressible and
    recorded*, so the state stops being invisible regardless of which check is
    skipping. A record that collapses partial into `ran` is a defect of the
    emitting command, never of the reader.
  - **success:** A block whose optional sub-step is unavailable emits
    `ran-partially` with the sub-step named; the same block with everything
    available emits `ran`; nothing in the journal can express a partial run as a
    clean one, and a consumer distinguishes the three without heuristics.
- **CAP-4** — written AT BLOCK CLOSE, before the block's checkpoint
  - **intent:** The close record is durable **when the block ends**, not when the
    run ends. This is load-bearing rather than a preference: the motivating run
    **stopped mid-workflow at the quality gate**, so end-of-run emission would
    have produced nothing at all — the exact case the journal is read for. The
    ordering is stated so it is not left to chance: the record is written
    **before** the block's `checkpoint.json` write (`cmd_checkpoint`,
    `scripts/draft-pipeline.py:3521-3530`), so any state a resume can reach has a
    record behind it, and a crash between the two leaves a record with no
    checkpoint rather than a checkpoint with no record. Crash tolerance is a
    consequence of the boundary already existing, not new machinery: resume
    already depends on per-boundary checkpoints.
  - **success:** Killing a run between two blocks leaves every completed block's
    record on disk; killing it *inside* a block leaves that block's open record
    with no close, which reads as "entered, did not finish" and not as absence.
- **CAP-5** — reasons are DERIVED from the workspace, never read off a flag
  - **intent:** Where a record states *why* something did not happen, the reason
    is computed from **what the workspace actually holds** at close, not from an
    input flag or an unset config key. #1289 is the governing instance and its
    fix falls out here rather than as a separate patch: the interview journal's
    `consulted:` line (contract at `skills/draft-article/stages/stage2.md:584-591`)
    today has two states — a pin plus a seed→question map, or
    `none (<reason>)` defaulting to `policy_source unset`
    (`scripts/draft-pipeline.py:2845-2848`). It needs a **third**, and the three
    are distinguished by workspace evidence: **(i)** no source configured — no
    surface artifact exists; **(ii)** source read, zero seeds survived — a
    surface artifact exists in the workspace and the seed→question map is empty;
    **(iii)** source configured, unreachable — the reader's own degradation
    reason, which is already carried explicitly (`--policy-note`,
    `scripts/draft-pipeline.py:5141`) and stays authoritative where present.
    State (ii) is the one the observed run had and could not express.
  - **success:** A run with a policy surface in the workspace and no surviving
    seeds records the source-read-zero-seeds state naming both facts; a run with
    no surface artifact records the unset state; a degraded run records the
    reader's reason unchanged; the run that produced #1289, replayed, no longer
    reports `policy_source unset`.

## Constraints

- **The record is a machine intermediate, not a human artifact.** It lands in the
  run workspace under `docs/storage-architecture.md` D2 — *"machine-readable
  intermediates a human never opens by intent"* — and **Claude Code is the
  declared reader**. No human-readability optimization is owed: no rendering, no
  summary view, no formatting budget. The completion summary's cost block
  (`cmd_cost_block`, `scripts/draft-pipeline.py:2657-2670`) remains the
  owner-facing projection of it.
- **Append-only, one JSON object per line, at the existing path**
  (`<ws>/run-events.jsonl`, `_run_events_path`, `scripts/draft-pipeline.py:2593`).
  The file's location and format do not move; what changes is who writes it and
  what a line must contain. Existing readers (`_read_run_events`,
  `_cost_proxies`) must keep parsing runs written before this contract — an
  older line missing the new fields is **legacy**, never invalid.
- **`run-event` survives, narrowed.** It remains for events **no block command
  can observe from inside itself** — agent-side retries and subagent spawns
  (`--event retry|subagent`). It is no longer the mechanism by which a block's
  own start/end is recorded, and skill prose must stop asking for that.
- **Emission never fails a run.** A record that cannot be written degrades to one
  logged line, in the seam's standing degradation discipline; the block's own
  work is never blocked by its journal. A *malformed* record is a different
  matter and is a defect the validator catches at check time.
- **Publication boundary.** Records carry only the pointer grammar already public
  in this repository — no hub name, no hub layout, no real commit pin
  (`specs/spec-writing-assistant/SPEC.md`, publication-boundary clause). The
  `consulted:` line's existing pin handling is unchanged by CAP-5.
- Scripts are stdlib-only Python / POSIX shell in `scripts/` with `check-*.sh`
  harnesses (repo convention), and the check declares its `# tier:`,
  `# parallel-safe` and `# covers:` headers like every sibling.

## Non-goals

- **Token and cost accounting.** Output-token totals live in harness transcripts
  a run cannot see; the journal stays over workspace-derivable proxies, exactly
  as `_cost_proxies` already states.
- **Policing prompt-composed surfaces.** The five registry gates without code
  emitters (`thesis`, `journey-incorporation`, `gap-interview`,
  `narrative-structure`, `visual-set` — the list is declared at
  `scripts/draft_gates.py:333-337`) are **stated residue**, not scope: the
  correct move is to **shrink that surface by giving them emitters** — the
  direction the gate-carrier work (#1245) already started — and never to add a
  rule an agent must remember. Recorded here so its absence is not read as an
  oversight; it is scoped follow-on work, and it is **not a precondition** for
  anything in this spec.
- **A second journal.** Nothing here founds a new file, a new directory, or a new
  reader. One path, one format, more writers.
- **Retention, rotation, or garbage collection** of run workspaces — owned by the
  resolver and `docs/storage-architecture.md`, unchanged.
- **Any change to what the quality gate checks**, including the per-section
  evidence-type check whose silent skip motivated CAP-3. That repair is #1288's.

## Success signal

A run is driven end to end with no `run-event` call anywhere in the transcript,
and stopped deliberately at the quality gate as `20260802T185710-622820` was. Its
`run-events.jsonl` carries an open and a close record for every block that ran
— including the fill, the judging and the gate — each close record naming its
verdict, the draft hash it decided over, and its route; the gate's record reads
`ran-partially` and names the sub-check it skipped; the interview's record and
its `consulted:` line agree with the workspace's own contents rather than with a
config flag. A debugger reading only that file can say where the run stopped and
why, without opening the transcript.

## Assumptions

- The block↔command table (`skills/draft-article/SKILL.md:149-155`) is complete —
  that every functional block has exactly one mandatory command through which
  emission can be made unconditional. Where a block turns out to have none, that
  block is **cannot-determine** for this contract and is named as such in the
  implementing story rather than quietly exempted.
- The existing workspace already holds enough to derive CAP-5's reasons for the
  interview block. Whether every other block's "why not" is workspace-derivable
  is not asserted here; a block whose reason is only knowable from a flag is a
  finding to record, not a licence to record the flag as a fact.
