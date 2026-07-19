# F5 — Working note

**Use when:** assembling the owner's newsletter issue — a lightweight working
note built from recent activity. The issue's contract is **assembly <1hr**
(SPEC-article-frameworks, working-note ratification 2026-07-16), which is why
this framework runs the **slim pipeline profile**, not the full pipeline.

**Profile: SLIM** — no 5-question interview (`consume --framework working-note`
routes straight to fill; NEEDS-OWNER material surfaces as `[VERIFY]` or
blockers at fill, never as questions), and a lighter quality gate
(`quality-gate --profile slim`: mechanical dimensions only; the dim1–2 rubric
judge is waived by contract). Variant renderings (email + web archive) come
from the working-note slim packaging profile (SPEC-platform-variants,
"Working-note slim profile").

**Sources — ratified constraints (binding, verbatim from the ratification):**

1. Sources are the active repos' recent activity **plus the owner's policy
   recall surface read via the existing policy-source seam mechanics —
   read-only, pinned, lessons first**.
2. The policy hub's **Q&A history archive is never a harvest source** —
   promotion to the recall surface is the only path by which hub content
   becomes harvestable.
3. **Published text carries public repository links only.**

Slot syntax, the config-bound frontmatter, and the shared pointer block are
defined once in [`CONVENTIONS.md`](CONVENTIONS.md) — F5 reuses them and does
not re-implement them. There are **no `[SKIP: …]` tags** in this framework:
skip semantics annotate interview-fed slots, and the slim profile has no
interview. Section order is load-bearing; the four blocks are fixed — a
working note with a block missing is a different artifact, not a shorter note.

## Visual slot (SPEC-article-visuals CAP-1)

**F5 declares no visual slot** — the lightweight profile never proposes one.
No `[Figure: …]` placeholder ever appears in a working note.

## Frontmatter

Config-bound `article` frontmatter (rendered per language from user config; see
[`CONVENTIONS.md`](CONVENTIONS.md)). F5 fills its value slots:

- `title` — *(the period's one concrete claim, not "weekly update N")*
- `summary` — *(≤240 chars: the lesson + the number)*
- `topics` — *({kebab-case} tags)*

## GATE {One lesson}                                (~80 words) [EVIDENCE: episode|example]
{(One transferable lesson from this period's own work, stated as a claim with
its boundary — where it applies and where it doesn't. AP-10: it must come from
the owner's logs/decisions/scars, not from reading. One lesson exactly; a
second lesson is next issue's.

Tell it as an ARC (SPEC-article-frameworks, "Fill — narrative-arc sourcing",
#425): misconception → turning point → evidence → abstraction. Source it from
the recall surface via the seam, lessons-first — never the batch history
(constraint 2). SELECTION INPUTS: a lesson carrying a `## Journey` section
(original framing → actual question → what moved it, with an `origin:`
marker), a topic-thread Declined line, or a struck-through superseded decision.
STRUCTURE MAPPING: misconception = the Journey's original framing / superseded
position; turning point = "what moved it"; evidence = the lesson's PUBLIC
Evidence pointers only (constraint 3); abstraction = the lesson one-liner. A
Journey may be hub-native or backfilled (`origin: reconstructed <date>`); both
are valid sources, but SURFACE the origin marker to the owner at selection.
With no lesson carrying a usable Journey / reversal record, do not invent an
arc — fall back to a plain one-lesson claim and note the gap.)}

## GATE {One number}                                (~40 words + the number) [EVIDENCE: measurement]
{(One real observed number from the period — a measurement, count, or cost —
with its source pointer. A number that was not actually observed is not a
working note; estimates and targets do not fill this slot.)}

## {Published links}                                (~40 words)
{(What shipped or published this period. Public repository and article links
ONLY — ratified constraint 3; a private link here is a publish defect, not a
style choice.)}

## {What I'm building}                              (~60 words)
{(Current direction — what the next period's work is aimed at. Forward-looking
and honest; no promises, no roadmap language.)}

## GATE {Pointer block}
*(The shared pointer block — see [`CONVENTIONS.md`](CONVENTIONS.md). Rendered
from user config; unfilled = not publishable.)*
