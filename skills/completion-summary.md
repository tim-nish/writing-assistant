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

## Explicit next step

After the three buckets, state **one concrete next step** — e.g. "run
review-article on the draft"; for a standalone harvest, "review the fact sheet, or
run draft-article to turn it into a draft".

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
