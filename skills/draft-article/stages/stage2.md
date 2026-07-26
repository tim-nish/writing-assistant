<!-- stages/stage2.md — draft-article stage companion (Story 19.3, #744/#740). Loaded on entry to this stage by the
     SKILL.md dispatcher; carries the stage's full operating detail,
     moved verbatim from the pre-split SKILL.md. -->

## Stage 2 — bounded gap interview

### Owner thesis, arc, and stakes as first-class items (Story 17.1, #439)

The gap interview is not only a hole-filler for what the sources cannot answer;
it is **the owner-input channel for the article's story**. Alongside the
NEEDS-OWNER gaps, the interview **explicitly elicits the owner's thesis, arc,
and stakes** — the one claim the piece exists to make, the misconception→turn
it narrates, and why it matters — as **first-class items**, not only when a
NEEDS-OWNER entry happens to name them. These items ride the **same ≤5 question
budget** and the same journal/disposition machinery as every other question;
they are owner judgment (opinion), so they are **`open`** items (owner-only
knowledge, [`SPEC-policy-source-seam CAP-2`](../../specs/spec-policy-source-seam/SPEC.md)),
never a source-pointed recommendation. Their answers come back as **owner
opinion** and reach the draft as **attributed prose spans** (Stage 3 below),
not as atomic sourced claims — this is the prose-shaped channel the owner's
story needs. When the fact sheet already carries the thesis as a sourced claim,
the item is suppressed like any covered question; when it does not, the owner's
answer is the article's spine.

### The gap interview is *the* owner-input channel (Story 13.98, #435)

Beyond the thesis/arc/stakes items above, the interview **explicitly invites the
owner's free-form requirements and material** — a constraint to honor, a
paragraph the owner wants included, an emphasis, a correction — as **first-class
interview items**, not only answers to source-gap questions. This is the
**designed channel for owner input into the draft**: an owner requirement enters
here and reaches the draft as an **owner-attributed prose span** (opinion,
thesis, arc — Story 17.1) or a **sourced/derived claim** (a checkable
requirement), never through post-hoc hand-editing outside the pipeline. Free-form
material rides the same ≤5 budget and journal machinery; a requirement beyond a
single run's budget is recorded as a NEEDS-OWNER-style item for the next
invocation, never dropped. **Make the channel visible:** when opening the
interview, say that free-form owner requirements are welcome *here*, so the owner
does not assume manual insertion afterward is the intended workflow (the
dogfooding surprise this closes).

### Policy-seeded tension questions (Story 14.4)

Before selecting questions, probe the host repo's optional `policy_source`
(SPEC-policy-source-seam) — the owner's policy repo, read-only and bounded
**in code** to GLOSSARY.md, LESSONS.md, and ≤2 `topics/*.md`. Which two topic
files is a **per-article decision made now, not a per-repo config**
(SPEC-policy-topic-at-draft CAP-2, Story 13.35), in two steps:

1. **List** the available topics — names only, no content read:

   ```
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/read-policy-source.py --root "$HOST" list-topics
   ```

   If this exits **13** (`gateway cannot enumerate topics` — a named
   tool-surface gap, Story 13.72), ask the owner for the topic names under
   the proposal contract instead; the ≤2 cap is unchanged.

2. **Propose ≤2 topics for THIS article** under the proposal contract. The
   **default recommendation** is drawn as follows, the owner approves or
   overrides either way:

   - **Mapped default (#525, SPEC-policy-topic-at-draft CAP-5).** When this
     draft is built from a backlog item that carries a `track:` frontmatter
     value, and the host repo's `policy_source` block declares a
     `track_topics` mapping whose keys include that track, the mapped topic(s)
     are the **default recommendation**. Read the mapping from the resolver's
     JSON — it exposes a `track_topics` field when present:

     ```
     python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-writing-sources.py --root "$HOST" policy-source
     ```

     Look up the backlog item's `track:` value in that object; its value (a
     topic name or list) is the recommended `--topics` selection. The mapping
     only widens **which** topics the recommendation names — it **never**
     applies silently (the owner still approves/overrides under the proposal
     contract), never widens the **≤2 cap**, and never touches the
     code-enforced whitelist. A mapped topic that names no hub topic file was
     already caught at stage 0 (topic-existence lint), so the recommendation
     is trustworthy by the time it is presented here.

   - **Intent-driven default (unchanged, today's behavior).** When there is
     **no mapping**, **no track** on the draft, or the track has **no mapping
     entry**, draft the recommendation from the chosen article intent and the
     host repo (e.g. an evaluation-methodology article from a benchmark repo →
     the benchmark-engineering topic) exactly as before — zero behavior change.

   Declining is valid in either case: the read proceeds with GLOSSARY +
   LESSONS only — still policy-seeded, recorded as track-less. Then read with
   the approved selection:

   ```
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/read-policy-source.py --root "$HOST" read --topics <a.md> [<b.md>] > "$WS/policy-surface.txt"
   ```

   **Then pre-filter the surface before it enters model context (Story 19.7,
   #741):**

   ```
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py policy-prefilter \
     --surface "$WS/policy-surface.txt" [--items "$WS/policy-items.json"]
   ```

   Author tension items and run `classify-policy` against the emitted
   `policy-surface.filtered.txt` — a deterministic allowlist reduction
   (subject patterns, config keys, seed pointers, headings; fail-open to
   inclusion) that is behavior-preserving for classification by test. The
   full surface stays on disk beside it for audit, and the command's
   `disclosure` line (full → filtered size) is **relayed once** as an
   informational note.

   (No approved topics → plain `read`: GLOSSARY + LESSONS only. The per-repo
   `track`/`topics` config keys were **removed** — Story 13.36,
   SPEC-policy-topic-at-draft CAP-3; a leftover key is a named stage-0
   configuration error, never silently applied. The ≤2 cap and the
   code-enforced whitelist are unchanged; `--topics` builds the whitelist,
   unlike `--only`, which filters within it.)

When `policy_source` is unset this whole step is skipped silently — zero new
interaction in generic mode (seam CAP-6).

Branch on its exit code — **the policy source is an enhancer, never a
dependency; no exit code here may abort the run**:

- **0** — the output leads with the run's pin (`pin: <policy-source>@<commit>`)
  and each file's content line-numbered. Author **tension items** from it:
  questions whose `gap_type` is `contradiction`, `ambiguity`,
  `missing-rationale`, or `reversal-candidate`, each carrying its seed
  `{quote, pointer: file:line@commit}` quoted **verbatim** from the surface at
  the pinned commit. The policy source supplies **questions only** — never an
  answer, never a recommendation (SPEC-policy-source-seam CAP-2: triage and recommendations stay a
  view over harvest output). A question that merely restates its seed will be
  rejected (R4) — ask the tension, not the quote.

  **Author against the consulted surface as a whole, never a single line
  (#299).** Before characterizing a quoted line as a tension, read the *rest of
  what the reader returned* for a **companion line that already resolves it** —
  the same batch that records a rejection often records the discriminator right
  beside it. If a companion resolves the apparent conflict, either **do not
  raise the item at all**, or raise it **with the resolving line** in the seed's
  `companion` field, so the owner arbitrates the real residual question instead
  of re-deciding settled ground. A tension the surface already answers is a
  manufactured tension: it spends an owner-gate slot on nothing, and an answer
  to it contributes a "resolution" to a conflict that never existed.

  **Stale seed, not a live tension (#306).** Before raising a conflict, compare
  *when the seed was recorded* against *the material it appears to contradict*.
  The inputs are already in hand — the surface's `updated:` dates and `state:`
  lines, and the run's pin. When the seed **predates** the material (a glossary
  entry updated before the behavior it describes matured), the honest reading is
  a **stale recorded position**, not a live contradiction: route it to
  `gap_type: reversal-candidate` and ask the owner to **confirm or update the
  recorded position** — never ask them to adjudicate a conflict as if it were
  live. Nothing else about the seam changes: same bounded read, same pin, same
  proposal-only contribute-back. Manufactured tension is self-reinforcing — an
  owner who answers a stale-seed question as though it were live contributes a
  "resolution" to a conflict that was an artifact of staleness, so the routing
  decision is what keeps the recall surface honest.

  **The line the discriminator usually turns on:** *harvest is evidence
  assembly; the interview is the judgment gate.* Assembling many source-pointed
  facts is not the same act as generating prose from them — the owner's answers
  are what turn evidence into an argument. Do not seed a tension that treats
  evidence assembly as if it were unattended generation without first checking
  whether the surface itself draws that line. Write the items to
  `"$WS/policy-items.json"` (seam-formats.md §2) and pass them via `--items`
  below; they are schema-validated **before** triage.
- **10** (`policy_source` toggle absent or `enabled` falsy) — generic
  interview, **silently**: no items, no log line, behavior identical to a
  repo without the seam.
- **11** (toggle present, gateway unavailable — unreachable, transport error,
  or timeout; the retired exit 12 collapses here) — the reader printed
  exactly one `policy_source unavailable: <reason>` line;
  **relay that one line once** and continue with the generic interview. Do
  not retry, do not warn again — one line, then generic mode. Keep the
  reason: the journal's `consulted:` line records it (`--policy-note`).
- **13** (named gateway tool-surface gap — Story 13.72) — treat exactly like
  11: the reader printed one `policy tool-surface gap: <reason>` line;
  relay it once, continue generic, record it via `--policy-note`.
- **4** (malformed block) — a stage-0 configuration error slipped through;
  halt and report it like any CAP-5 finding (this cannot happen after a clean
  `stage0`).

### Policy-result classification — CAP-7, before any owner question (Story 13.75)

After authoring the policy items and **before** running `interview`, classify
the served policy result against the authoritative user config
(SPEC-policy-source-seam CAP-7, added 2026-07-18, #365). This is a
**mechanical pre-step** — a deterministic pass over a declarative
comparable-subjects table, never an LLM judgment:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py classify-policy \
  --surface "$WS/policy-surface.txt" --root "$HOST" \
  --items "$WS/policy-items.json" > "$WS/policy-classified.json"
```

Every candidate subject lands in exactly one of CAP-7's four classes —
`determined` / `constrained` / `open` / `conflict` (`determined` is
structurally present in the output and empty until the subject table gains
determining semantics; the shipped detector covers the EN-topology regression
as `conflict`, and the same subject as `constrained` when config does not
assert the excluded value). Pass
the output's `interview_items` array (reconciliation items first, then the
open pass-throughs) as the `--items` file below, and carry its
`journal_records` into the run record. Three contracts hold:

- **A conflict subject is presented ONLY as the emitted reconciliation
  question** — a `gap_type: reconciliation` item whose `positions` array
  carries every disagreeing side (`{quote, pointer, authority ∈
  policy|config|repo}`; seam-formats.md §2) — **never as an ordinary
  content-preference question whose candidates smuggle the conflict in**. The
  classifier marks the original tension item `superseded_by_reconciliation`
  and drops it from the pass-through; do not re-add it. (This is the
  2026-07-18 regression: a policy-incompatible records-only answer was
  offered as an ordinary candidate, selected, and shipped unreconciled
  against `syndication.policy` EN-canonical config.)
- **The gate banner states the machine's PARSE before the options, and "no
  conflict" is a first-class option (#739).** A reconciliation item now
  carries `parse` — which rule is being scoped, by what predicate the
  conflict was computed, how the machine reads the served line (mandate /
  permission / indeterminate), and whom it binds — and the banner renders it
  **before** the options, in the contract's section-(g) plain text (it passes
  `validate-proposal-payload.py` unchanged), so a misparse is catchable while
  it is still cheap. The item's `options` array is presented as the
  structured choices, with **"No conflict — both records stand"** first:
  accepting it changes neither config nor policy, and the journal records
  `reconciliation_outcome: no-conflict` (record it via `--selection
  no-conflict` or an answer whose text opens with "No conflict"). The
  truthful answer to a manufactured conflict must never exist only as
  free-form.
- **A constrained subject excludes VISIBLY — never by filtering (#566).** When
  a served line rules an answer out without determining one, the question is
  **still asked** and the ruled-out candidate **stays in the list**, marked
  `excluded` with the governing line's verbatim quote and its pinned pointer
  (seam-formats.md §2). Present it that way: show what policy removed and why,
  and keep the **override real** — the owner may still choose it, which routes
  to the staging candidate as a *proposed policy change*. **Never present only
  the compatible candidates.** A gate that looks like a free choice while one
  resolution has been quietly removed is a defaulted multi-outcome gate
  wearing a different costume, and the exclusion becomes unauditable. The ≤3
  candidate cap counts **selectable** candidates only, so an exclusion never
  forces a candidate out of the list.
- **Owner judgment is never pre-decided — the structural exemption.** An item
  whose gap_type is a judgment class (`opinion`, `significance`, `surprise`,
  `tradeoff`, `warning`, `audience`, `motivation`, `retrospective`) always
  classifies `open` and passes through untouched, even when its text matches
  a conflict subject: for judgment questions the "questions only" rule stands
  whole and no class other than open/conflict may apply.
- **An owner answer that reverses a served ratified line is a proposed policy
  change, not policy.** It routes to the staging-candidate emitter (below) as
  a config↔policy reconciliation decision, and is **never treated as current
  policy by later stages of the same run** — the plan-side conformance gate
  that enforces this at draft time is Story 13.76's, not this step's.

Then select the interview questions from the stage-1 state (with policy items
when the probe produced them):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py interview --framework <F> \
  [--items "$WS/policy-classified-items.json"] <state>
```

(where `policy-classified-items.json` is the classifier output's
`interview_items` array; on a run with no policy items at all, skip
`classify-policy` and `--items` alike)

**Three-outcome triage over the harvest output (Story 10.2).** Every candidate
question is triaged against the harvest output **only** — the fact sheet and the
NEEDS-OWNER list, reading **no source material** beyond them (it may read the
framework contract, config, and run-state metadata needed to run the interview).
The `triage` array classifies **each** bank question into exactly one outcome:

- **suppressed** — a fact-sheet entry already covers the question's information
  need (matched semantically via a synonym set, not literal text), and no
  NEEDS-OWNER gap re-raises it. **The owner never sees it** (`covered_by` names
  the covering entries, for the journal in Story 10.4);
- **recommended** — a NEEDS-OWNER entry re-raises the topic → **always
  recommended** (confirm/deny the claim), grounded on that entry;
- **open** — neither → genuinely owner-only knowledge, answered as a bullet.

Where a question triaged **open** is in fact groundable from a fact-sheet
**owner-judgment** entry (a dev-log note of what surprised them *is* a sourced
owner statement), present it as **recommended** instead — this recommendation
pass is a **view over the harvest output**, introducing no new unsourced material.

**Issue- and Den-sourced facts follow the same rule, stated here so it is never
left to inference (Stories 13.50 / 13.51):** a fact harvested from a
`github-issues` or `tanuki-den` source that carries an **owner disposition**
(accepted/dismissed) is eligible grounding for a recommended answer **exactly
like any harvest fact** — the disposition is a sourced owner statement. Open or
deferred findings never reach the fact sheet (harvest routes them to
NEEDS-OWNER), so they surface as confirmed gaps here, not as grounding. A
finding's **recurrence count is data the recommendation may quote, never a
reason the pipeline treats it as more significant** — significance is the
owner's call, asked, not inferred from a count.

Validated policy items join the candidate set as **asked** questions
(`outcome: open`, `rationale: policy-seed`, their `seed` carried through): a
tension between the material and a recorded position is owner-only by nature,
so suppression does not apply — and there is never a recommended answer for
one (SPEC-policy-source-seam CAP-2).

The surviving (non-suppressed) questions are returned as `questions`, and are:

- drawn from the fixed question bank, **prioritized by the framework's GATE
  slots** (not bank order), so the same fact sheet yields a stable interview;
- **confirmed NEEDS-OWNER gaps first**, then **policy-seeded tension
  questions**, then generic open questions, using the GATE-slot order as the
  deterministic tie-break when more than five could apply — the ≤5 cap holds
  even when the NEEDS-OWNER list is longer or policy items are in play;
- **one slot reserved for policy tension (#302).** When at least one valid
  policy-seeded tension item exists, the **highest-priority one is guaranteed a
  slot**: it displaces the lowest-priority survivor rather than extending the
  budget. Priority order alone starves seeds on any repo whose harvest yields
  five or more confirmed gaps — precisely the fact-rich repos the seam exists
  for — and the loss is silent: the editorial anchor falls back to a routine
  slot answer (`policy_seeded: false`) and contribute-back emits an empty file.
  With no valid tension item, selection is exactly as before — no slot is held
  open and nothing is padded. **A reconciliation item no longer competes for
  this slot (amended 2026-07-22, Story 18.40, #542/#545):** it is a
  **mandated/gate** item, not an interview candidate — see the tier below. Its
  `positions` still ride into the journal like a seed's do;
- **at most 5**, and **zero** when harvest already covers everything — never
  padded to five.

**Mandated/gate items are a tier OUTSIDE the ≤5 cap (Story 18.40, #542/#545).**
Two items are pipeline **obligations**, not owner-knowledge candidates: the
**CAP-7 config↔policy reconciliation gate** (a blocking gate — "surfaced and
answered → gate cleared") and the **CAP-8 depth offer** ("offer it once"). They
are partitioned out **before** the cap and the #302 reservation run, so they:

- **never consume a capped slot** (they do not displace NEEDS-OWNER candidates,
  and candidates never displace them), and
- **never consume the #302 reserved slot** — that slot is guaranteed to the
  highest-priority policy-**seeded** tension item, which is exactly what #545
  broke when a reconciliation item took it and the editorial anchor was recorded
  as an empty-text gate item.

They **lead presentation** (a gate the owner must clear comes first) and are
reported separately: `interview`'s JSON carries `mandated: [<id>…]` beside
`asked` — where **`asked` counts only the capped pool**, so `asked <= budget`
still holds and the total shown is `asked + len(mandated)`. The tier is bounded
by construction (at most those two items), so the ≤10-minute owner-attention
budget is unaffected, and every item is still presented under the owner-facing
proposal contract.

Present a policy-seeded question under the same proposal contract as every
other: its **Why** context is the seed — the verbatim quote plus its
`file:line@commit` pointer — so the owner sees exactly which recorded position
the question probes. The quote is presented under the contract's **section-(g)
plain-text conventions** (quoting by indentation, no fencing or emphasis
markers; Story 13.48), keeping its `file:line@commit` pointer. Its primary
input is bullet free-text, like any open question.

**Presentation order is contract, not discretion (SPEC-draft-article-ux CAP-4,
Story 13.30).** Ask the surviving questions in the pinned order the `interview`
command already emits (`presentation_order`): **claim/angle first** (the
policy-seeded tension question when one exists — it reframes every later
answer; else the opinion/claim question), **audience second**, then
**headline/significance**, then **color** (surprise, tradeoff, warning,
retrospective). Batching within that order is free — grouping several
questions into one ask is fine — but never reorder across it. The journal
echoes the order, so a mis-ordered run is attributable. Selection priority
(the bullets above) is unchanged; this governs presentation only. When harvest
yields **no `number`/`result` fact**, the bank's conditional evidence-fallback
question ("what result or worked example would convince a skeptical reader?")
joins the candidates automatically (CAP-5) — the evidence GATE's interview
fallback, surfacing the gap here instead of failing late at Stage 3.

Present each surviving question under the
[owner-facing proposal contract](../owner-facing-proposal-contract.md): show
**where** the section it concerns sits in the article outline and a **short
preview of the current section** (when one already exists), **why** the question
is asked, and **choices whose labels state their concrete effect** — never a
shorthand the owner must decode. A first-time owner answers from **repository
knowledge alone**. Assemble the prompt payload and **validate it before showing
it** (contract (e)): `validate-proposal-payload.py` blocks a missing Effect line
or a truncated field. Pass `--ws "$WS" --surface <name>` on that same call so
the presentable payload is **captured verbatim** to
`$WS/presented-payloads.jsonl` at ask time, and record the owner's selection +
free text against the returned `ask_id` with `--answer` (contract (f), Story
13.28) — every owner-facing ask in this pipeline (interview, visual proposals,
Stage-4 verification) captures this way.

### Recommended answers with dispositions (Story 10.3)

A **recommended** question arrives with its **source-pointed candidate answer as
the default choice**, and dispositions **labeled by concrete effect**:

- **Approve** → "adopt this answer as written" — the recommendation becomes the
  interview answer **verbatim** and **keeps its source pointers**, grounding
  sourced claims in stage 3 exactly like a fact-sheet entry;
- **Modify** → "edit this answer, then use it" — the owner's edit is their
  contribution on top of the grounding; the answer is **interview-sourced**;
- **Replace** → "discard this and use my own" — the owner's bullet; also
  **interview-sourced**;
- **Skip** → the question goes unanswered; **only the skip is recorded** — what
  it *means* is the target framework slot's declared effect (Story 10.5),
  resolved at stage 3, never by the interview engine. The skip choice's label
  states that slot's declared effect.

An **open** question carries **bullet free-text** as its primary input (no
recommendation to approve).

Record each answer — with the disposition that fixes its provenance class — via:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py answer --id <qid> \
  --disposition <approved|modified|replaced|answered|skipped> [--text <answer>] [--pointer <p> ...]
```

It enforces the D2 rules — an **approved** answer must inherit ≥1 pointer;
**modified/replaced/answered** carry owner text and **no** pointers (owner
judgment); a **skip** carries neither. The recorded answer text is kept
**verbatim**, keyed by question `id`, for stage-3 traceability.

### Recommended defaults for editorial-judgment gaps (SPEC-policy-editorial-direction CAP-6, Story 13.60)

When a confirmed NEEDS-OWNER gap is an **editorial-judgment** class — `opinion`,
`significance`, `surprise`, `tradeoff`, `warning`, `audience` — and the policy
surface already holds a relevant recorded position, present it as a **proposed
default** the owner ratifies, instead of a bare open question. This is the
propose-ratify invariant applied to the *shape* of the answer: it saves the
owner seconds per question, and is **no substitute for #302's reserved slot**
(the cap fills on count, not time).

- **Item shape (Story 13.59; multi-candidate Story 13.92).** Carry the recalled
  position on the interview item as `recommended_default {default, quote,
  pointer}`, with `owner_answer` structurally empty at generation. When more
  than one recalled position fits the gap, carry **1–3 candidates ordered by
  recontextualizing power** (the one that most reframes the others first)
  instead: `recommended_default {candidates: [{default, quote, pointer}, …]}`
  — 1–3 entries, each auditable, the owner ratifying **exactly one**
  (approve/modify/replace/skip); the machine is never final. A single position
  (no `candidates` key) is the N=1 case, unchanged.
  `validate-interview-items.py` refuses a default on an ineligible class
  (**R6**) or a tension item (**R7**), a recalled position that is not
  auditable (**R3**, per candidate), and a `candidates` list outside 1–3
  (**R10**) — so a bad default never reaches the owner.
- **Presentation.** Present the default under the owner-facing proposal
  contract like every other ask (Where/Why/Effect, plain-text payload per
  section (g); the seed quote + `file:line@commit` pointer is the **Why**),
  and **capture it** via `validate-proposal-payload.py --ws --surface interview`.
  **Every presented default counts toward the ≤5 interview cap** — never a
  pre-interview side batch that moves the decision outside the owner-attention
  bound.
- **Ratification — four effect-stating choices, owner judgment throughout:**
  - **Ratify** → "use this recalled position as written" — record with
    `--disposition ratified`: the default text becomes the interview answer as
    **owner judgment** (`interview` provenance), **never** the pointer-inheriting
    `approved` class. The recalled policy pointer is **not** a SOURCE.
  - **Modify** → "edit it, then use it" — `--disposition modified` (owner text,
    no pointers).
  - **Replace** → "discard it, use my own" — `--disposition replaced`.
  - **Skip** → the gap stays an **unresolved NEEDS-OWNER item**, exactly as if
    no default had been offered; only the skip is recorded.
- **Audit (invariant 3).** The recalled position appears only in the `seed<-`/
  `consulted:` records — record it with `journal --seed-extra
  '<pointer>=<gap_type>'`. A factual claim grounded only in a policy line still
  fails the provenance gate or stays `[VERIFY]`; a policy pointer is never a
  SOURCE.
- **Gating (#299 / #306).** Recall a default only under the
  whole-consulted-surface authoring rule (a same-surface companion line
  accompanies or suppresses the recall) and staleness protection (a seed
  predating the material it addresses routes to reversal-candidate handling,
  never a confident default). Consultation uses only the existing pinned,
  bounded, read-only policy reader — no new access path.

**Validate the answers in one batch, not one round-trip per answer (Story 13.6).**
When you have the owner's answers to the surviving questions, pass them all at
once as a JSON list of answer specs and get **one consolidated report of every
rejection** — instead of a reject-and-retry cycle per bad answer, which burns
turns against the pipeline budget (#118):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py answer --batch <answers.json>
```

Each list entry is `{"id", "disposition", "text"?, "pointers"?}` — the same
fields and the **same D2 rules** as the single form. A clean batch emits the
records as a JSON list; any rejection names the offending `id` and the fix, and
the whole batch is a hard gate (non-zero exit) so a malformed answer never
reaches stage 3.

**Offered-candidate provenance on a tension question (Story 18.28, #515).** When
a consult-first tension question presented **1–3 pinned candidate answers**,
record what was offered and which the owner took, so `disposition: approved` no
longer collapses accepted-candidate / accepted-after-edit / owner-typed-from-
scratch into one indistinguishable state. Add two fields to that answer (single
form: `--candidates '<json>' --selection <sel>`; batch: the same keys on the
list entry):

- `candidates` — the offered options **as presented**: a JSON list of
  `{"text", "pointers"?, "order"?}` (order defaults to the list position);
- `selection` — `candidate:<n>` (took option n as-is) | `candidate:<n>+edited`
  (took n then edited) | `owner-authored` (typed their own despite the options).

Both are **additive** — a non-tension answer omits them and is unchanged. The
gate stays **machine-proposed, never machine-final**: recording the choice does
not let the machine pick it.

### Interview journal — the boundary diagnostic (Story 10.4)

When Stage 2 finishes, write an **interview journal** to the run workspace, one
entry per **candidate** question, so a mis-asked or mis-suppressed question is
attributable from run state — never discovered by the owner mid-interview:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py journal \
  --interview <interview.json> --answers <answers.json> \
  [--policy-note "policy_source unavailable: <reason>"] \
  [--events "$WS/interview-events.jsonl"] > "$WS/interview-journal.json"
```

Each asked question that carried offered candidates has its `candidates` and
`selection` (Story 18.28) copied into its journal entry — the run-workspace
record of what was offered and chosen. `--events` additionally writes an
**interview-selection calibration event** per such question to the run workspace
(one JSON object per line: `type`, `id`, `disposition`, `selection`, `offered`),
so *which candidate got chosen* joins the same pass-tuning stream the review
arbitration events feed; a later offline mining pass ingests it. Without
`--events`, no stream is written and behavior is unchanged.

Each **asked** question records its **survival rationale** (`topic-absent` /
`needs-owner-reraise` / `owner-judgment` / `policy-seed`), the recommendation's
**grounding pointers** (when recommended), the **seed pointers** (when
policy-seeded — the `seed` field, parallel to the grounding), and the owner's
**disposition**; each **suppressed** question records its **covering fact-sheet
entries**. A question asked that the declared sources could in fact answer is
then attributable from the journal — harvest scope gap vs. de-dup miss vs.
triage error — without owner intervention. The command **fails closed** if an
asked question has no recorded disposition, so an unattributable interview
never ships.

**Story-element selection is disclosed in the journal (CAP-9, #428).** For a
lesson-based run, the journal also records, **per selected story element, the
rule that selected it** — the element **id** and its declared reason (e.g.
"Journey-bearing cluster, unconsumed, matched framework slot X"). This is the
audit trail that makes selection reproducible: the same fact sheet selects the
same elements with the same stated reasons. Disclosure only — recording the
reason never changes which elements were selected. A run that selected an
element without a recordable reason fails the same way an undisposed question
does; the completion summary then repeats these reasons for the owner.

**Editorial anchor (SPEC-policy-editorial-direction CAP-2, Story 13.38).** The
journal also records the run's **editorial anchor** — the claim/angle answer:
the first *presented* question whose disposition carries owner text, with
`policy_seeded: true` when a policy tension seeded it (this is what the QSB
run's p1 did by accident, made first-class). The anchor is carried into review
as the **claim intent anchor** (SPEC-review-ux / SPEC-policy-editorial-direction
CAP-3 consume it from the journal). It shapes the article's argument and what
reviewers weight — it **never grounds a factual claim** (no-facts invariant):
its provenance stays exactly what the disposition rules assigned, and it adds
no source pointer. A run whose slot-1 question was skipped simply has no
anchor — nothing is invented.

**The anchor is never a gate item, and never empty (Story 18.41, #545).** Since
the mandated tier *leads* presentation, "the first presented answered question"
would otherwise pick the **CAP-7 reconciliation gate** — which is a config
answer, not a claim. #545 shipped exactly that: `editorial_anchor` was
`{id: rc1, text: ""}`, so review calibration and provenance joins received an
empty string. Anchor selection therefore **skips mandated/gate items and
empty-text answers** and takes the claim/angle answer from the capped set —
which may be the owner's brief/q2-derived claim when no policy tension seeds
slot 1. Two named rejections guard it, in lockstep with `_anchor_rejection` in
`draft-pipeline.py`:

- `editorial-anchor-empty` — the answer carries no owner text;
- `editorial-anchor-is-gate-item` — a mandated/gate item was proposed as the anchor.

When no valid anchor exists the journal records
`editorial_anchor_rejected: <reason>` — the loss is **named, never silent**
(silent fallback is the failure this contract exists to prevent).

**The journal ends with the `consulted:` line (Story 14.4, CAP-5).** Its last
key maps every seed to the question it seeded, under the run's pin —
`consulted: <policy-source>@<commit> — LESSONS.md:41 → t1; …` — the /ask-style
audit trail of which policy lines drove which questions. A run that was not
policy-seeded records `consulted: none (policy_source unset)`, or, when the
probe degraded, `consulted: none (policy_source unavailable: <reason>)` via
`--policy-note` — every interview run states its policy provenance, including
the generic ones. Surface the line in the completion summary's informational
notes when it names a pin.

**On request — the policy-influence report.** When the owner asks what the
policy changed in a run, produce the
[policy-influence report](../policy-influence-report.md)
(`${CLAUDE_PLUGIN_ROOT}/skills/policy-influence-report.md`): a view over the
journal + presented payloads + `consulted:` lines — never a second draft or
A/B run, and never emitted unasked (Story 13.40).

### Staging candidates — proposal-only contribute-back (Story 14.5)

After the journal, emit staging-candidate blocks for the policy-seeded tension
questions the owner actually answered (dispositions
`answered`/`modified`/`replaced` — a skip proposes nothing):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py staging-candidates \
  --interview <interview.json> --answers <answers.json> \
  --source-repo <host repo name> --created <run date YYYY-MM-DD> \
  [--tag <track>] > "$WS/staging-candidates.md"
```

Each block mirrors the policy hub's staging-area frontmatter (`slug, created,
source_repo, perishable, tags`) followed by the question and the owner's
decision in full sentences (seam-formats.md §3).

**An answered reconciliation question emits a config↔policy reconciliation
block (Story 13.75, CAP-7).** When the owner answered a `reconciliation` item
(dispositions `answered`/`modified`/`replaced`), the emitter frames its block
as the **config↔policy reconciliation decision**, citing every position it
decided between (the served line at the pin, the config key at its
configVersion). The owner's answer is a **proposed policy change** for
whichever record lost — it is never treated as current policy by this run's
later stages (the plan-gate enforcement is Story 13.76's).

**A staleness-routed item proposes an update, not a resolution (#306).** When
the answered item was a `reversal-candidate` raised because its seed predated
the material (above), the block's question and decision are framed as a
**policy-update proposal for the stale line** — "this recorded position is out
of date; here is what now holds" — never as the resolution of a live tension.
The distinction matters downstream: the owner is being handed a candidate
*correction* to a recorded position, and a block that framed it as a resolved
conflict would record a dispute that never existed. **This is where the tool
stops**: the blocks land in the run workspace only — the owner copies accepted
ones into the hub's staging area by hand, and nothing is ever written into
the policy hub (the consumer holds no hub path at all — Story 13.73; the
gateway serves read-only). A run with no answered tension questions emits
nothing —
never an empty block. When candidates were emitted, the completion summary's
**informational notes** must name the file (`$WS/staging-candidates.md`) and
the block count, so a proposal is never silently buried in run output.

### Stage 2→3 policy-block gate — draft generation blocks on a conflict/stale plan (Story 13.77)

**After the answers are recorded (and staging candidates emitted), before any
Stage 3 fill**, run the stage-progression precondition
(SPEC-article-draft-pipeline, 2026-07-18 amendment: draft generation blocks on
a conflict or stale plan — like the quality gate, never silently proceeded
past). It is mechanical (no LLM):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py policy-block-check \
  --classification "$WS/policy-classified.json" --answers <answers.json> \
  > "$WS/policy-block.json"
```

**Resumed-run half (autostart):** when a resumed run already has an emitted
article plan (a prior invocation reached plan emission), the plan's recorded
CAP-4 conformance status **re-validates before Stage 3+ continues** — pass the
plan, and the fresh surface so the status is **recomputed at the current pin**
through the 13.76 `conformance` machinery (read-only — same table, same rules,
one implementation):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py policy-block-check \
  --plan <plans/<slug>.md> --surface "$WS/policy-surface.txt" \
  --root <host-repo> [--staging "$WS/staging-candidates.md"]
```

Branch on the JSON:

- **`blocked: false`** (`conformant` / `open` / answered reconciliation) —
  proceed to Stage 3 unchanged.
- **`blocked: true`** (`action: publish-blocker`) — **surface the
  `publish_blocker` payload in-conversation** (it names the conflicting
  positions with their pointers, or the moved pin/configVersion — never a bare
  status), **write the block checkpoint, and STOP the run**: checkpoint the
  output's suggested `checkpoint` object —
  `{"stage": "policy-block", "next_stage": "interview"}` — via
  `checkpoint --ws "$WS"`, so the run resumes **at the block** and the
  reconciliation question **re-presents on resume**; never checkpoint before
  Stage 2, and never `next_stage: fill` (that would resume past the gate).
  The completion summary's **publish-blockers bucket** carries the payload
  (positions/pin delta included) and the resume path.
- **In-run repair** — the block is repairable in the same invocation:
  - **conflict** → if the owner answers the reconciliation question now
    (CAP-7), record it via `answer` and **re-run the check** — any recorded
    decision unblocks, **including a reversal**, which proceeds as a proposed
    policy change through its staging-candidate block (never as current
    policy);
  - **stale** → **re-consult at the current pin**: re-run the policy reader
    (`read-policy-source.py read`), `classify-policy`, and the conformance
    recompute against the fresh surface, then re-run the check — it proceeds
    or re-blocks per the new status (a recorded `stale` whose referenced
    lines still hold at the new pin clears to `conformant`).
- **Generic mode never touches the gate**: with no `policy_source` toggle (or
  reader exit 10) there is no classification and no policy-seeded plan, and
  the check returns `{blocked: false, reason: "generic-mode"}` — behavior
  identical to a repo without the seam.

This gate is a **separate precondition at the same boundary** as the quality
gate: it changes nothing about the quality gate or `[VERIFY]` markers.

