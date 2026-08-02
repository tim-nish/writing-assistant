# Pipeline vocabulary and data flow

A reader's map of the draft-article pipeline: what each working term means and
where information is narrowed, discarded, or routed as it flows from source
material to a publishable draft. This page is **derived from the current
implementation and the ratified specs, not inferred** — where a rule is
normative it points at the contract that owns it rather than restating it
(duplicated normative text would drift). The canonical contracts are
[`specs/spec-article-draft-pipeline/SPEC.md`](../specs/spec-article-draft-pipeline/SPEC.md)
and its companion
[`pipeline-stages.md`](../specs/spec-article-draft-pipeline/pipeline-stages.md).

## The stages

`draft article <type> from <sources>` runs a fixed sequence:

```
start          probe          gap interview     framework fill    verify        complete
(invocation) → (verdict +    → (owner answers) → (the fill drafts,→ (provenance) → (canonical + plan)
                anchors)                          examine per claim)
```

- **Start — invocation.** Validates configuration and classifies the source
  tokens (path / glob / commit-range); emits the run-state probe consumes.
- **Probe.** Checks whether the declared sources can ground this
  brief at all — a verdict plus a handful of anchors saying where evidence
  sits. **No fact sheet is built**: there is no pre-extraction pass anywhere in
  the pipeline (retired 2026-08-02, #1182/#1220).
- **Gap interview.** At most five questions covering only what the
  sources cannot answer; answers return as owner input for the fill.
- **Fill.** Populates the framework's slots from the interview
  answers and from **examine**, which grounds each claim at the read that
  produced it, classifying every sentence in a provenance map. The pin is born
  with the claim rather than two stages before it.
- **Verify.** An independent `verify-provenance` check and the
  fill→verify quality gate.
- **Complete.** Durably writes the two declared products: the canonical draft
  at `output.drafts` and the article plan at `plans/<slug>.md`.

## The fill

The fill is where source facts and owner judgment become prose. Its contract is
CAP-3 of the pipeline spec.

**The fill opens with an argument-plan sub-step (#440/#434).** Before filling any
slot, it composes an explicit **argument plan** — thesis, arc, per-section
content intents — from the examined claims (including the narrative kinds) and the
interview, then fills **from that plan**, so the article is an argument rather
than a framework skeleton stitched from fact-sheet prose. A framework governs
each section's **content obligations, not a literal heading skeleton** — a
multi-lesson article is one arc, not the skeleton repeated per lesson. The plan
is a run-workspace intermediate, owner-visible; at completion the plan-record
`plans/<slug>.md` projects the thesis/arc from it. The fill→verify quality gate
fails stitched-fact-sheet and per-lesson-skeleton drafts **before** review.

- **Inputs:** the gap interview's answers and, per claim, what `examine` grounds during fill.
- **Outputs:** a slot-filled draft with schema-conformant frontmatter, plus a
  **sidecar provenance map** classifying every body sentence.
- **Restrictions — the three provenance classes** (every claim-classed
  sentence must trace to a pointer, an interview answer, inherited pointers, or
  a `[VERIFY]` marker):
  - **sourced** — carries a fact-sheet or interview pointer.
  - **derived** — compresses, combines, or restates ≥2 named sourced claims and
    inherits their pointers. Introducing new **causality, significance,
    evaluation, comparison, intent, or scope** makes it *inferred*, not derived.
  - **narration** — asserts nothing checkable (the **falsifiability test**: no
    reviewer with source access could mark it false) and needs no pointer.
  - An assertion that exceeds all of the above carries an inline `[VERIFY]`
    marker; the pipeline never silently asserts.
- **Copy, don't summarize.** A sourced claim copies the verbatim source text
  behind its pointer rather than paraphrasing it, so the pointer always
  resolves to what the sentence says. The drafting agent never grades its own
  claim/narration boundary — `verify-provenance` runs in an isolated subagent
  (NFR13).

## The closed nine-KIND fact-sheet vocabulary

Every fact-sheet entry declares exactly one **KIND** from a **closed set** of
nine (`pipeline-stages.md`) — five atomic kinds plus four **narrative** kinds
(added 2026-07-20, #438):

| KIND | Means |
|---|---|
| `result` | An outcome the work produced. |
| `decision` | A choice made, with its rationale where recorded. |
| `number` | A measured or counted quantity. |
| `quote` | Verbatim source text (may span consecutive physical lines). |
| `event` | Something that happened at a point in time (a release, a fix). |
| `chronology` | An ordered sequence of events — a timeline. |
| `motivation` | The *why*: the problem/gap, or free-standing decision rationale. |
| `cost` | A recorded price or tradeoff paid. |
| `reversal` | A superseded position (a struck decision, a Declined line). |

The four narrative kinds admit **pointer-backed** narrative material and may use
a multi-line span pointer like `quote`. Anything that does not fit one of these
nine KINDs cannot be pinned as evidence — it routes elsewhere (below).

## Episode vs state claims, and the time axis of a source

Added 2026-08-01 (#1182/#1184/#1185, `specs/spec-writing-assistant/` amendments).
Two vocabularies meet here: what a **source** is, and what a **claim** asserts.

**A declared source carries a `time_axis`, DERIVED FROM ITS TYPE** — the
declaration never states it, and `resolve-writing-sources.py` refuses a
hand-written `time_axis:` key at read time.

| `type` | `time_axis` | Why |
|---|---|---|
| `commits` | **true** | A commit is a change together with its stated reason, in order — the closest thing a repository has to a native episode. |
| `github-issues` | **true** | An issue **thread** records a decision being reached, dated. The read includes the comments; a body-only projection is a marked partial. |
| `tanuki-den` | **true** | A finding record carries `first_seen`, a recurrence count, an ordered per-run evidence list and a `status` that moves; its pointer pins to the dated run that judged it. |
| `path` | **false** | Prose and code alike. Docs and specs may describe the latest state of usage, but they are not written with the directional purpose of generating episodes, and material beyond a document's original purpose is not something to depend on. |

**A claim declares its type in the provenance map**, beside its provenance
class — `P4.S6[L35]: sourced episode <- a1b2c3d`:

- **`episode`** — asserts how something **came to be**. Admissible **only**
  against a source with a time axis.
- **`state`** — asserts how something **currently is**. Admissible against
  either class, and the **default** when a map entry declares no type. The rule
  constrains episode claims only.

**Enforcement is at the ship gate, deny-never-warn.** `verify-provenance`
refuses a claim typed `episode` whose every pin resolves to a `time_axis:
false` source, naming the claim and the source that failed it; the fill→verify
gate blocks on it like any other finding. This is a **predicate on the shipped
mechanism**, not a second one — examine is unchanged and stays per-claim.

**What a given repository can ground is readable before drafting:**
`resolve-writing-sources.py time-axis --root <host-repo>`. A declaration that
grounds no episode claim is reported as a **fact about the declaration**, exit
0 — an owner who declares only prose and code has not misconfigured anything.

## Where information is narrowed, discarded, or routed

The pipeline deliberately loses material at each boundary; knowing where keeps
its output auditable.

- **Claim → examine.** Only source-pointable material gets a pin. A claim the
  fill wants but examine cannot ground goes to a **`NEEDS-OWNER`** item or
  carries `[VERIFY]`, never into the draft unmarked.
- **Owner-judgment dimensions route off the sheet.** Owner judgment —
  **surprise, significance, tradeoff, warning, opinion** — is not source-checkable,
  so it routes to `NEEDS-OWNER` and reaches the draft (if at all) through the
  **interview**, the gate between evidence and prose. **Pointer-backed narrative
  material** (chronology, problem statements, motivation, failure/cost, reversals)
  is different: since #438 it **does** get pinned, under the four narrative
  KINDs above — the interview stays the judgment gate, but the narrative
  *evidence* is grounded rather than routed off.
- **Interview → draft.** An **approved** recommended answer keeps its source
  pointers and grounds sourced claims like an examined claim; **modified** or
  **replaced** answers become interview-sourced material.
- **Policy source absent → generic mode.** When the host repo declares no
  `policy_source` (or the gateway is unavailable), the policy-seam steps
  **degrade to generic**: no tension questions are seeded and no policy
  influence is recorded — the pipeline runs unchanged otherwise. The policy
  source is an enhancer, never a dependency.

## See also

- [`specs/spec-article-draft-pipeline/SPEC.md`](../specs/spec-article-draft-pipeline/SPEC.md)
  — the canonical pipeline contract (CAP-1…CAP-7).
- [`specs/spec-article-draft-pipeline/pipeline-stages.md`](../specs/spec-article-draft-pipeline/pipeline-stages.md)
  — the stage table, fact-sheet entry format, provenance map, and quality gate.
- [`docs/interview-architecture.md`](interview-architecture.md) — the gap
  interview decision.
- [`docs/harness-architecture.md`](harness-architecture.md) — the
  article-quality harness (provenance classes and the quality gate).
