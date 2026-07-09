# Pipeline stages (companion to SPEC-article-draft-pipeline)

## Stage table

| # | Stage | Actor | Human time | Output |
|---|---|---|---|---|
| 0 | Invoke: `draft article <framework> from <sources>` (framework = F1–F4 from SPEC-article-frameworks; sources = paths/globs/commit ranges) | Owner | ~0 min | Run started |
| 1 | Harvest: read sources, extract candidate claims/results/numbers | AI | 0 | Fact sheet, every entry source-pointed (CAP-1) |
| 2 | Gap interview: ≤5 questions on what sources cannot answer | AI asks, owner answers in bullets | ~5 min | Interview answers (CAP-2) |
| 3 | Fill: populate the framework's slots from fact sheet + answers; frontmatter from the article schema; inferred claims marked `[VERIFY]` | AI | 0 | Draft (CAP-3) |
| 4 | Verification pass: resolve `[VERIFY]` markers, veto off-voice text; >1 rewrite needed → new interview question, not editing | Owner | ~4 min | Draft ready for review |
| 5 | Variants: dev.to copy (`canonical_url` placeholder) and/or Zenn repo-sync copy per language policy | AI | 0 | Platform files (CAP-4) |

Draft then exits this pipeline into SPEC-article-review.

## Fact-sheet entry format (stage 1)

```
- CLAIM: <one sentence>
  SOURCE: <path:line | commit sha | URL>
  KIND: result | decision | number | quote | event
```

Entries the AI wants to use but cannot source go to a `NEEDS-OWNER` list feeding stage 2 — never into the draft unmarked.

## Interview question bank (stage 2)

Ask only questions whose answers are absent from the fact sheet; pick ≤5, prioritized top-down; tailor wording to the framework's GATE slots:

1. What surprised you most while building this? (feeds F2 slot 3 / F1 slot 4)
2. Which single result or number matters most, and why that one? (feeds evidence GATE slots)
3. What would you warn a reader about before they adopt this? (feeds limits/boundaries slots)
4. What did this decision cost you — what did you give up? (feeds tradeoff slots)
5. Who exactly is this article for, and what should they do after reading? (feeds hook + pointer block)
6. What opinion in this piece are you willing to defend in comments? (voice anchor)
7. What would you do differently if starting over? (feeds F2 slot 6)

## `[VERIFY]` marker convention (stages 3–4)

- Inline, adjacent to the claim: `The retry storm doubled token spend [VERIFY: inferred from logs 6/12–6/14, no exact figure found].`
- The bracket names *why* it's unverified so the owner verifies instead of re-deriving.
- Stage 4 exit criterion: zero `[VERIFY]` markers remain (each resolved to a source, an owner confirmation, or deletion of the claim).
