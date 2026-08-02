<!-- stages/stage0.md — draft-article stage companion (Story 19.3, #744/#740). Loaded on entry to this stage by the
     SKILL.md dispatcher; carries the stage's full operating detail,
     moved verbatim from the pre-split SKILL.md. -->

## Start — mint the run (one call)

**The run mint is a single invocation (Story 13.13)** — configuration validation
(CAP-5), the framework check, and workspace **autostart** (Story 13.12) fold into
one command so the run spends one turn here, not three:

```
S0=$(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py stage0 <framework> <sources...> --root <host-repo>)
WS=$(printf '%s' "$S0" | python3 -c "import json,sys; print(json.load(sys.stdin)['ws'])")
```

(`--root` — accepted by every plugin script that resolves the host repo —
defaults to the git top-level of the current directory and errors if cwd is not
inside a git repo; pass it explicitly whenever the session's working directory
might not be the host repo.)

Two **optional** owner directives ride the same call: `--depth "<level or
scope>"` (CAP-8, below) and `--element "<name>"` — the **named-element pin**
(CAP-9/#431) that scopes the whole run to one story element (see "Story-element
selection" below). Both are enhancers; absent them the run behaves exactly as
before.

**Say which repository you are operating on, first (#309).** `stage0` returns the
resolved `target`; make it the run's **first owner-visible line** — before any
scope read, workspace mint, or LLM spend:

```
Operating on host repo: <target>
```

An operation against the wrong repository is otherwise undetectable until the
work is already paid for, and with a `policy_source` declared a wrong target
seeds the interview from the wrong repo's recorded positions. If an explicit
`--root` disagrees with the session's cwd, the resolver prints a one-line notice
naming both — relay it; `--root` still wins.

It does, in order, halting on the first problem so nothing starts on a bad
config or framework:

- **Configuration validation (CAP-5).** Halts on any unresolved example
  placeholder, malformed URL (e.g. a double-slash `canonical_url`), or missing
  required key, printing a **per-key report** naming the file
  (`user-config.yaml` / `writing-sources.yaml`) and the fix — the report is
  `validate-config.py`'s verbatim. A clean config is silent. Relay any report and
  stop.
  - **A missing `writing-sources.yaml` is a hard stop, not a self-service fix
    (Story 13.11; placement amended by #211).** Do **not** proceed on a config
    you invented. The file lives in the **machine-global per-repo config —
    never in the host repo** (a host repo may be public, and this file can
    carry private pointers); resolve the exact destination with
    `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py sources-file --root <host-repo>`.
    Relay the error, then **offer to scaffold** a starter `writing-sources.yaml`
    at that resolved machine-global path as an explicit, owner-confirmed step;
    on consent create it from the example and show the owner the **path and
    contents** before re-running the mint; without consent, stop.
    Never scaffold silently, and never create the file inside the host repo.
- **Article-type check** against the **closed set** of intent labels and their
  `F1`–`F5` aliases (`resolve_framework`) — an invalid name exits non-zero and
  **nothing starts** (no workspace minted). Relay and stop. **An unmapped
  intent gets a reason and a nearest fit, never a bare label list (Story
  13.81):** the error states *why* there is no framework (the category set is
  ratified and closed — the four categories plus the working-note profile, all
  five enterable), names the closest sanctioned fit for the intent, and for a tutorial/how-to intent
  references the deliberate AP-10 exclusion (SPEC-article-frameworks) so the
  writer sees a decision, not a bug. Relay that hint verbatim — never
  fuzzy-select a framework on the writer's behalf; a mapped intent resolves
  exactly as before.
- **No sources gate — scope is DERIVED, never composed at a gate (Story 20.147, #1209; amended 2026-08-02 — the amendments companion is the authority).** The owner supplies at most a REGION at the brief; which repositories may be examined comes from the brief's `examine_scope` — the union of the selected Strands' served `projects:`, carried on the brief record — and the per-claim examine step does its own enumerating at the read ([`examine.md`](examine.md)).
  Never ask the owner to compose or approve a file list or a scope selection — the retired gate's 2026-08-01 defect (recommending "all declared sources", 423 files, 78% code, to an episode-claims article) has no gate to be constructed at; a repository outside the derived scope is refused, not searched; and with no brief-carried scope, the recorded `<sources...>` selection stays a filter within `writing-sources.yaml`, never a widener.
- **Workspace autostart** — resumption is **automatic, not opt-in**; on a `--brief` invocation automatic means **same-brief-only** (amended 2026-08-02, #1207 — the amendments companion is the authority: a different-brief run is skipped fresh via `fresh_skipped`, nothing deleted; cold invocations unchanged below). It resumes
  the **newest in-progress run** (a workspace whose checkpoint records a
  `next_stage` other than `done`) when one exists, returning `"resumed": true`
  and the `next_stage` to continue from — **skip straight to that stage**, reusing
  the persisted intermediates. **A resume announces itself at turn one (Story
  19.10, #746):** relay the returned `resume_disclosure` line — run id, age,
  and subject from checkpointed state — immediately after the #309 target
  line, so a topic mismatch is visible before anything is spent. The owner's
  explicit opt-out is `--fresh`: it mints a new workspace, leaves the
  in-progress run untouched (its id returned as `fresh_skipped` with a
  `fresh_note` to relay — nothing is deleted), and the ratified automatic
  default is unchanged when `--fresh` is not asked for. Otherwise it mints a fresh workspace with
  `"resumed": false` and `next_stage: probe` (the no-false-resume path). A large
  multi-source draft completing across several invocations is the **normal
  model** — a turn-ceiling casualty simply continues next invocation.

On success `stage0` prints one JSON: `{"config_ok": true, "run_state": {…framework,
framework_file, sources…}, "resumed": …, "ws": …, "next_stage": …}`. Carry
`run_state` into the next process unchanged and write every intermediate under `ws`.
(The underlying `validate-config`, `start`, and `autostart` commands still exist
for standalone use; `stage0` composes them.)

`$WS` is a fresh per-run workspace directory **outside the host repo**
(`docs/storage-architecture.md` D2), resolved by the path resolver — never a
path you compose yourself, and never the host working tree. Its internal layout
is resolver-internal; always ask the resolver, never spell it out. The probe
record (`probe.json`, #1182), interview answers, the provenance map, quality-gate
output, and any scratch all live under `$WS/`; there is no state-vs-cache split.
The **only** files this pipeline writes into the host repo are the declared
products at `output.drafts` (the `complete` gate). Pass `$WS` to probe so it writes
there rather than minting its own workspace.

**Artifact-write precondition (Story 13.78).** The harness Write tool refuses
to overwrite a file that has not been Read in the current session (`File has
not been read yet`). Two situations make a pipeline target already-exist:
**re-writes** (the fill's revision loop, a regenerated provenance map, a
visual *modify*, re-entry after a policy block) and **resumed runs**, where
every artifact persisted by a prior invocation exists but nothing in this
session has Read it. So before every Write to a `$WS` path (or any path this
run may have written before): **Read the target first if it exists; only a
path minted fresh this turn may be written blind.** On a resume, treat every
existing workspace artifact as unread. Writes routed through the pipeline
scripts (`stage0`/checkpoints, `journal`, `complete`,
`write-article-plan.py`) are exempt — the precondition applies only to the
Write tool, and burning retry turns on it is a known budget leak (#388).

### Story-element selection — the model and its disclosure (CAP-9, #428)

A lesson-based article covers **story elements**. A **story element** is a
general **evidence cluster** — a set of fact-sheet entries grouped by a
**declared, deterministic membership rule** (a shared `## Journey` lesson unit,
a shared framework slot, a co-pointed evidence set); an F2 lesson is **one
case** of a cluster, not the only one. Membership is **reproducible from the
declared rule** — the same fact sheet yields the same clusters — and **never a
taste judgment**.

Each element carries a **stable id**. The relation is explicit: the **id is
identity** (two elements are the same iff their ids match), the
**evidence-pointer set is derived payload** *under* the id, and **pointer drift
on re-harvest never changes identity** — a moved pin or a re-pointed entry
updates what the element points at, not what the element *is*. Anything keyed on
the id (consumption, CAP-3) survives re-harvest.

**Mint the id mechanically — never free-choose the token (CAP-9/#428, #529).**
The id is a **deterministic function of the cluster's declared membership
anchor**, derived by the tool, never a token you invent per run (that is the
#529 root cause: one run wrote `el-weak-driver`, the next `weak-driver`, so
id-keyed exclusion could never fire). Derive every element's id with:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/write-article-plan.py element-id "<the cluster's declared membership anchor>"
```

The **anchor** is the cluster's **primary declared identity in the fact sheet** —
the label the declared, deterministic membership rule names the cluster by (for
an F2 lesson: the lesson unit's declared title/claim as harvested, e.g.
`Weak driver`). The tool casefolds, drops an already-derived `el-` prefix, and
slugifies it to `el-<slug>` — a **byte-identical** result for the same anchor
(`Weak driver`, `weak-driver`, and `el-weak-driver` all resolve to
`el-weak-driver`). Because the anchor is read from the fact sheet, not chosen
freshly, **two runs over the same fact sheet mint the same ids** and id-keyed
consumption exclusion fires across runs. An anchor the tool cannot slugify
(`ok: false`) is a **defect** — fix the declared membership rule, never hand-mint
a nameless id.

Selection chooses which elements the article covers, **upstream of the argument
plan** (CAP-3/#440 composes *from* the selected elements). The **selection rule
is #428 disclosure-only**: surfacing it changes **nothing** about what gets
selected — with the same fact sheet, two runs select the same elements. What
CAP-9 adds is that the rule is **stated, not implicit**:

- the **interview journal** records, **per selected element, the rule that
  selected it** (id + the declared reason — e.g. "Journey-bearing cluster,
  unconsumed, matched framework slot X"); and
- the **completion summary** repeats the per-element selection reasons in its
  informational bucket, so the owner sees *why each element is in the article*
  without opening a run artifact ([`completion-summary.md`](../../completion-summary.md)).
  Any consumption statement it makes **names the population it covers** — see
  the population rule under Consumption exclusion below (CAP-9, #732).

An element the run selected but whose reason cannot be stated is a defect, not a
silent omission — disclosure is required wherever selection ran.

**Consumption exclusion — default to unconsumed (CAP-9, #430).** Lesson-based
selection **defaults to the elements no prior draft has consumed**, so drafting
repeatedly from one repo does not reselect covered material by chance:

- A completed draft **records the story-element ids it consumed** in **its
  article plan** (`plans/<slug>.md`, the `consumed:` frontmatter key —
  SPEC-article-plan). This is the **only** consumption record: **no new store**.
- Selection computes "already consumed" from the **`project_consumed_index`** the
  plan consultation returns (`write-article-plan.py consult --project <project>`
  — see below) — a view **regenerated from every `plans/*.md` on each call**,
  scoped to plans that belong to **this run's project** (the pin's repo
  component, `_plan_project` — the SAME membership rule differential-context
  uses, **not** a pin-sha or exact-slug match, #529). An element whose id appears
  there is excluded from the default selection.
- Because consumption is keyed by **element id** (identity, 18.8), it **survives
  re-harvest**: a moved pin or re-pointed entry changes the payload, not the id,
  so a consumed element stays consumed. Mint every candidate element's id with
  `element-id` (above) so the id it is keyed on **reproduces across runs** —
  without the mechanical derivation, the same cluster gets a different id each
  run and exclusion can never fire (#529).
- **The "first article on this project" claim is PROJECT-scoped and evidenced
  (#529).** State it **only** when the `plans/*.md` scan finds **no** plan for
  this project — mechanically, when `consult`'s `project_plans` is empty. The
  claim **names the scanned location** (`plans/*.md`). When `project_plans` is
  **non-empty** you may **not** claim a first article: exclusion was checked
  against those plans, whether or not any element was skipped.
- **Every consumption statement NAMES THE POPULATION it covers (CAP-9, #732).**
  Same shape as the project-scoped claim above, for the same reason: a claim
  whose scope is unstated is read at whatever scope the reader has in mind.
  Wherever consumption is stated — the completion summary, a selection
  disclosure, a gate item — say **which set**: *"all 4 of the 4 story elements
  this run minted are consumed"*, or *"none of the 11 elements across this
  project's plans is unconsumed"*. Never a bare quantifier.
  **Forbidden, with the reason:** phrasing a consumption statement as coverage
  of the hub's Lessons. A run reported **"every core lesson has been consumed"**
  while the owner's estimate was that under 10% of the lessons learned building
  the project had reached an article — and **both were true**. A story-element
  id is derived from the *cluster's declared membership anchor* in the fact
  sheet (`element-id`, above), so it is minted from **this repo's declared
  sources** and is **never a hub Lesson slug**; the two quantify over disjoint
  namespaces with nothing converting between them. So "core lesson", "all the
  lessons", and any wording that reads as coverage of the hub Lesson pool are
  **out** — not because they overstate, but because they name a set this run
  cannot see.
  **This adds no capability and no mapping.** The machine-readable
  Lesson-citation join key does not exist and belongs to the articles repo, not
  to this tool (CAP-9's own open question); the coverage question stays
  unanswerable here. The rule is only that a statement says what it counted.
- **When exclusion DOES fire, disclose it.** Every element skipped because a
  prior article on this project already consumed it is disclosed in the interview
  journal and the completion summary — the skipped element's **id** and the plan
  that consumed it (from `project_consumed_index`) — so a defaulted-away element
  is stated, never silently dropped (the same per-element disclosure the
  selection rule requires above).
- The exclusion is an **owner-overridable default**, never a hard filter: the
  owner may **re-cover** a consumed element (surface it as a proposal under the
  [proposal contract](../../owner-facing-proposal-contract.md); a re-cover is the
  owner's to ratify). With **no plans for this project**, nothing is excluded and
  selection is exactly as today.

**Exclusion gates SURFACING, never PERMISSION (Story 18.47, #560).** The default
above is about **what the selector offers first**, never about what the owner is
allowed to ask for. An entry that **explicitly names** an element a prior article
already consumed is **honoured** — the run states that it was consumed and by
which plan, and proceeds. Refusing it, or re-asking for confirmation, is the
failure this clause exists to prevent
(`threshold-gates-surfacing-not-permission`). Resolve
it mechanically rather than by judgement:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py entry --element "<name>" --consumed-index <consult-output.json>
```

Each named element comes back `honoured: true`, carrying `consumed_by` and the
disclosure line when it was consumed. **Default (unnamed) selection is
unchanged** — this clause changes permission semantics only, never the default
surface (#430 intact).

**One entry mechanism — the named-element pin is its degenerate case (CAP-9,
#431, generalized by the 2026-07-22 #554 amendment).** An entry is the owner's
**free-form description of the story they want**; an entry that **names an
element** is the **degenerate case of that same path** — a request whose named
set has exactly one member. It is **not a separate code path and not a second
described mechanism**: `_entry_request` resolves both, `state.entry` records
which form was used, and `state.element` is **projected from it**, so the pin's
guarantees below hold by construction rather than by a parallel implementation.

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py entry --request "<the owner's free-form description>"
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py entry --element "<name>"    # the degenerate case
```

The owner can say **"write the article about *this* element"** by passing
`--element <name>` to the run mint (recorded as `state.element`, projected from
`state.entry`). When set:

- the name **resolves to an element id** (18.8) and **selection is pinned** to
  it — no other elements are selected, and the disclosure above states the pin
  as the selecting rule;
- **examine grounds claims for that element alone** (during the fill,
  [`examine.md`](examine.md)), and the **interview covers that element's gaps**;
- the pin **scopes** the run — it does **not widen the declared-source
  boundary**. Examine still reads only the writing-sources-declared files (the
  recorded sources are a filter, never a scope widener); it just examines claims
  for the one pinned element. A named element outside the declared sources finds
  no evidence there — the pin never reaches past the source boundary to get it.

With **no** `--element`, selection is exactly as above (the default, disclosed
rule) — the pin is an optional owner input, never a required gate. The
**declared-source boundary is identical for both entry forms**: naming an
element and describing a story free-form each scope the run, and neither reaches
past the writing-sources-declared files.

### Depth/scope directive (CAP-8, #432)

Article depth is **owner intent, never a tool default**. If the owner's
invocation names a depth or scope — a level (`deep-dive` | `standard` | `note`)
or a one-line scope statement ("just the retry bug, deeply") — pass it to
the run mint so the run records it:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py stage0 <framework> <sources...> --depth "<level or scope>" --root <host-repo>
```

The run-state then carries `depth: {"level": …}` or `depth: {"scope": …}`. If
the owner gave **no** directive, do not invent one — the offer is presented
**exactly once as a gap-interview item** under the proposal contract, and
the answer is recorded; absent an answer, the run proceeds exactly as before.

**The offer is generated mechanically, not left to this prompt (Story 18.42,
#542).** It was previously only an instruction here, so any path that skipped
the prompt lost it silently — run 20260722T095152 re-entered via the
scope-ratification screen and defaulted the depth without ever asking, exactly
what "owner intent, never a tool default" forbids. `interview` now emits the
offer itself whenever run state carries no directive, as a **mandated-tier**
item (so the ≤5 cap cannot displace it), and reports the accounting:

- `depth_offer: "presented"` — no directive, the offer was made;
- `depth_offer: "directive-present"` — a `--depth` directive (or a prior
  invocation's recorded answer) exists, so it is **not** re-asked.

This holds on **every fresh or re-opened/narrowed run** — re-entry regenerates
it from state, so there is no path that silently defaults. The offer **trails**
the capped questions so the claim/angle question keeps presentation slot 1.
Before reporting completion, assert the accounting:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py depth-check --interview "$WS/interview.json"
```

Exit 0 means the run either carried a directive or was offered the choice.
Exit 1 means neither — **disclose the applied default in the completion
summary's informational notes** rather than shipping a silent default.

**Reading-time bands as the depth-choice unit (CAP-8 clause, Story 18.27,
#506).** The run-mint / gap-interview depth question **may** present **suggested
reading-time bands** derived from the selected elements — `~3 min note / ~7 min
standard / ~15 min deep-dive` — **plus a custom value** the owner can type when
no band fits. Get the bands (scaled by the selected-element count) from:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/reading-time.py --bands --elements <selected-element-count>
```

The owner's pick is **recorded AS the depth directive** — each band maps to a
level (`{"level": "deep-dive"}`), captured exactly like a `--depth` answer —
and is **never a reading-time target**. Reading-time is only the *unit in which
the owner expresses* the depth choice; fill still elaborates by depth semantics
(above), the reading-time estimate stays **informational** (CAP-6), and
**nothing auto-splits or auto-trims** to hit the number. A large miss between
the chosen band and the finished estimate surfaces as an **informational FYI**
(pass the chosen band to the estimator, `reading-time.py … --band-minutes <N>`;
the owner decides), never an automatic cut. With **no directive** at all, the
run is **byte-for-byte the behavior before CAP-8** — the bands are an optional
way to *ask*, never a new gate.

**At the fill, generation consumes the directive** (`state.depth`): it governs **how
much each slot elaborates and how many story elements the draft carries** — not
a word count or reading-time target. A **deep-dive** keeps material a
framework's split hint (e.g. F2's ">3 lessons") would otherwise cut in **one**
article; a **note** stays tight. When a framework's count/length split hint
would fire, surface it as an **owner choice** ("~N lessons — one deep-dive, or
split?"), **never an automatic split** (the hint is a declinable suggestion per
CAP-8). With **no directive**, fill behaves exactly as before, and the
reading-time estimate stays informational — it drives no split.

### Owner coverage brief (CAP-9-aligned, Story 18.24, #505)

Beyond the one-element `--element` pin and the one-line `--depth` scope, the
owner may hand the run a **free-form coverage brief** — "what this article
should cover", in their own words. Pass it to the run mint as **text or a file
path**:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py stage0 <framework> <sources...> --brief "cover the retry storm and how the judge missed it" --root <host-repo>
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py stage0 <framework> <sources...> --brief path/to/brief.md --root <host-repo>
```

The run-state then carries `brief: {"text": …, "provenance": "owner-authored",
"origin": "inline"|"file"|"brief-record"}` — recorded with **owner-authored
provenance**, like an interview answer; the brief is the owner's words, never a
tool-invented scope. The brief then shapes three stages, all **inside the
existing boundaries**:

- **Selection** — the brief **maps to story-element clusters** (CAP-9): each
  brief item selects its matching cluster, disclosed per element exactly as any
  selection is (interview journal + completion summary). A **brief item matching
  no cluster is never silently dropped** — it surfaces as a **NEEDS-OWNER gap**
  or an interview question ("the brief asks for X but no evidence cluster
  covers it — is it out of scope, or a gap to fill?").
- **Argument plan** — the brief **supplies the owner's thesis candidate** (the
  thesis the owner already holds), fed into the fill's argument-plan sub-step.
  The disclosure trail is **unchanged**: the thesis is still owner-attributed,
  and every checkable claim stays sourced/derived.
- **Directed grounding** — examine **emphasis follows the brief WITHIN the
  writing-sources-declared files** ([`examine.md`](examine.md)). The brief
  **must not widen the source
  boundary**: exactly like the #431 `--element` pin, it is a **filter/emphasis,
  never a scope widener** — it never adds a file, never reaches past the
  declared sources, and the **promotion-gated `q_a` staging area stays
  unreachable** (promotion is the only path in). A brief item whose evidence is
  not in the declared sources is a
  NEEDS-OWNER gap, not a reason to read further.

At completion record `brief_provenance` **matching the actual producer** (Story 20.94, #1050): `owner-authored` when the owner typed the brief, `terrain-adopted` when it arrived composed from a selection they made over enumerated alternatives — both are the owner's scope, and neither is a tool-invented one. With `terrain-adopted` also record `brief_source` as one-line JSON, `{"pins": {"terrain": ..., "hub": ...}, "artifact": ...}` — **pins first**, because the path is a state-dir location that goes stale by relocation while still looking authoritative, and the pins identify the material without it.
**Nothing reads that pointer and no stage may** — it is never opened, stat'd or followed — and **no stage branches on `brief_provenance`**: the draft, the examine emphasis and the argument plan are byte-identical either way. Resolving it would oblige this pipeline to know another producer's rendering, invocation and lifetime; a value nothing reads creates no such obligation.
With **no** `--brief`, the run behaves exactly as before — the brief is an
optional owner input, never a required gate.

**The brief record and its journey arcs (Story 20.91, #1044).** A `--brief` FILE that is a JSON object carrying a `brief` string is a **brief record**: the string is used unchanged (so every behaviour above is untouched), and the members it was composed over contribute `journey_arcs` to run state — `{"at": <pins>, "arcs": [{index, slug, arc, arc_cite, served, not_served_reason}, …]}` — **beside `sources`**, as declared source material at the recorded pin, **alongside the host-repo sources and never in place of them**. `sources` is untouched: an arc is not a repository, the boundary is not widened, and repositories remain examination **scope**, never evidence binding. Recognition is by **shape**, which makes this a **format and never a producer** — nothing here detects, names, imports or resolves who wrote the file, an owner can hand-write one, and anything else stays a plain text file read exactly as before. Each arc travels **quoted at its cite in the register it was served in**; no stage rewrites it into a rule, a summary or a claim before the drafting decision. An absent one carries `served: false` with its `not_served_reason`, so *"no arc exists"*, *"no arc arrived"* and *a record predating the field* stay three findings and never collapse into one.
**The article floor is unchanged**: every article still carries ≥1 Fact — a sourced or derived claim resolving at the ship gate — and **an arc alone never satisfies it**. An arc arriving is new material, not a new licence, and missing per-Strand facts stay disclosure rather than failure. (The host-repo recording task this paragraph used to hold the arc apart from was retired with the join that minted it — SPEC-writing-assistant, amended 2026-08-01, #1183 — so there is no longer any recording task an arriving arc could be mistaken for discharging. The arc's own status is unchanged: material, never a Fact.) This makes arcs **available** and decides nothing about prose: whether one enters as a worked example, a short story, or a standalone paragraph is **parked** (#1045) behind the first draft composed with arcs available, and a stage that picks one has decided a parked question. Distinct from the completion-time `brief_source.artifact` pointer above, which is never opened, stat'd or followed — this record is an **input handed to the gate** through the `--brief` contract that has accepted a file since Story 18.24.

### Plan consultation at draft start (SPEC-article-plan CAP-3, Story 13.57)

After the run mint, before the interview, **consult existing article plans** in the
articles repository — serial engineering-lessons articles should build on prior
decisions instead of repeating them. The read is **read-only through the repo's
schema** — nothing under the articles repository is created or modified by
consultation, and plan content **never enters the harvest evidence stream**
(Story 13.56's fences apply):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/write-article-plan.py consult --root <host-repo> --project <related.projects>
```

It returns each prior plan's discovery surface (slug, intent, claim, status,
pin, relates, **consumed**) plus a **`consumed_index`** — every story-element id
any plan records as consumed, mapped to the plans that consumed it — and, scoped
to **this run's project** (`--project`, defaulting to the host repo basename): a
**`project_plans`** list (the plans whose `_plan_project` matches, the projected
scan of `plans/*.md`), a **`project_consumed_index`** (the same map restricted to
those plans), and **`scanned`** (`plans/*.md`, the location any first-article
claim must name). The **`project_consumed_index`** is the **consumption-exclusion
input** (CAP-9/#430): it is a **view regenerated from `plans/*.md` on each
call**, so lesson-based selection defaults to the elements **absent** from it
(see "Story-element selection" above); `project_plans` being **empty** is what
licenses the "first article on this project" claim, and non-empty forbids it.
From this surface you **may surface plan-grounded proposals** — each
under the [owner-facing proposal contract](../../owner-facing-proposal-contract.md),
**none auto-applied**:

- "article Y already covered X — link to it instead of re-explaining";
- "lesson Z has new evidence since `<pin sha>` — update it?";
- a **continue / fill / update / new** recommendation for how this article
  relates to the prior plans (recorded as `relates` on the plan this run
  eventually emits).

**The tool never applies a prior plan.** Every proposal is the owner's to ratify
or decline. A **declined** proposal leaves **zero friction and no residue** —
the run proceeds exactly as if the proposal had never been surfaced (the
presented-payload log keeps the decline, like every other proposal). A
repository with **no plans, or a schema-less destination, degrades silently**:
`consult` returns an empty list with a reason, and the run behaves exactly as it
does today — never a failure, and never a prompt about missing plans.

### Continuation mode — build on a named prior article (Story 13.95, #429)

The plan consultation above **discovers** how this run relates to prior work;
**continuation mode** is the owner **directing** it. When the invocation carries
a `continuing <prior-slug>` modifier —

```
draft article <type> from <sources> continuing <prior-slug>
```

— the owner has pinned the relation, so this run does not re-discover it:

1. **Read the named prior canonical** at the resolved `output.drafts`
   (`resolve-writing-sources.py draft-location`) and select its plan entry from
   `write-article-plan.py consult` (which returns every prior plan's discovery
   surface — pick the `<prior-slug>` row) — **frontmatter and `summary` only**,
   read-only through the repo schema. The prior draft's
   **body never enters the harvest evidence stream** (Story 13.56's fences hold
   exactly as for plan consultation); it is *framing context*, not a source.
2. **Constrain the lede at the fill** to **build on** the prior article rather
   than restate it: the opening assumes the prior claim/summary as given and
   advances from it, instead of re-explaining shared context. This is a directed
   emphasis on the drafting agent, not new evidence and not a new provenance
   class — every checkable claim stays sourced/derived as always.
3. **Record the relation in the emitted draft's frontmatter** —
   `related.articles: [<prior-slug>]` — and as `relates: continue <prior-slug>`
   on the plan this run emits, so the chain is machine-legible for the next run's
   consultation.

If `<prior-slug>` resolves to **no canonical or plan**, surface it under the
[owner-facing proposal contract](../../owner-facing-proposal-contract.md) —
"no article `<prior-slug>` found; draft standalone, or correct the slug?" —
never a hard failure. Continuation is an **enhancer**: with no modifier the run
behaves exactly as today (auto plan-consultation only).

### Differential context — compress-and-link prior-article coverage (Story 18.23, #504)

Consumption exclusion (CAP-9/#430) stops the run re-covering a story **element**
the owner already published; **differential context** stops it repeating the
surrounding **tissue** — the same introductions, shared setup, and warnings a
prior article on the **same project** already carries. This is **automatic**,
like continuation mode, not gated on an explicit `continuing <slug>`: whenever
prior published/drafted articles **share the project** (`related.projects`), the
argument plan receives a **prior-coverage digest**. Compute it after the run mint,
alongside plan consultation, over the **existing carriers** — `plans/*.md` and
the prior canonicals — **never** the policy hub, and with **no schema change**
(the project a plan belongs to is the repo component of its recorded `pin`):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/write-article-plan.py differential-context --root <host-repo> --project <related.projects>
```

It returns, for each prior article sharing the project, a `prior_coverage` entry
— **slug + summary + its Context span + its warning spans** — read from the
plan and the canonical's frontmatter/body exactly as continuation mode reads a
named prior article. **The prior body never enters the harvest evidence stream**
(Story 13.56's fences hold exactly as for plan consultation): the digest is
**framing context**, not a source, and no checkable claim is ever sourced to it.

At the fill, the argument plan treats repeated context as **compress-and-link**,
not re-explanation: where this article would re-introduce shared setup a prior
article already established, write a **one-sentence recap plus a pointer** to
that article (`related.articles`) instead of re-explaining it. A **warning
repeats only when it is load-bearing for THIS article's claim** — a caveat the
digest already carries is otherwise linked, not restated. This is a directed
emphasis on the drafting agent, not new evidence and not a new provenance class.

With **no prior article sharing the project**, the digest is **empty** and the
run behaves **exactly as today** — the compress-and-link machinery never fires,
and nothing about a first article on a project changes.

### Durability — checkpoint each stage, resume from the last completed one (Story 13.5)

Wall-clock is unconstrained but the **turn/compute budget is a real ceiling**, so
the pipeline is resumable: **after each stage command emits its output state,
checkpoint it** so a re-invocation continues from where it stopped instead of
restarting (a turn-ceiling casualty is recoverable, not a total loss). The stage
state already carries `next_stage`; persist it:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py checkpoint --ws "$WS" <stage-state.json>
```

The write is atomic and idempotent — checkpointing the same stage twice is a
no-op, and because the checkpoint records `next_stage`, resuming
**never re-runs a completed stage**. The mint's `autostart` (above) already picks
the right workspace and `next_stage` automatically; `resume --ws "$WS"` inspects a
specific workspace's checkpoint directly when you need it:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py resume --ws "$WS"
```

**Sub-stage progress inside long stages (Story 13.83, #388).** The stage-level
checkpoint alone is not enough for the long stages: an evidence-heavy run that
dies *mid-stage* would replay the whole stage every invocation and never
converge. So the long stages also record **sub-stage progress** — one call per
completed unit of work (batchable):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py progress --ws "$WS" --stage <stage> --done <unit> [<unit> …]
```

The upsert merges `progress.<stage>.done` into the existing checkpoint
(preserving `run_state` and stage state), is idempotent per unit, and refuses
a stage the run has already completed. **Record a unit only after its
artifacts are durably written** — the recording IS the boundary, so a
half-written unit is never marked done. On resume, `autostart`/`resume` return
the `progress` object with the rest of the state: **skip the units it lists**
and continue from the first unrecorded one. A stage's normal completion
checkpoint overwrites the file, clearing its sub-stage progress. Probe is
atomic at `probe.py record` (#1182) and records no sub-stage progress; the
long later stages do.

**The gap interview records per answered question (Story 18.38,
#533).** The interview presents a deterministic ordered set (`interview`'s
`presentation_order`). Probe is non-interactive — the
only ≤5-question elicitation loop is *this* stage — so it is the interruptible
question loop the #533 ESC-then-resume burned. After each question is answered
(recorded via `answer`/`journal`), mark it done:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py progress --ws "$WS" --stage interview --done <question-id>
```

On a resumed interview, recompute the presented set (deterministic — same ids)
and re-enter at the **next unanswered question**, never re-asking an answered
one. The remaining questions are a mechanical set-difference, not a judgment
call:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py interview-remaining --ws "$WS" --present <id> <id> …
```

It prints the presented ids not yet in `progress.interview.done`, in
presentation order (empty = every question answered, so the interview is
complete and the run advances to `fill`). This is the elicitation half of the
2026-07-22 (#533) durability amendment.

**Disclose before re-spending on a resume, and stop orderly on the resume path
too (Story 18.39, #533).** The #533 failure was a resume that spent a large
token volume with **no visible explanation of what the spend was doing**. On
**every resumed run** (`autostart` returned `"resumed": true`), before spending,
emit the one-line disclosure of what the resume will do — the stage it resumes
at, the already-done units it will **skip** (never re-spend), and any pending
budget-stop note it relays:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py resume-disclosure --ws "$WS"
```

Empty output means a fresh run or a completed one — nothing to disclose. And the
budget-triage **orderly stop binds identically on a resumed invocation**: a
resumed stage that breaches its budget persists at the next sub-stage boundary
with `progress … --stop-note`, records the CAP-6 partial-progress note, and
exits clean — exactly as a fresh run does. Budget triage is never a
fresh-run-only path, and a resume never silently re-burns a budget.

**End EVERY invocation with the stop-side run-status line (Story 18.91, #665).**
On any exit path that is not a `complete` — a turn ceiling, a budget stop, an
interview pause, an elected pause, a session end — the **final owner-visible line**
of the invocation is the deterministic run-status line: the workspace id, the
stage it stopped at, and (whenever `next_stage` is not `done`) an explicit
"no draft persisted yet — re-invoking `draft-article <repo>` resumes at
`<stage>`", so the owner never has to diff directories to learn what the run did.
It renders from the checkpoint alone:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py stop-disclosure --ws "$WS" --repo <host-repo>
```

Unlike `resume-disclosure`, this speaks on **every** stop including a run with no
checkpoint yet — the guarantee is that no invocation ends silently. A completed
run defers to the `complete` gate's persisted-path relay below and never restates
it.

**An ELECTIVE pause is an owner gate, rendered as a selection (Story 18.94, #667;
SPEC-article-draft-pipeline invariant, 2026-07-24).** The line above covers
*involuntary* stops (turn ceiling, budget triage). This governs the pauses the
agent *elects* while contracted work remains — and an elected pause has none of a
gate's properties unless you give it them:

- **Elective pauses are permitted only at an ENUMERATED sanctioned point.** The
  sanctioned points are the involuntary contracted stops (the turn-ceiling
  casualty and the budget-triage orderly stop) plus a stage boundary explicitly
  carrying large declared spend. **Absent a sanctioned point, the default is to
  continue the contracted chain** — do not stop and ask.
- **A bounded contracted step is NOT a pause point.** Electively stopping
  immediately before a defined bounded step of a stage — e.g. the evidence-type
  **`repair-hop`** (below), a re-judge, a re-gate — inverts the gate model: gates
  end in actions, and a gate's outcome executes in the same sitting. Finish the
  bounded step; do not pause in front of it.
- **When you do elect a sanctioned pause, render it as a gate, not prose.** Its
  **first line leads** — `PAUSED (elective) · run <ws> · stage <next_stage> · one
  action` — never below a status report, and it presents an **explicit selection**
  ("Continue now (<the bounded work>) / Pause here (resumes automatically at
  `<stage>`)"), the same option-screen contract the interview uses. **No selection
  presented ⇒ no elective pause.** A trailing "say *continue*" is the exact
  anti-pattern this replaces.
- The pause is disclosed by the stop-side run-status line above (elected pauses
  are one of its named exit paths).

**Mark the run done on completion — through the completion gate (Story 13.68).**
When the pipeline finishes, run the `complete` subcommand. It is the **only
sanctioned way to finish a draft run** — never hand-write the final
`next_stage: done` checkpoint:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py complete \
  --draft "$WS/<draft>.md" --slug <slug> --root <host-repo> --ws "$WS"
```

The run's declared products are **two** (SPEC-article-draft-pipeline,
2026-07-18 amendment; SPEC-platform-variants CAP-1): the canonical draft at
`<output.drafts>/<slug>.md` and the article plan at `plans/<slug>.md` — **both
must be durably persisted before completion may be reported**. `complete`
persists the canonical (with the emission trailer carrying its content hash,
the same convention the variants stage records), verifies the plan exists at
its resolved destination (the schema-less **user-scoped fallback counts** as a
successful plan write), and only after BOTH products verify writes the final
`next_stage: done` checkpoint so `autostart` treats the run as complete. A
failed write of either product is a **hard error naming the product and path**:
the run never reports "complete", and the checkpoint never records
`next_stage: done` over a workspace-only canonical. The gate applies whenever
`complete` runs, so a resumed run checkpointed before this contract is never
grandfathered. On success the JSON names **both persisted absolute paths** —
relay them in the completion summary's informational notes. Re-running
`complete` over already-persisted products re-verifies and succeeds
(idempotent).

**`complete` also runs the destination repo's `lint-article` on the persisted
canonical (Story 18.99, #674)** — authoritative by pointer, no rule copying. A
frontmatter **bounds** violation (`summary` > 240, `title` > 70) is a **hard
error** with no `next_stage: done` checkpoint, exactly like a failed product
write — a run never reports "complete" over a canonical the destination repo
rejects on schema. Every other lint class (`pointer`, `headings`, `links`,
`template`, missing-field schema) is a **disclosed warning** in `complete`'s JSON
(`lint_warnings`) — relay it in the completion summary; style rules never block
completion.

**The articles repo's `INDEX.md` is regenerated at persist (Story 18.43,
#540).** The repo declares it "regenerated — one line per
backlog/draft/newsletter item", but nothing carried that duty out: a repo
holding 4 drafts read `_Empty._`, so a just-persisted draft was invisible on
its browsing surface. `complete` now rewrites it as a **deterministic
projection over the item frontmatter the pipeline just wrote** — the files
always win, and regenerating a current index is a no-op:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/regenerate-index.py write --root <host-repo>
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/regenerate-index.py check --root <host-repo>   # exit 1 = stale
```

`INDEX.md` is a **view, not a third declared product**: it is never
completion-gated, so a failed index write is a **disclosed warning** in the
completion summary's informational notes (`index.warning` in `complete`'s
JSON — relay it), never the hard error the two declared products carry. Persist
therefore never silently widens the gap: the index is either current or its
staleness is stated.

Checkpoint state lives under `$WS` with the other intermediates
(`docs/storage-architecture.md` D2), never in the host tree.

**Resumed-run audience recheck (Story 13.41 — the run mint's half of the presence
rule).** When `stage0`/`autostart` resumes a run (`"resumed": true`) whose
`next_stage` is `verify` (or `variants`, from a checkpoint written before Story
13.69 made variant emission post-review) — i.e. a filled draft already exists among
the intermediates — confirm that draft carries a **resolved `audience`** before
continuing (a run checkpointed before the audience precondition existed may lack
it). If it is missing or still `{audience}` (or `audience_id` is missing or
still `{audience_id}` — Story 13.71), fill both per the fill's rule and
re-run the quality gate; the variant stage's hard stop remains the mechanical
backstop either way.


---

**Start exit → probe.** Read [`stage1.md`](stage1.md) and run:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/probe.py record --ws "$WS" --root <host-repo>
```

(Probe writes `$WS/probe.json` — a feasibility verdict plus anchors, never a
fact sheet (#1182). The stage sequence and each stage's one command are the dispatcher's
table in [`../SKILL.md`](../SKILL.md) — this line points at it, never restates it.)
