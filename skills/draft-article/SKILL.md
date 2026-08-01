---
name: draft-article
description: >
  Draft a technical article from a repository's own material. Invoke as
  "draft article <article-type> from <sources>" to run the pipeline: probe →
  gap interview → framework fill → verification → completion (variants are a
  separate post-review invocation — see variants.md). Article
  types are intent labels — "introduce the project", "share engineering
  lessons", "explain the evaluation methodology", "survey a research area",
  "write a working note" (F1-F5 remain the internal/expert alias); sources
  are paths, globs, or commit ranges.
---

# Draft article

One invocation kicks off the whole probe-to-variant flow:

```
draft article <article-type> from <sources>
```

- **article-type** — an **intent label**: "introduce the project", "share
  engineering lessons", "explain the evaluation methodology", "survey a
  research area", or "write a working note" (the lightweight slim-profile
  entry — see "Working-note slim profile" below). The framework ids
  `F1`–`F5` keep working as the internal/expert alias (see
  `${CLAUDE_PLUGIN_ROOT}/skills/draft-article/frameworks/`); both forms
  resolve through `resolve_framework` in the pipeline helper — a closed
  mapping, never fuzzy-matched.
- **sources** — any mix of paths, globs (`src/**/*.py`), and commit ranges
  (`HEAD~20..HEAD`).

**No article type given?** Ask by intent, in-conversation (proposal contract):
offer the five intent labels with a **repo-grounded recommendation** — e.g. a
tagged release exists → "introduce the project" is viable; no release → its
own entry precondition already redirects to "share engineering lessons", so
recommend that. Draft the recommendation from repo state you can check
(tags, docs, eval assets), never from guesswork.

**Capture the intent gate like every other ask (Story 19.13, #758).** This is
the run's first fork and was the one owner-facing ask the capture contract
skipped: assemble the payload — the offered intent labels, the recommendation
and its basis (the seed pointer in the **Why** when policy-informed) — and
validate/capture it **before presenting**:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-proposal-payload.py \
  --ws "$WS" --surface intent <payload>
```

then record the owner's selection against the returned `ask_id` with
`--answer` (proposal contract (f)). The offered-alternatives record is what a
later session (Revise, a plan-schema audit) reconstructs the angle decision
from — a run whose gates leave no payload log has its loss NAMED by the
journal (`payload_capture_warning`), never silent. The intent gate precedes
`stage0`, so mint/resolve `$WS` first via `autostart` when capturing here.

**Policy-informed recommendation (SPEC-policy-editorial-direction CAP-1,
Story 13.37).** When the host repo declares a `policy_source`, the
recommendation may additionally draw on the owner's recorded positions — read
the base surface (`read-policy-source.py read --only GLOSSARY.md LESSONS.md`;
topics are not selected yet at this point) and let a recorded stance on what
the owner's channel should emit shape which type is recommended. The three
invariants are hard lines: the policy **proposes** (a recommendation the owner
ratifies or overrides — never a silent decision); it supplies **no facts**
(the seed shapes the recommendation, never grounds a claim); and the influence
is **audited** — quote the seed verbatim with its `file:line@commit` pointer
in the question's **Why**, and record it in the journal's `consulted:` line
via `journal --seed-extra '<pointer>=article-type'`. An owner override is a
**recorded decline** (the presented-payload log keeps the recommendation and
the selection; declines are the recall surface's raw material — proposal-only,
staging-candidate path unchanged). Without a `policy_source`, the
recommendation is repo-grounded only, with zero policy interaction.

**Vocabulary boundary (SPEC-draft-article-ux CAP-1, Story 13.27):** framework
ids (`F1`–`F4`), GATE slot markers, and stage names are internal contract
vocabulary. They stay in specs, filenames, run state, and the journal — they
**never appear in an owner-facing question, proposal, or summary**. When
talking to the owner, always use the intent label ("introduce the project"),
never the id.

Every `draft-pipeline.py` subcommand and its flags are tabled in
[Pipeline command reference](#pipeline-command-reference-draft-pipelinepy) at the
end of this skill — consult it instead of running `--help` or reading the script
source mid-run.

## Owner-facing proposals

Every point in this pipeline where the owner approves, modifies, or declines
something — the **Stage 2** gap interview and the **Stage 4** verification pass —
follows the shared
[**owner-facing proposal contract**](../owner-facing-proposal-contract.md)
(`${CLAUDE_PLUGIN_ROOT}/skills/owner-facing-proposal-contract.md`): show **where**
the item lands (outline/section context, with a preview of current content when
one exists), **why** it is asked, and **choices whose labels state their concrete
effect** on the article — never a shorthand label the owner must decode. This
skill references that one convention rather than restating its own wording.


## How to run — the stage sequence (dispatcher)

This file is the **dispatcher** (Story 19.3, #744/#740): it carries the stage
sequence, the one command per stage, and the relay-and-stop rules — and
**nothing else**. Each stage's full operating detail lives in its companion
stage file under [`stages/`](stages/); **on entry to a stage, read exactly that
stage's file** (the `variants.md` pattern) and execute it. Normative history
and contracts live in `specs/` — the stage files cite them and restate
nothing. Every owner-facing ask follows the shared
[owner-facing proposal contract](../owner-facing-proposal-contract.md).

**Global rules that bind every stage:**

- **Name the target repository first (#309):** `stage0`'s resolved `target` is
  the run's first owner-visible line — `Operating on host repo: <target>` —
  before any scope read or LLM spend.
- **Relay and stop:** a validator/config report, a hard error from a gate, or
  a named degradation line is **relayed to the owner verbatim and the run
  stops or degrades as the stage file says** — never silently retried,
  swallowed, or paraphrased into success.
- **Artifact-write precondition (Story 13.78):** before every Write to a `$WS`
  path that may already exist (re-writes, resumed runs), Read the target
  first; only a path minted fresh this turn may be written blind. Pipeline
  script writes are exempt.
- **Durability:** checkpoint each stage (`checkpoint --ws "$WS"`), record
  sub-stage progress in the long stages (`progress --ws … --done …`), and end
  **every** non-`complete` exit with the stop-side run-status line
  (`stop-disclosure --ws "$WS" --repo <host-repo>`). On any resumed run, emit
  `resume-disclosure` **before spending**. Elective pauses only at sanctioned
  points, rendered as a gate (stages/stage0.md §Durability).
- **Host-repo footprint:** every intermediate lives in the run workspace `$WS`
  — minted by `stage0` (resolver-backed: `resolve-paths.py new-run` is the
  standalone form) **outside the host repo**, never a path you compose — and
  the **only** files written into the host working tree are the declared
  products at `output.drafts` through the `complete` gate. After a run,
  `git status` in the host repo shows nothing but declared products.
- **Budget triage is an orderly stop:** finish the unit in progress, persist
  at the boundary with `--stop-note`, exit clean (stages/complete.md).
- **Run-level cost journal (#742):** at each stage boundary, retry, and judge
  spawn, record the event —
  `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py run-event --ws "$WS" --stage <s> --event start|end|retry|judge-round|subagent`
  — and at each stage boundary consult
  `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py budget-check --ws "$WS"`;
  `breached: true` presents the continue / orderly-stop choice (never a
  silent continue). The completion summary's informational bucket carries
  `cost-block --ws "$WS"`'s lines (stages/complete.md).

| Stage | Enter by reading | The one command |
|---|---|---|
| **0 — start** (config gate, framework check, workspace autostart; optional `--depth`/`--element`/`--brief`; plan consultation, continuation, differential context; durability contract) | [`stages/stage0.md`](stages/stage0.md) | `draft-pipeline.py stage0 <framework> <sources…> --root <host-repo>` |
| **1 — probe** (feasibility verdict + anchors, no fact sheet — #1182; routes interview/fill/done; working-note slim profile) | [`stages/stage1.md`](stages/stage1.md) | `probe.py record --ws $WS --root <host-repo> <result>` |
| **2 — gap interview** (policy seeds → classification → ≤5 questions + mandated tier → answers → journal → staging candidates → policy-block gate) | [`stages/stage2.md`](stages/stage2.md) | `draft-pipeline.py interview --framework <F> [--items …] <state>` |
| **3 — fill** (argument plan, structure proposal, per-section fill + sidecar provenance map, per-claim examine — [`stages/examine.md`](stages/examine.md), #1182 — visual set, isolated provenance judge) | [`stages/stage3.md`](stages/stage3.md) **and** [`style-contract.md`](style-contract.md) | `draft-pipeline.py provenance --map <map> --draft <draft>` |
| **3→4 — quality gate** (mechanical dims + isolated rubric judge; two-cycle bound; missing-input repair hop) | [`stages/gate.md`](stages/gate.md) | `draft-pipeline.py quality-gate --draft … --map … --judge …` |
| **4 — owner verification** (resolve every `[VERIFY]` to zero; bounded rewrites) | [`stages/stage4.md`](stages/stage4.md) | `draft-pipeline.py verify <draft>` → `verify-markers --count` = 0 |
| **complete** (article plan emission + conformance, the dual-product `complete` gate, completion summary; variants are post-review — `variants.md`) | [`stages/complete.md`](stages/complete.md) | `draft-pipeline.py complete --draft … --slug … --root … --ws …` |

**Stage routing notes (the dispatcher's whole job):**

- Stage 0's JSON carries `next_stage` — jump straight to it on a resume
  (`"resumed": true`), reusing persisted intermediates; never re-run a
  completed stage.
- Stage 1 is **probe** (stages/stage1.md): its `record` routes `next_stage`
  itself — a working-note run passes `--framework working-note` and skips
  Stage 2 (the slim profile); an ungrounded verdict stops the run.
- Stage 3 reads the owner's **one versioned style contract** once, before the
  fill ([`style-contract.md`](style-contract.md), Story 20.139 #1201): the
  contract is consumed **at generation**, never per article and never at
  review, and it is **read-only** — an absent contract is stated and the run
  proceeds, and nothing here ever writes or offers to create one.
- Stage 2 ends at the **policy-block gate** (`policy-block-check`): blocked →
  surface the payload, checkpoint at the block, STOP; clear → Stage 3.
- The Stage 3→4 gate and `verify-provenance` both pass before Stage 4; both
  re-run after any revision (bounded at two cycles, delta re-grades —
  stages/gate.md).
- The run ends **only** through the `complete` gate (stages/complete.md);
  then the completion summary with its three buckets and the explicit next
  step ("run review-article / stop here"). Platform variants are a separate
  post-review invocation ([`variants.md`](variants.md)) — never a stage of
  this flow.

## Pipeline command reference

The authoritative flag table for every `draft-pipeline.py` subcommand lives in
[`stages/complete.md`](stages/complete.md#pipeline-command-reference-draft-pipelinepy)
— consult it instead of `--help` or the script source mid-run. Variant
subcommands are referenced in [`variants.md`](variants.md).
