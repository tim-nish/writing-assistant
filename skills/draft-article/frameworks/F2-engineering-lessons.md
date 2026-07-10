# F2 — Engineering lessons

**Use when:** sharing lessons, design decisions, failure findings from development.

**GATE (entry) — a framework-selection precondition, not a fill-in slot:** at
least one real surprise/failure with an artifact you can show (log excerpt, diff,
measurement). No showable artifact → the lesson isn't ready to write.

Slot syntax, the config-bound frontmatter, and the shared pointer block are
defined once in [`CONVENTIONS.md`](CONVENTIONS.md) — F2 reuses them and does not
re-implement them. `Context` and the pointer block appear **exactly once**; the
lesson unit between them repeats. Section order is load-bearing.

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

<!-- Lesson unit START — repeat this block (slots 2–6) for up to 3 lessons.
     >3 lessons → split into two articles. Do NOT repeat Context or the pointer
     block; each repeat is one lesson with its OWN "What actually happened" artifact. -->

## {What I believed going in}                       (~60 words)
{(The reasonable-sounding assumption. Readers must recognize themselves in it.)}

## GATE {What actually happened}                    (~120 words + artifact)
{(The surprise, WITH the artifact: log excerpt, diff, number, screenshot.
This slot empty = article not publishable (AP-10). Each lesson needs its OWN
artifact — the evidence gate is enforced once per lesson, not once per article.)}

## {Why — the mechanism}                            (~120 words)
{(Root cause, not symptom. This is the transferable part; be precise.)}

## {What I changed, and what it cost}               (~100 words)
{(The fix or decision, with the tradeoff you accepted stated plainly.)}

## {When this applies to you — and when it doesn't} (~80 words)
{(Generalize with boundaries. Scoping the lesson honestly beats overselling it.)}

<!-- Lesson unit END -->

## GATE {Pointer block}
*(The shared pointer block — see [`CONVENTIONS.md`](CONVENTIONS.md). Rendered
from user config; unfilled = not publishable.)*
