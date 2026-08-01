<!-- stages/stage1.md — draft-article stage companion (Story 19.3, #744/#740). Loaded on entry to this stage by the
     SKILL.md dispatcher; carries the stage's full operating detail. -->

## Stage 1 — probe: can this repository ground the brief?

Harvest is retired at this stage (amended 2026-08-02, #1182/#1097/#1185/#1209
— the amendments companion is the authority). Harvest read at stage 1 while
the article's structure is fixed at stage 3, so it gathered against an
unstated query; stage 1 now asks the one question it can actually answer:
whether this repository can ground anything for this brief at all. Probe
returns a **feasibility verdict** plus a **handful of anchors** — resolvable
pointers into the declared sources — and writes **no fact sheet**: no
artifact of harvest's shape exists anywhere in the run workspace. Per-claim
grounding is `examine` (stage 3+, story 20.147 — [`examine.md`](examine.md)),
where a concrete claim exists to test.

First read the declared surface, then judge, then record:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/probe.py surface --root <host-repo>
```

`surface` prints the declared read surface **through the typed time-axis
source model** (`resolve-writing-sources.py files` is the one enumeration; a
second walk here would be a second boundary that drifts). The stage-0 sources
are a **selection**, not a scope widener: whatever probe reads must intersect
the declared boundary — a path can only narrow what is read, never add an
undeclared repo, and `record` refuses an anchor outside the enumerated
surface. The surface carries every declared entry with
its derived `time_axis` and an `id` the coverage ledger must account for,
plus the enumerated files. Read against the brief only what feasibility
needs — anchors, never an extraction pass. Then record **your** judgment
(the model judges; the tool validates and records, never decides):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/probe.py record --ws "$WS" --root <host-repo> [--framework <F>] <result.json|->
```

The result carries:

- **`verdict`** — `grounded` or `ungrounded`, nothing third.
- **`anchors`** — up to 7 resolvable pointers (`path:line[-line]` into an
  enumerated source file, or a commit sha); `record` refuses any that do not
  resolve. An anchor says where the evidence **sits**, never extracts it. A
  `grounded` verdict carries at least one.
- **`reasons`** — required on `ungrounded`; the run stops on them.
- **`coverage`** — what was consulted (`consulted`) and what could not be
  reached with **why** (`unreached`), accounting for **every** declared
  source id; `record` refuses a ledger with a gap. An empty result from an
  unreachable source is a different finding from an empty result from a read
  source. A brief needing episode claims against a declaration with no
  time-axis source is the standard ungrounded reason — stated from the typed
  surface, never guessed.

**A doomed article dies here.** An `ungrounded` verdict stops the run before
any interview or structure work: the checkpoint routes `next_stage: done`,
the verdict and its reasons are kept in `$WS/probe.json`, nothing is deleted.
Relay the verdict and every reason to the owner verbatim.

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
