# Completion summary

Every run of this plugin — draft, review, or **standalone harvest** — ends with
the same completion summary, then an explicit next step. No run ends by only
reporting results.

## Three buckets (always all three, always labelled)

Partition everything the run surfaced into exactly three labelled buckets:

1. **Informational notes** — things worth knowing that need no action (counts,
   what was harvested, and — for an article body — the reading-time estimate).
   For a run that reached Stage 5, this bucket also records the **emission
   choice and its outcome** (the platforms offered vs. the owner's `chosen`
   subset, and where each variant file landed — FR57) and, when one fired, the
   **lede re-targeting touchpoint** (which variant carried a `lede_proposals`
   entry and how the owner arbitrated it).
2. **Publish blockers** — things that **must** be fixed before publishing: an
   unresolved `[VERIFY]` marker, an unrendered figure (a `render_blockers`
   entry from a profile whose platform cannot render the diagram), an open
   configuration defect (CAP-5), a **platform-lint defect** on an emitted
   variant (`lint-platform-variant`, CAP-5 of SPEC-platform-variants), or a
   **stale variant** — a `publish_blockers` entry from `variant-staleness`
   (`stale-variant` / `unrecorded-canonical-hash`, FR60): the canonical draft
   moved since emission, so route the change to the draft; re-emission is the
   owner's explicit publish decision through the standalone variants flow
   (`variants --slug <slug>`), never something a review run performs. A
   blocker appears **here and nowhere else** — never also under informational
   notes or optional cleanup.
3. **Optional cleanup** — nice-to-have polish the owner may skip.

## Partial progress — never a silent loss (Story 13.7, CAP-6)

Wall-clock is unconstrained but the **turn/compute budget is a real ceiling**. A
run that stopped before finishing — it hit the ceiling, was interrupted, or is
being resumed — reports its progress in the **informational notes** bucket so the
owner can pick it back up instead of starting over:

- the **last completed stage** and the **resume path** for the run workspace, read
  straight from the pipeline checkpoint (Story 13.5):

  ```
  python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py resume --ws "$WS"
  ```

  When it reports `resumed: true` and a `next_stage` short of the end, the summary
  names the last completed stage and gives the resume command; when the state
  carries a `budget_stop` note (an orderly stop, Story 13.85), relay that note —
  it names the exact boundary reached and what remains. A completed run
  reports nothing here. This item is informational, not a blocker — a partial run
  is recoverable, not broken.

When a stage's budget-triage signal fires, the run performs an **orderly
stop** (Story 13.85, #388): it finishes only the unit in progress, persists at
that sub-stage boundary with a `--stop-note`, and exits clean — a normal end
of an invocation, never a silent death at `error_max_turns`.

## Explicit next step — an in-conversation choice, never a file to open

After the three buckets, present **one concrete next step as an in-conversation
choice** (a selection UI — AskUserQuestion — where available; plain offered
options otherwise). The owner decides by selecting, never by opening a file:

- **draft run** → "run review-article on the draft / stop here".
- **standalone harvest** → "continue into draft-article / stop here", drafted
  from what the run just produced (fact-sheet entry count, NEEDS-OWNER count) so
  the choice is informed without opening anything.
- **review run** → "apply the accepted findings, then re-run review" or "the
  draft is publishable".
- **partially-completed run** → the resume command above is the next step.

**Interaction contract (CAP-6, #226):** every human decision point — the next
step included — lives **in the conversation**. Local artifact paths (fact sheet,
run workspace, logs, checkpoints) MAY be displayed informationally — a
copy-pasteable path is still required output where the convention says so — but
**opening or navigating a local artifact is never a prerequisite** for
continuing the workflow, and never phrased as one ("review the file at <path>,
then …" is the defect; "here's the path for reference — continue or stop?" is
the contract).

## Reading-time estimate (article body only)

A run that **produces or reviews an article body** includes a reading-time
estimate in the informational bucket:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/reading-time.py --language <en|ja> <file>
```

- **EN**: words ÷ **~200 wpm**.
- **JA**: characters ÷ **~500 cpm**.

A **standalone harvest** run has **no article body to measure and omits** the
reading-time estimate — it has a fact sheet, not prose.

## Policy consultation summary (informational — Story 13.100, #437)

Every consultation of the policy gateway is already recorded (the interview
journal's `consulted:` line, seed pointers and `editorial_anchor`; the review
pass's `consulted:` line; the run's pin), but during dogfooding the owner
could not see any of it without opening run artifacts. So the **informational
notes** bucket carries a **readable, structured summary of the run's policy
consultations — not a raw record dump** — that lets the owner see at a glance:

- **whether the policy gateway was consulted at all this run**, including the
  **degraded / generic-mode** case (unavailable or no `policy_source`);
- **which policy areas** (surfaces / topics) influenced the run;
- **how** the policy affected the run — which interview questions it **seeded**,
  the **classification outcomes**, and what the **editorial anchor** took from
  it;
- the **pin** the run used (`<policy-source>@<commit>`);
- that the information was **queried fresh for this run** — state the
  fresh-query fact plainly; **no cache exists** and none is implied.

**Presentation layer only — no new store, no cache, no copying of upstream
policy content.** Aggregate strictly from artifacts the run already wrote: the
journal `consulted:` line, `editorial_anchor`, and `seed<-` pointers; the
policy-result classification output; the review `consulted:` line; and the pin.
These are the **same inputs** the on-request policy-influence report
([`policy-influence-report.md`](policy-influence-report.md)) reads — **reuse
that view**, do not add a second source. This summary is the *automatic,
always-shown* completion-time digest; the full line-by-line influence report
stays **on request only** (an unread per-run dossier trains ignoring), so keep
this digest short — a few lines, with a pointer that "show the policy influence
report" produces the full view.

A run whose host declares **no `policy_source`** states exactly that in one
line (`policy: none (generic mode)`); a run where the gateway was **unavailable
or hit a tool-surface gap** relays its one recorded reason line. The summary is
never silently omitted — its absence would be indistinguishable from "policy
had no influence", which is the confusion this item exists to remove.
