# F3 — Evaluation & benchmark methodology

**Use when:** writing about how to measure — benchmark design, agent evaluation,
leakage, reproducibility.

**GATE (entry) — a framework-selection precondition, not a fill-in slot:** an
evaluation you actually ran and its observed result (Story 13.86, #389). The
result need not be a benchmark number: counted instances, caught-defect
episodes, or gate outcomes from a process/gate-based evaluation satisfy the
GATE — what it refuses is an evaluation you did not run. No evaluation of your
own → this is a survey (F4), not a methodology piece.

Slot syntax, the config-bound frontmatter, and the shared pointer block are
defined once in [`CONVENTIONS.md`](CONVENTIONS.md) — F3 reuses them and does not
re-implement them. Section order below is load-bearing.

## Visual slot (SPEC-article-visuals CAP-1)

**F3 declares one comparison table — required** — the results table in the
*What it caught* GATE is where the methodology's evidence lands (tables are
preferred over diagrams for comparative content). It is **proposed, not
auto-inserted** (Story 8.2). If the owner **declines** the visual proposal, the
slot is **omitted entirely** — no `[Figure: …]` or placeholder residue is left in
the draft.

## Frontmatter

Config-bound `article` frontmatter (rendered per language from user config; see
[`CONVENTIONS.md`](CONVENTIONS.md)). F3 fills its value slots:

- `title` — *(the measurement question or its answer, e.g. "How do you know your agent got better?")*
- `summary` — *(≤240 chars: the measurement problem + your method)*
- `topics` — *({kebab-case} tags)*
- `related.projects` — *(the benchmark/evaluation project the method comes from)*

## {The measurement question}                       (~100 words) [SKIP: verify]
{(The question practitioners actually have, phrased as they'd ask it.)}

## {Why the naive approach fails}                   (~150 words + demo) [SKIP: omit]
{(DEMONSTRATE the failure — a leaked scenario, a variance plot — don't assert it.
Name the specific measurement being demonstrated; the "What it caught" GATE below
must report the after-result on THIS same measurement.)}

## {The method}                                     (~200 words + sketch) [SKIP: verify]
{(Design principle first, implementation sketch second. WHAT the method
guarantees and why, before HOW it's coded.)}

## GATE {What it caught}                            (results table/figure + ~100 words) [SKIP: blocker]
{(Real results from running it. This slot empty = article not publishable.
Requires an actual results table/figure produced by the run — observed results
qualify whether quantitative or not (Story 13.86, #389): a benchmark table, or
rows of counted instances / caught-defect episodes / gate outcomes, each row
pinned like any sourced claim. Prose-only or a bare
[VERIFY] placeholder does NOT satisfy this GATE — reporting the after-result on
the SAME measurement the naive approach demonstrated above.)}

## {What this measurement cannot tell you}          (~80 words) [SKIP: verify]
{(Scope the metric's validity. For an evaluation audience this section IS the
credential. Mandatory: a methodology article that omits its limits is not
publishable.)}

## {Reproduce it}                                   (links + ~50 words) [SKIP: accept-later]
{(Code, dataset, leaderboard. A methodology article without reproduction links
undercuts its own thesis. Links must resolve to real code/dataset/leaderboard —
not prose promises; an empty or placeholder link blocks completion, per the
source-pointing invariant.)}

## GATE {Pointer block} [SKIP: blocker]
*(The shared pointer block — see [`CONVENTIONS.md`](CONVENTIONS.md). Rendered
from user config; unfilled = not publishable.)*
