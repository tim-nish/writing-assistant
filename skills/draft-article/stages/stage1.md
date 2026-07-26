<!-- stages/stage1.md — draft-article stage companion (Story 19.3, #744/#740). Loaded on entry to this stage by the
     SKILL.md dispatcher; carries the stage's full operating detail,
     moved verbatim from the pre-split SKILL.md. -->

## Stage 1 — harvest and consume its output

Hand the run to the `harvest` skill to produce its output document at
`$WS/fact-sheet.md` (the source-pointed fact sheet **and** the NEEDS-OWNER
list) — give harvest the `$WS` from Stage 0 so it writes there. The stage-0 sources are
a **selection**, not a scope widener: harvest enumerates the
writing-sources-declared files (`resolve-writing-sources.py files`) and
**intersects** this selection with them, so a path passed on the command line can
only narrow what is read — never add an undeclared repo. Reconciliation against
`writing-sources.yaml` happens there.

**Fact-sheet entries are emitted, never guessed (validator convergence, #206).**
Harvest builds every file-pointer entry through
`pin-source.py --emit-entry` (its §3) — copied from tool output — and runs
`validate-fact-sheet.py` as a **single confirmation pass**. Repair after a
REJECT is **bounded at two validator passes**: entries still rejected after the
second pass move to the NEEDS-OWNER list with their REJECT reason and the stage
surfaces its **budget-triage signal** (Story 13.7 — the existing per-stage
signal, not a new channel) instead of looping again. This stage never instructs
free-hand entry writing followed by validate-loop repair — that
reject → guess → re-run cycle is what exhausted the turn budget across all
three frameworks (#206). Entries rerouted by the bound are listed in the
completion summary's **informational notes** (they reach the owner as interview
material, not as a silent loss).

Then consume that output into pipeline state:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py consume <harvest-doc>
```

This carries harvest's output forward **without re-reading any source** — it only
reads the harvest document, so there is no second read path that could bypass the
Story 3.1 scope boundary. **Harvest-reuse on a rerun (#736/#737):** a resumed or
re-entered run reuses the persisted fact sheet and its recorded per-source
progress verbatim and re-executes only the stages after the last checkpoint —
consume failing never means harvest re-ran. It:

- holds **both** the fact sheet and the NEEDS-OWNER list, parsed against harvest's
  exact contract (a schema change surfaces here rather than being absorbed);
- preserves every entry's **source pointer verbatim** (`path:line@sha` / sha /
  URL) for later traceability — no re-normalization;
- **threads the NEEDS-OWNER list into the gap interview** (`next_stage:
  interview`, Story 4.3), so unsourced gaps are not dropped;
- advances on a valid-but-empty result (empty fact sheet and/or NEEDS-OWNER) —
  the stage contract is total.

**Working-note runs:** pass the article type — `consume <harvest-doc>
--framework working-note` — so consume routes `next_stage: fill` (the slim
profile has no interview stage; see "Working-note slim profile" below).

## Working-note slim profile (F5 — Story 13.89, #412)

The ratified working-note category (SPEC-article-frameworks, working-note
ratification 2026-07-16) runs a **slim pipeline profile**, because its
contract is "assembly <1hr" and the full pipeline's attention budget is
mis-sized for it. Differences from the full flow — everything not listed
here runs exactly as the full pipeline does:

- **Sources are constrained (ratified, binding):** the active repos' recent
  activity **plus the owner's policy recall surface via the policy-source
  seam — read-only, pinned, lessons first**; the policy hub's **Q&A history
  archive is never a harvest source**; **published text carries public
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
- **No Stage 2 interview:** `consume --framework working-note` emits
  `next_stage: fill` (`interview` rejects F5 with a named error). NEEDS-OWNER
  entries still ride the state — at fill they become `[VERIFY]` markers or
  publish blockers, never questions.
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
