---
name: review-article
description: >
  Review a framework-complete draft article for publication. Invoke as
  "review article" (a draft picker enumerates the repo's candidate drafts;
  a direct draft path is the expert bypass) to run the fixed pass order: lint → structure →
  prose → policy consistency → cold read, each LLM pass once per draft version, emitting capped
  severity-tagged findings (blocker/should/nit) with no rewrites. The owner is
  the sole arbiter of every finding.
---

# Review article

Take a framework-complete draft from "review requested" to "publishable" with a
fixed, small number of passes:

```
review article [<host-repo> | <draft>]
```

**Name the target repository first (#309).** Before reading any scope, print the
resolved target as the flow's first owner-visible line:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py target --root <host-repo>
```

Relay it as `Operating on host repo: <path>`. A wrong-target run is otherwise
only discoverable after the work is paid for. When an explicit `--root`
disagrees with the session's cwd the resolver notes both on stderr — relay that
line too; `--root` still wins.

## How to run — the phase sequence (dispatcher)

This file is the **dispatcher** (Story 20.13, #818; the Story 19.3 packaging
pattern): it carries the phase sequence, the one command per phase, and the
relay-and-stop rules — and **nothing else**. Each phase's full operating
detail lives in its companion file under [`phases/`](phases/); **on entry to a
phase, read exactly that phase's file** and execute it. Normative history and
contracts live in `specs/` — the phase files cite them and restate nothing.
Severity criteria, finding-class formats, and the declared-convention contract
live in [`review-prompts.md`](review-prompts.md).

**Global rules that bind every phase:**

- **The owner is the sole arbiter.** Every LLM pass emits **findings only** —
  capped at 10, severity-tagged (`blocker`/`should`/`nit`), each naming the
  criterion behind its severity — **no rewrites, no praise, no summaries**.
  Nothing is applied without the owner's arbitration.
- **Style is MEASURED, never carried.** The Reviewer has exactly **one** style
  dimension — conformance to the owner's one versioned style contract, **citing
  the clause** — and it is its **own finding class, outside blocker/should/nit,
  that never blocks**. A style finding that cannot cite a clause is **not
  emitted, because it is taste**; with no contract configured the dimension
  states that it did not run and why. Contract:
  [`style-conformance.md`](style-conformance.md).
- **Fixed pass order, never reordered:** lint → structure → prose → policy
  consistency → cold read; each LLM pass runs **exactly once per draft
  version**. No pass is skipped at the agent's discretion.
- **Cold-read isolation is a mechanism:** the cold read runs as a separate,
  context-free invocation given **only the draft** — an agent that ran the
  earlier passes answering the cold-read rubric voids the pass.
- **Relay and stop:** a validator report, a review-precondition failure, or a
  named degradation line is relayed verbatim and the run halts, skips, or
  degrades as the phase file says — never silently retried or paraphrased
  into success.
- **Host-repo footprint:** review writes **no files into the host tree**;
  anything persistent goes to the run workspace
  (`WS=$(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py new-run)`).
  After a run, the host repo's `git status` shows nothing new.
- **Owner-facing proposals** follow the shared
  [owner-facing proposal contract](../owner-facing-proposal-contract.md):
  where the item sits, why it is raised, choices whose labels state their
  concrete effect.

| Phase | Enter by reading | The one command |
|---|---|---|
| **Entry & setup** (picker or direct path; starter template on a blank repo; footprint; pre-review checkpoint proposal; stage-0 config validation) | [`phases/entry.md`](phases/entry.md) | `draft-pipeline.py review-checkpoint-proposal --draft … --slug …` |
| **Passes 1–5** (halt semantics; findings contract; intent anchors; shared preamble; model routing; lint → structure → prose → policy → cold read) | [`phases/passes.md`](phases/passes.md) | `lint-article <draft>` then the four LLM passes per the phase file |
| **Arbitration** (pinned consolidated list; reject-only defaults; policy three-way; events emission; second-cycle gate) | [`phases/arbitration.md`](phases/arbitration.md) | `emit-arbitration-events.py <dispositions.jsonl> --ws "$WS" --scenario <slug>` |
| **Re-entry & report** (provenance/quality re-entry by artifact class; before/after diff; completion summary) | [`phases/reentry.md`](phases/reentry.md) | `draft-pipeline.py review-reentry --draft … --slug … --root … --ws "$WS" --applied <n>` |

**Phase routing notes (the dispatcher's whole job):**

- **Entry:** no argument or a host repo → enumerate candidates through the
  resolver and present a **picker** (exactly one candidate → confirm, never
  auto-pick; zero → point at draft-article, never an empty picker). A direct
  draft path is the expert bypass. Then the checkpoint proposal (once), the
  pre-arbitration snapshot into `$WS`, and `validate-config.py` (halts on
  config defects) — all per `phases/entry.md`.
- **Passes:** a lint **review-precondition failure** (residual `[VERIFY]`,
  unfilled GATE slots, template residue) halts — the draft is not
  framework-complete. A **frontmatter defect on a complete body** is a
  publish blocker that does **not** halt: the content passes still run.
  Policy consistency runs only when the host declares a `policy_source`;
  its reader's exit codes degrade to a skip, never an abort
  (`phases/passes.md`).
- **Arbitration:** one round, top-down over the consolidated ranked list;
  ordinary findings default to accepted (deselect to reject);
  policy-contradiction findings keep their three-way choice. A surviving
  blocker triggers **exactly one** additional full cycle — never more.
- **Close:** **zero applied edits** → hand-write the done/reviewed checkpoint
  (`phases/entry.md` shows the one-liner) and report. **≥1 applied edit** →
  the edited draft re-enters the gate regime (`phases/reentry.md`); the
  `review-reentry` subcommand writes the checkpoint itself — **never
  hand-write it after edits**. Review never emits or re-emits a variant;
  stale variants are publish blockers with the re-emission path named.
- Every run ends with the shared
  [completion summary](../completion-summary.md) — editor's assessment first,
  then the three buckets and an explicit in-conversation next step
  (`phases/reentry.md`).
