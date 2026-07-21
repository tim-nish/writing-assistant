---
name: fork-gate-consult-first
description: >
  Before raising a human gate that presents policy, architecture, or
  prior-decision forks, consult the served policy surface so covered forks
  become overrideable FYIs and only genuinely new positions reach the owner as
  gates. Applies the standing consult-first contract to every fork-presenting
  stop point (spec-policy-fork-consultation, #480).
---

# Fork-gate consult-first

Before raising a human gate that presents **policy, architecture, or
prior-decision forks**, consult the served policy surface — so covered forks
become visible, overrideable **FYIs** and only genuinely new positions reach the
owner as **gates**. Applies the standing consult-first contract to every
fork-presenting stop point. Contract: `specs/spec-policy-fork-consultation/SPEC.md`
(#480, ratified `a7184b8`). Sibling of the divergence detector — same §3.1
intake, opposite trigger family (that skill triages decisions *already taken*;
this one triages decisions *being asked*).

Driven by `scripts/fork-consult.py`; the *semantic* step (does a served line
discriminate a fork's options?) is LLM-assisted and reaches the script as a
per-fork `consult` result.

## The pass (CAP-1/2/3)

At a fork-presenting stop point, before showing the table:

1. **Per in-scope fork, consult first (CAP-1).** For each fork whose content is
   **policy / architecture / prior-decision**, form the discriminating question
   from the option text and query the served surface through the **existing seam
   client** (`policy_lookup`, owner-realm grant, pinned bounded read) — one hit
   per in-scope fork, preceding the stop. **Purely mechanical/product forks are
   out of scope** and skip consultation. No new consult surface — only new call
   sites here.
2. **Classify (CAP-2/CAP-3):**

   ```
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/fork-consult.py present \
     --input "$WS/forks.json" --pin "<policy-source>@<commit>" \
     [--policy-source-available false]
   ```

   - **Covered + discriminates → FYI** (CAP-2): chosen option + verbatim quote +
     `file:line@commit` at the run pin, in a distinct FYI section. **Coverage is
     strict** — a merely *topical* quote that does not discriminate the options
     stays a **gate**. An FYI is **always shown, never silently applied**; the
     owner may **override inline**, which reopens it as a gate (a natural
     divergence signal for the sibling detector).
   - **Uncovered (or covered-but-topical) → gate** (CAP-3): ≤3 machine-proposed
     candidates with their partial grounding, **ordered by recontextualizing
     power**, **no pre-selected default**; the gate never times out into a
     choice.

3. **Fresh pin per run — no consultation cache.** The `--pin` is supplied per
   run; nothing caches a consult result between runs.

**Receipt outcome (#519).** Every per-fork receipt `present` emits carries an
**`outcome`** ∈ `{auto-resolved-FYI | escalated}` — what the gate *did* with the
consultation: a covered FYI is `auto-resolved-FYI`; a gate (uncovered,
covered-but-topical, or degraded) is `escalated`. An FYI the owner **overrides**
reopens as a gate, so re-run `present` with `--overridden <fork-id>` and its
receipt records `escalated` (the disposition, not the origin). The access log
proves a consult *occurred* but cannot observe this disposition, so the field is
what makes covered-fork auto-resolutions **mechanically countable** for the
ratified impact-statistics view (`report.counts.auto_resolved_fyi` /
`.escalated`, countable from receipts alone). A receipt missing a valid
`outcome` is a lintable defect:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/fork-consult.py lint --input "$WS/receipts.json"
```

## Miss feedback (CAP-4) — proposal-only

Every uncovered in-scope fork is a **consult miss** (a distill-bug signal in the
run receipts). At the owner's gate answer, an owner "report upstream" choice
produces a **§3.1-conformant staging block** for manual copy into the upstream
intake:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/fork-consult.py emit-miss \
  --question "<the fork question>" --decision "<owner answer>" \
  --slug "<YYYY-MM-DD>-<gist>" --source-repo "<repo>" --created "<date>"
```

The block is a **conformance copy** of the hub §3.1 staging-file schema
(the configured policy hub's §3.1 is the authority; hub wins on
any mismatch, a mismatch is a defect of this spec), with **no schema of its
own** — the same emitter the divergence detector (#436/#482) cites. This skill
is the **second emitter** into that intake: shared envelope, distinct payload.
The **upstream hub is never written**; the copy is a manual, approved owner step.

## Carrier — every fork-presenting stop point (no orphan mechanism)

The stop points that raise **policy/architecture/prior-decision fork tables** are
the spec-lane authoring tools — and they **all live outside this repo**
(installed skills or userSettings). This repo carries the **mechanism**
(`fork-consult.py`) and this **reference**; the actual call site is an
**owner-side edit** to the installed skill. The repo's own skills present **no**
such fork tables — they are exemptions. Every stop point resolves to an
**owner-side invocation** or an **in-repo exemption** (Story 18.13, #484):

**Owner-side invocations — out-of-repo fork-presenters (wire in the installed skill):**
- **`/triage-gh` spec-lane re-offer** — userSettings (not a repo file). Its
  alternatives AskUserQuestion (step 6d) presents policy/architecture/
  prior-decision alternatives; run this pass before it — covered → FYI,
  uncovered → gate.
- **bmad-spec** — installed skill, gitignored (`.claude/skills/bmad-*/`). Before
  surfacing an unresolved either/or, run this pass.
- **bmad-architecture** — installed skill, gitignored. Before showing a
  load-bearing-call fork (paradigm / stack / boundaries), run this pass.

These are **owner-side** because their files are not in this repo; the carrier
check **cannot** assert them mechanically (greping gitignored/absent files would
pass locally and fail on a fresh checkout) — it asserts the **in-repo** side is
clean and that these three are documented here as the owner-side wiring.

**In-repo exemptions — no policy/architecture/prior-decision fork table:**
- **The gap interview** (`draft-article` Stage 2) — already applies consult-first
  natively (Story 14.4 policy-seeded tension items + the editorial anchor); its
  own consult path stands, not re-wrapped here.
- **Review arbitration** (`review-article`) — presents the article's own review
  findings (reject-only arbitration), not a policy/architecture/prior-decision
  fork → out of scope.
- **Mechanical gates** (`/commit-groups`, `/repo-cleanup`, `/publish-issues`) —
  commit grouping, deletion approval, board mapping; never policy forks → skip.

A **new in-repo skill** that raises a policy/architecture/prior-decision fork
table without either running this pass or carrying an exemption row here is the
orphan-mechanism defect the carrier check catches.

## Invariants

- **Never blocks a run.** `policy_source` absent/unavailable ⇒ all in-scope
  forks present as **gates**, **one logged line**, the run proceeds.
- **Never machine-final.** A covered fork is an *application of an existing
  ratified line*, always overrideable; an uncovered fork never auto-resolves.
- **No new consult surface, no cross-repo forwarding, no cache.**
- **Publication boundary:** FYIs, gates, and staging payloads carry only the
  served `file:line@commit` pointer grammar already public in this repo.
