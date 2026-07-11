# F4 — Research survey

**Use when:** low-cadence reputation-anchor surveys (e.g. signature methods).

**GATE (entry) — a framework-selection precondition, not a fill-in slot:** you
have read the primary papers, and a related preprint/repo of yours exists or is
imminent (spec §6.2 paper+code pairing). No paper+code pairing of your own → this
isn't yet a reputation-anchor survey.

Slot syntax, the config-bound frontmatter, and the shared pointer block are
defined once in [`CONVENTIONS.md`](CONVENTIONS.md) — F4 reuses them and does not
re-implement them. Scope, the map, My take, the reading list, and the pointer
block each appear **exactly once**; the branch unit between the map and My take
repeats per taxonomy branch. Section order is load-bearing.

## Visual slot (SPEC-article-visuals CAP-1)

**F4 declares one landscape table or concept map** — the field map in *The map*
section (a table when the landscape is comparative, a concept map when it is
topological). It is **proposed, not auto-inserted** (Story 8.2). If the owner
**declines** it, the slot is **omitted entirely** — no `[Figure: …]` or
placeholder residue is left in the draft.

## Frontmatter

Config-bound `article` frontmatter (rendered per language from user config; see
[`CONVENTIONS.md`](CONVENTIONS.md)). F4 fills its value slots:

- `title` — *(field + angle, e.g. "Signature methods for market data: a field guide")*
- `summary` — *(≤240 chars: scope + who it's for)*
- `topics` — *({kebab-case} tags)*
- `related.publications` — *(your preprint slug — F4's paper+code pairing)*

## {Scope and audience}                             (~80 words) [SKIP: verify]
{(What's covered, what's excluded, who this is for, and the as-of date —
surveys age; dating them keeps them citable.)}

## {The map}                                        (table or diagram + ~100 words) [SKIP: verify]
{(A taxonomy of approaches. The map is the artifact readers bookmark. Every
approach named here must resolve to a citation — no uncited claims.)}

<!-- Branch unit START — repeat this block once per taxonomy branch (no fixed
     count). Each branch carries its OWN 2–4 key-paper citations. Do NOT repeat
     Scope, the map, My take, or the reading list. -->

## {Branch: core idea / key papers / when to use / open problems}   (~150 words each) [SKIP: verify]
{(Per branch: the idea in 2 sentences, 2–4 key papers, the practical
'use this when', and what's unsolved. The key papers are this branch's OWN
resolvable citations — every claim in the branch points to one.)}

<!-- Branch unit END -->

## GATE {My take}                                   (~150 words) [SKIP: blocker]
{(Where the field goes and what YOU are building on it — the owner-evidence
slot that keeps a survey within AP-10. REQUIRES BOTH: your angle on the field's
direction AND a link to your preprint/repo. An opinion with no link, or a link
with no angle, does not satisfy this GATE.)}

## {Reading list} [SKIP: accept-later]
{(The papers, ordered by 'read this first', one-line annotations. This is a
distinct deliverable — the curated entry path — not a concatenation of the
per-branch key papers.)}

## GATE {Pointer block} [SKIP: blocker]
*(The shared pointer block — see [`CONVENTIONS.md`](CONVENTIONS.md). Rendered
from user config; unfilled = not publishable. This GATE is independent of the
My-take GATE — satisfying one does not satisfy the other.)*
