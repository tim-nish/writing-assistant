# F2 — Engineering lessons

**Use when:** sharing lessons, design decisions, failure findings from development.

**GATE (entry) — a framework-selection precondition, not a fill-in slot:** at
least one real surprise/failure with an artifact you can show (log excerpt, diff,
measurement). No showable artifact → the lesson isn't ready to write.

Slot syntax, the config-bound frontmatter, and the shared pointer block are
defined once in [`CONVENTIONS.md`](CONVENTIONS.md) — F2 reuses them and does not
re-implement them. `Context` and the pointer block appear **exactly once**; the
lesson unit between them repeats. Section order is load-bearing.

**Each lesson is a story element** (CAP-9/#428) — one case of the general
evidence cluster defined in the [SKILL](../SKILL.md#story-element-selection--the-model-and-its-disclosure-cap-9-428):
a cluster of fact-sheet entries with a **stable id** (id is identity, the
evidence pointers are derived payload). Selection of which lessons the article
covers is disclosed per element (the interview journal + completion summary
state the id and the rule that selected it); this framework does not re-specify
that — it just names lessons as the elements F2 selects over.

## Visual slot (SPEC-article-visuals CAP-1)

**F2 declares one optional before/after or timeline visual** — showing the change
over time that the lesson turns on. It is **optional** and **proposed, not
auto-inserted** (Story 8.2). If the owner **declines** it, the slot is
**omitted entirely** — no `[Figure: …]` or placeholder residue is left in the draft.

## Frontmatter

Config-bound `article` frontmatter (rendered per language from user config; see
[`CONVENTIONS.md`](CONVENTIONS.md)). F2 fills its value slots:

- `title` — *(the lesson as a claim, e.g. "Structured discovery halved our token bill")*
- `summary` — *(≤240 chars: the lesson + the evidence type behind it)*
- `topics` — *({kebab-case} tags)*
- `related.projects` — *(the project the lesson came from)*

## {Context}                                        (~100 words)
{(What you were building and why; link the project record. Only enough
context to make the lesson intelligible — this is not the project intro.)}

<!-- Lesson unit — these slots are each lesson's CONTENT OBLIGATIONS, not a
     literal heading skeleton to reproduce verbatim per lesson (CAP-3/#440/#434).
     Fill each lesson FROM the run's argument plan ($WS/argument-plan.md): the
     whole article is one ARC (shared context → distinct, varied lesson sections
     → one synthesis), and a section's structure varies with its content — a
     lesson may fold or reorder these obligations rather than emit five identical
     headings. A slot met with a single under-evidenced sentence fails the
     Stage 3→4 gate.
     >3 lessons is a DECLINABLE SUGGESTION to split, not a rule (CAP-8, #432):
     depth is owner intent — surface "~N lessons; one deep-dive or split?" as an
     owner choice, and honor a depth/scope directive (deep-dive keeps them in one
     article). Do NOT repeat Context or the pointer block; each repeat is one
     lesson with its OWN "What actually happened" artifact. -->

## {What I believed going in}                       (~60 words) [SKIP: omit]
{(The reasonable-sounding assumption. Readers must recognize themselves in it.)}

## GATE {What actually happened}                    (~120 words + artifact) [SKIP: blocker] [EVIDENCE: episode|example|measurement]
{(The surprise, WITH the artifact: log excerpt, diff, number, screenshot.
This slot empty = article not publishable (AP-10). Each lesson needs its OWN
artifact — the evidence gate is enforced once per lesson, not once per article.)}

## {Why — the mechanism}                            (~120 words) [SKIP: verify]
{(Root cause, not symptom. This is the transferable part; be precise.)}

## {What I changed, and what it cost}               (~100 words) [SKIP: verify]
{(The fix or decision, with the tradeoff you accepted stated plainly.)}

## {When this applies to you — and when it doesn't} (~80 words) [SKIP: verify]
{(Generalize with boundaries. Scoping the lesson honestly beats overselling it.)}

<!-- Lesson unit END -->

## GATE {Pointer block} [SKIP: blocker]
*(The shared pointer block — see [`CONVENTIONS.md`](CONVENTIONS.md). Rendered
from user config; unfilled = not publishable.)*
