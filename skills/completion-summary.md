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
