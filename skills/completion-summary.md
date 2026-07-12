# Completion summary

Every run of this plugin — draft, review, or **standalone harvest** — ends with
the same completion summary, then an explicit next step. No run ends by only
reporting results.

## Three buckets (always all three, always labelled)

Partition everything the run surfaced into exactly three labelled buckets:

1. **Informational notes** — things worth knowing that need no action (counts,
   what was harvested, and — for an article body — the reading-time estimate).
2. **Publish blockers** — things that **must** be fixed before publishing: an
   unresolved `[VERIFY]` marker, an unrendered figure, an open configuration
   defect (CAP-5). A blocker appears **here and nowhere else** — never also under
   informational notes or optional cleanup.
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
  names the last completed stage and gives the resume command; a completed run
  reports nothing here. This item is informational, not a blocker — a partial run
  is recoverable, not broken.

Before a stage hard-fails at the ceiling, **surface a budget-triage signal** (a
warning that the turn budget is nearly spent) rather than dying silently at
`error_max_turns`, so the run can be checkpointed and resumed rather than lost.

## Explicit next step

After the three buckets, state **one concrete next step** — e.g. "run
review-article on the draft"; for a standalone harvest, "review the fact sheet, or
run draft-article to turn it into a draft". For a **partially-completed run**, the
next step is the resume command above.

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
