<!-- stages/stage1.md — draft-article stage companion (Story 19.3, #744/#740). Loaded on entry to this stage by the
     SKILL.md dispatcher; carries the stage's full operating detail. -->

## Stage 1 — probe: can this repository ground the brief?

Stage 1 is a **configuration and permission check** (amended 2026-08-02,
#1224 — the amendments companion is the authority). It asks one question:
**can this run read what it was granted?** It does not enumerate files, hunt
anchors, or judge feasibility.

**Why the feasibility verdict is gone.** Probe replaced harvest here as a
model-judged read returning a `grounded`/`ungrounded` verdict, up to seven
anchors, and a coverage ledger. Two of its own clauses could not both hold —
"anchors, never an extraction pass" against a ledger accounting for **every**
declared source — and the ledger won in practice: one 2026-08-02 run read 168
files to certify an empty result from a source that contributed nothing.
Underneath that was a deeper problem: the article's structure is fixed at
stage 3, so a verdict here judges a thesis that does not yet exist.

**Feasibility is discovered where it binds.** A claim that cannot be grounded
is an ungrounded **claim**, found at [`examine`](examine.md) — a finding the
pipeline acts on, where an ungrounded **run** was a verdict about nothing.
Die-early folds into the first failed examine.

**The declaration splits in two, and only one half lives here.** As a
**permission boundary** — what may be read at all — `writing-sources.yaml` is
untouched, and the invariants resting on it are unchanged: the stage-0
selection is a **filter, never a scope widener**, and out-of-scope repos are
never searched automatically. As a **coverage denominator** it is retired:
certifying coverage of a declared universe makes cost scale with the
declaration rather than with the claim.

Run it, and record it:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/probe.py check --root <host-repo>
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/probe.py record --ws "$WS" --root <host-repo> [--framework <F>]
```

`record` takes **no result argument**: nothing at this stage is a judgment, so
there is nothing for the model to supply. It reports:

- **`declared`** — the granted sources, by name.
- **`unreadable`** — any granted source the run cannot read, named with its
  path. This is the **one** condition that stops the run here, and it is a
  configuration error rather than a verdict about the article.
- **`elapsed_s` / `budget_s` / `over_budget`** — the stage-1 **time budget**,
  declared at `probe.py:TIME_BUDGET_S` and asserted by `check-probe.sh`.
  #1224 observed that no performance budget existed anywhere and the only cost
  language was relative ("a fraction of harvest's cost"), which bounds nothing
  once harvest is gone.

**Relay one line, not this record.** The owner-surface budget applies
(`turn_budget.py`, story 20.153): a clean check is a status line, and the
record itself belongs in the workspace.

**What this trades away, stated so it can be checked.** The #1104 disclosure
made a thin read *read as thin* by denominating it. Dropping the denominator
risks reinstating that, and the bet is that per-claim scoring is the better
instrument because each claim is individually gradeable. **Overturn
condition:** a sitting where per-claim results are present and the owner still
cannot tell a well-grounded article from a thin one — at which point the
ledger returns, bounded to term-matched sources with the remainder
counted-never-read.

**Checkpoint/resume contract (the SPEC's per-stage obligation).** Probe is
atomic at `record`: an interrupted probe leaves the run's checkpoint at
`next_stage: probe` (the stage-0 mint), so a resumed run re-enters probe from
the top — there is no partial probe state to reconcile. A recorded probe
persists `$WS/probe.json` and the routed checkpoint in one invocation, and
re-running `record` replaces probe.json idempotently.

**Stage exit.** `record` routes `next_stage` itself: `interview` (full
profile), `fill` (working-note slim profile, via `--framework`), or `done`
(ungrounded). There is no consume step — no harvest document exists to
consume.

## Working-note slim profile (F5 — Story 13.89, #412)

The ratified working-note category (SPEC-article-frameworks, working-note
ratification 2026-07-16) runs a **slim pipeline profile**, because its
contract is "assembly <1hr" and the full pipeline's attention budget is
mis-sized for it. Differences from the full flow — everything not listed
here runs exactly as the full pipeline does:

- **Sources are constrained (ratified, binding):** the active repos' recent
  activity **plus the owner's policy recall surface via the policy-source
  seam — read-only, pinned, lessons first**; the policy hub's **Q&A history
  archive is never a declared source**; **published text carries public
  repository links only**. State these bounds to the owner at Stage 0.
- **The one-lesson block is told as a narrative arc (Story 13.93, #425;
  SPEC-article-frameworks "Fill — narrative-arc sourcing").** At fill, select
  the lesson from a recall-surface `## Journey` section (original framing →
  actual question → what moved it), a topic-thread Declined line, or a
  struck-through superseded decision, and map the arc onto the block:
  misconception (original/superseded framing) → turning point ("what moved
  it") → evidence (the lesson's **public** Evidence pointers only) →
  abstraction (the lesson one-liner). A Journey may be hub-native or
  `origin: reconstructed <date>`; both are valid, but **surface the origin
  marker to the owner at selection**. No usable Journey/reversal record →
  a plain one-lesson claim, arc not invented. F5's own template carries the
  full contract.
- **No Stage 2 interview:** `probe.py record --framework working-note` routes
  `next_stage: fill` (`interview` rejects F5 with a named error).
- **Lighter quality gate:** run `quality-gate --profile slim` — the dim1–2
  rubric judge is waived by contract (do not spawn a judge subagent);
  mechanical dims 3–4 and the audience precondition run in full. The
  per-section evidence-type check (Story 13.90) also runs in full — slim
  never bypasses it: F5's one-lesson and one-number blocks carry
  `[EVIDENCE: …]` declarations like any GATE slot.
- **No visual proposal:** F5 declares no visual slot — never offer one.
- **Framework:** `frameworks/F5-working-note.md` — four fixed blocks (one
  lesson / one number / published-links / what-I'm-building); no entry gate.
- **Variants:** the email + web-archive renderings come from the working-note
  slim packaging profile (SPEC-platform-variants) at the separate post-review
  variants invocation, as with any draft.


---

**Stage 1 exit → Stage 2.** Read [`stage2.md`](stage2.md) and run:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py interview --framework <F> [--items …] <state>
```
