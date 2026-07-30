<!-- stages/complete.md — draft-article stage companion (Story 19.3, #744/#740). Loaded on entry to this stage by the
     SKILL.md dispatcher; carries the stage's full operating detail,
     moved verbatim from the pre-split SKILL.md. -->

## Emit the article plan (SPEC-article-plan CAP-1/CAP-2, Story 13.55)

At run completion — after the verified draft exists — emit the run's editorial
decisions as an **article plan** at `plans/<slug>.md` in the articles
repository, so they survive the disposable workspace and a later run can
consult them (Story 13.57). The plan is a **deterministic projection** of
artifacts this run already produced (journal, editorial anchor, dispositioned
answers, visual decisions, unresolved items) — **no new owner interaction**,
and regenerating it from the same artifacts is byte-identical.

**Carry the section→element map into the plan (Story 18.93, #668).** The
argument plan's **section-intents** block (each section → its element id(s),
content obligation, and evidence pointers) is a run-workspace intermediate that
vanishes with the workspace. Project it into the durable plan so the owner's
N-sections-vs-N-lessons review stays mechanical from one file:

- **Frontmatter `sections:`** — a **one-line JSON array** (the flat plan
  frontmatter parses no nested YAML), one item per section in order:
  `sections: [{"title": "Signals, not verdicts", "elements": ["el-signals-not-verdicts"]}, …]`.
  Every element id listed **must be in `consumed:`** (the writer refuses a
  section that places an element the draft never consumed — the grouping
  cannot drift from the consumption record). A multi-element section is a
  grouped cluster and is legal — recording it is exactly what makes the
  grouping reviewable.
- **Body `## Section plan`** — per section, the content obligation, its
  evidence pointers (pinned, carried verbatim), and the element's **CAP-9
  declared membership-rule one-liner**, so the grouping justification survives
  the workspace.

- **Frontmatter `structure_provenance:`** (#911, the F1–F5 demotion
  instrument) — **required beside `arc:`**: `framework:F2` when the accepted
  structure is the framework's own skeleton (sibling-lessons — including the
  no-choice default path), `bespoke` for any other accepted shape, with
  `+owner-edited` appended when the owner rewrote the accepted structure
  after adoption. The `structures` proposer already marks every candidate
  with its provenance — **carry the accepted candidate's value; never
  re-derive it here**. The writer refuses an `arc` with no
  `structure_provenance`: an explicit `bespoke` is a measurement, and a
  missing field surfaces as a missing measurement — never an implicit pass.

- **Frontmatter `resolved_defaults:`** (Story 20.62, #945;
  SPEC-article-draft-pipeline CAP-3, second clause) — every choice the run
  resolved by a **declared default**, recorded **in the plan** so it is
  **visible and overridable there**. A **journal or log entry does not
  satisfy this**: "merely logged" is the failure the clause names. A one-line
  JSON array, one item per resolved choice:
  `resolved_defaults: [{"choice": "audience", "value": "practitioners", "default": "practitioners", "declared_in": "config:article.audience", "axes": 1}]`.
  - **The axis count is the test**, never how important, confident or severe
    the choice looks — that test degrades under time pressure while an axis
    count does not. `axes` must be **1**; a **multi-outcome choice with no
    policy basis fires the gate** instead of being defaulted, and the writer
    refuses a record claiming otherwise.
  - **An undeclared default is not a default.** `declared_in` names where the
    default is declared (config key, policy line, framework template); with
    none, the choice is **asked**, never silently resolved.
  - **Overridable where shown:** `value` is what composition proceeds on.
    The owner changes it **in the plan** — no brief-gate re-run, no
    re-selection of the Strand set. `structure-record` prints
    `resolved_choices` (the effective values) and flags each `overridden`
    entry.
  - **Ideal path unchanged:** a brief whose choices are all single-axis with
    declared defaults asks **zero additional questions**, and a plan
    recording no resolution validates exactly as before.

`sections:` is **additive** — a plan without it validates exactly as before,
`consumed:` stays the consumption-exclusion key, and downstream consumers are
unchanged.

Assemble the plan text from run state and hand it to the sanctioned writer,
which validates fail-closed and places it. **Every source pointer in the plan
body must be pinned — `path:line@sha`, never bare `path:line` (#410, Tanuki
F81): the writer's schema refuses unpinned pointers every time.** Carry
pointers verbatim from the artifacts the plan projects (fact sheet, journal,
visual-set plan — all already pinned); never re-derive or hand-type a pointer
at assembly. First-attempt validity is the contract; the refusal is recovery:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/write-article-plan.py write \
  --slug <slug> --root <host-repo> "$WS/article-plan.md"
```

### Policy-conformance gate (SPEC-article-plan CAP-4, Story 13.76)

When the run consulted the policy seam (Stage 2 wrote `$WS/policy-surface.txt`),
run the conformance gate on the assembled plan **before** handing it to
`write` — a policy-seeded plan without conformance data is refused by the
writer:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/write-article-plan.py conformance \
  --plan "$WS/article-plan.md" --surface "$WS/policy-surface.txt" \
  --root <host-repo> [--staging "$WS/staging-candidates.md"] --write
```

- The gate validates every policy-seeded decision the plan records against
  the **same pinned policy result** the run consulted and the authoritative
  user config, then `--write` records `policy_pin`, `policy_config_version`,
  and `policy_conformance` (∈ `conformant`/`open`/`conflict`/`stale`) into
  the plan's frontmatter through the writer's fail-closed validation. The
  recorded status **rides the plan**.
- At plan emission a `conflict` or `stale` status is **recorded, not blocking**
  — the stage-progression block fired earlier, at the Stage 2→3 boundary
  (`policy-block-check`, Story 13.77), and the recorded status is what that
  gate **re-validates on the next resumed run** before Stage 3+ continues.
  Relay the status (and the findings' positions/pointers) in the completion
  summary's informational bucket.
- Pass `--staging` when the run emitted staging candidates: a plan decision
  that **reverses a served ratified line** is conformant **only as a proposed
  policy change** (its staging-candidate block exists →
  `reversal_as_proposal: true`); without the block it stays `conflict`. The
  reversal is never treated as current policy.
- The gate writes **nothing to any policy hub** — with `--write` it touches
  exactly one file: the plan.

- The frontmatter is the closed schema (SPEC-article-plan CAP-2): `kind:
  article-plan` (constant, the machine marker that keeps a plan **out of the
  evidence stream**), `slug` (equal to the filename stem), `intent`, `claim`,
  `status` (`outlined`/`drafted`/`superseded`), `run_id`, `pin`
  (`<source-repo>@<commit>`); optional `audience`, `policy_seeded`+`seed`,
  `relates`, and the CAP-4 conformance trio `policy_pin` /
  `policy_config_version` / `policy_conformance` (all three **required** when
  `policy_seeded: true` — the conformance gate below records them). Everything the draft or its variants own (title, summary, topics,
  language, …), machine state (journal/checkpoint/provenance map), and
  free-text `evidence:` are **forbidden** — the writer refuses them with
  per-key diagnostics. Every evidence reference in the **body** is a
  commit-pinned pointer or an interview-answer id, never prose.
- **Only the plan file is emitted.** No journal, checkpoint, or
  provenance-map data lands in the articles repository, and **nothing is
  written to the host source repo** — the footprint invariant is untouched.
- **Schema-less destination fallback.** If `output.drafts` points somewhere
  without the articles-repo schema, the writer lands the plan in user-scoped
  state (keyed by repo + slug, draft association intact) and creates **no**
  `plans/` directory in that destination. The write succeeds either way;
  check `dest --slug <slug>` first if you need to tell the owner where it went.

## Completion summary

End every run with the shared
[**completion summary**](../../completion-summary.md)
(`${CLAUDE_PLUGIN_ROOT}/skills/completion-summary.md`): the three labelled buckets
— **informational notes**, **publish blockers**, **optional cleanup** — followed
by an explicit **next step presented as an in-conversation choice** (here: "run
review-article on the draft / stop here" — interaction contract, CAP-6/#226:
paths are reference information, never a required navigation step). Because
this run produces an **article body**, the informational bucket includes a
**reading-time estimate**:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/reading-time.py --language <en|ja> <draft>
```

**The informational bucket also carries the run-level cost block (Story 19.8,
#742)** — elapsed wall time, stage retries, judge rounds, subagent count,
derived from the workspace's `run-events.jsonl` (with its basis named; an
absent journal reads as "unknown", never as zero cost):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py cost-block --ws "$WS"
```

Relay its `lines` verbatim. When `resume`/`autostart` reported a
`skill_contract_mismatch` (Story 19.9, #743 — the skill surface changed while
the run was in flight), relay its `disclosure` line **once** here too: the
run proceeded per the ratified automatic-resumption contract, and this note is
the record that it did so under a changed contract. The run-level `budget-check` (same data) fires the
existing budget-triage choice at a stage boundary when the configured
`run_budget` thresholds (config; shipped defaults 120 min / 12 judge rounds)
are crossed — an over-budget run is a decision, never archaeology.

The informational bucket also names **both persisted product paths** —
`drafts/<slug>.md` and `plans/<slug>.md`, copy-pasteable, taken verbatim from
the `complete` subcommand's JSON (the dual-product completion gate, Story
13.68). A run whose `complete` invocation failed has no completion to
summarize: surface the gate's hard error instead.

Any unresolved `[VERIFY]` marker or unrendered figure is a **publish blocker**,
listed under that bucket and nowhere else. A run stopped by the Stage 2→3
policy-block gate (Story 13.77) lists its block there too: the bucket carries
the `publish_blocker` payload — the conflicting **positions with pointers**, or
the moved pin/configVersion — plus the **resume path** (the block checkpoint;
resume re-presents the reconciliation question).

**Partial progress and the turn budget — the signal is an orderly stop, not an
advisory (Story 13.7; hardened by Story 13.85, #388).** The turn/compute
budget is a real ceiling. When a stage's budget-triage signal fires (a bounded
repair loop breached, or the invocation is visibly near its ceiling), do not
push on to hard failure — **stop in order**:

1. **Finish only the unit in progress** — never start a new source, section,
   or repair pass after the signal;
2. **persist at that boundary** — the sub-stage recording (Stories
   13.83/13.84) or, at a stage edge, the normal stage checkpoint — passing
   the partial-progress note on the final recording:

   ```
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py progress --ws "$WS" --stage <stage> --done <unit> \
     --stop-note "stopped at <boundary>; remaining: <what's left>"
   ```

3. **exit clean** — end the invocation with a short message naming the
   boundary reached and the resume path (autostart continues the run). A
   clean stop is a **normal end of an invocation**, distinguishable from
   failure; `error_max_turns` or a wall-timeout is a defect of this stop
   mechanism, never the expected end of an over-budget run.

On resume, `autostart`/`resume` return the recorded `budget_stop` note —
relay it in the completion summary's **informational notes** (last completed
boundary + resume path, per the shared completion-summary contract); the next
recording without a stop-note clears it. A partial run is recoverable, never
a silent loss.

## Platform variants — a separate post-review invocation

Variant emission is **not a stage of this flow** (SPEC-article-draft-pipeline
CAP-4; SPEC-platform-variants CAP-3, 2026-07-18 amendments). The draft flow
ends at the `complete` gate, with next step **review-article** — no platform
decision is presented during a draft run. Variants are emitted later, post-
review, by a standalone invocation that consumes the **persisted canonical**
at `<output.drafts>/<slug>.md` (SPEC-platform-variants CAP-1) — never a
workspace copy:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py variants --slug <slug> --root <host-repo>
```

The full contract — platform listing, the owner's explicit emission choice,
the lede re-targeting proposal, per-platform visual rendering, the platform
lint, the stale-variant check, the post-publish site record, and those
subcommands' flag reference — lives in [`variants.md`](../variants.md)
(`${CLAUDE_SKILL_DIR}/variants.md`). A canonical that exists only in a run
workspace is refused there with a pointed error naming the expected persisted
path — run `complete` first.

## Pipeline command reference (`draft-pipeline.py`)

Every draft-flow subcommand of `${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py`, in
pipeline order. This is the authoritative flag list — consult it instead of
`--help` or the script source. Positional args are shown in `<angle brackets>`;
`-` means "read from stdin". The variant-emission subcommands (`variants`,
`variant-staleness`, `site-record`) are post-review, not part of this flow —
their reference lives in [`variants.md`](../variants.md).

| Subcommand | Stage | Purpose | Args / flags |
|---|---|---|---|
| `stage0` | 0 | Config validation (CAP-5) + framework check + workspace autostart in one call (Story 13.13) | `<framework> <sources…>` `--root` |
| `start` | 0 | Framework check + run-state only, no workspace (granular alternative to `stage0`) | `<framework> <sources…>` `--root` |
| `autostart` | 0 | Resume the newest in-progress run, else mint a fresh workspace (Story 13.12) | `--root` |
| `checkpoint` | durability | Persist a completed stage's state to `<ws>/checkpoint.json` (Story 13.5) | `--ws` (req) `<state\|->` |
| `resume` | durability | Report where to resume a run from its workspace checkpoint | `--ws` (req) |
| `progress` | durability | Record sub-stage progress (completed units inside a long stage) into the checkpoint (Story 13.83); with `--stop-note`, records an orderly budget stop (Story 13.85) | `--ws` (req) `--stage` (req) `--done` (req, 1+) `--stop-note` |
| `consume` | 1 | Ingest the harvest fact-sheet document into pipeline state | `<harvest-doc\|->` |
| `interview` | 2 | Build the bounded gap-interview question set for the framework | `--framework` (req) `<state\|->` |
| `answer` | 2 | Record one owner answer (single form), or validate a batch | `--id` `--disposition` `--text` `--pointer` (repeatable) `--batch` `--candidates` `--selection` |
| `journal` | 2 | Write the interview journal (triage record, Story 10.4) | `--interview` (req) `--answers` `--seed-extra` `--policy-note` `--events` |
| `policy-block-check` | 2→3 | Stage-progression precondition (Story 13.77): blocks Stage 3 fill on an unresolved config↔policy conflict or a `conflict`/`stale` plan, emitting the publish-blocker payload + block checkpoint; `conformant`/`open` and generic mode proceed | `--classification` `--answers` `--plan` `--surface` `--config-json` `--root` `--config-version` `--staging` |
| `provenance` | 3 | Parse + structurally validate the sidecar provenance map | `--map` `--count` `--draft` |
| `quality-gate` | 3→4 | The mandatory quality gate; non-zero exit blocks Stage 4 (Story 11.4) | `--draft` `--map` `--judge` `--framework-file` `--state` `--profile` |
| `verify-markers` | 3/4 | Validate `[VERIFY: reason]` markers; `--count` prints the count (drive to 0) | `<draft\|->` `--count` |
| `verify` | 4 | Build the owner verification worklist, one entry per marker | `<draft\|->` |
| `reroute` | 4 | Reroute an over-budget section into a new bounded interview question (Story 4.5) | `--rewrites` (req) `--section` |
| `complete` | completion | The dual-product completion gate (Story 13.68): persist the canonical to `<output.drafts>/<slug>.md`, verify `plans/<slug>.md`, then (and only then) write the `next_stage: done` checkpoint; the only sanctioned way to finish a run | `--draft` (req) `--slug` (req) `--root` `--ws` |

---

**Completion is the terminus — there is no next stage file.** The run ends
**only** through the `complete` gate above ([`../SKILL.md`](../SKILL.md)); it is
the only sanctioned way to finish a run. Variant emission is **not** part of
this flow: it is a separate, post-review invocation documented in
[`../variants.md`](../variants.md).
