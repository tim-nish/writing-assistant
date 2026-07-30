# The placement cover — counted after composition

Companion to [stage3.md](stage3.md) (Story 20.61, #945;
SPEC-article-draft-pipeline CAP-3, "Composition over an owner-selected Strand
set", 2026-07-30). Read it when the run's brief carries the owner's selected
**Strand set**; otherwise nothing here applies.

The completeness the owner was promised **at selection** follows the set into
**drafting**: each composed candidate **places every selected Strand, or
discloses the omission by name**. The brief records the set as `members`
(index, slug, served gloss, cite — SPEC-terrain `presentation.md` CAP-3, the
#937 selection-is-a-set clause); this reads that set and never redefines it.

- **Counted after composition, on the output.** The count reads the emitted
  candidate's actual `sections`/`beats` — never the composer's inputs, options
  or intent. *A composer that cannot omit in principle can still omit in fact*,
  so an assertion about the algorithm discharges nothing.
- **A cover, not a partition.** A Strand placed in **two or more** sections
  **passes** — a Strand carrying four tags belongs in four co-tag sections, and
  forcing it into one needs a tie-break, i.e. a machine deciding which
  relationship the owner may see. Only **zero** placements is an omission.
- **Per candidate, not just the default.** Every candidate carries its own
  `cover` and its own disclosure, so choosing a non-default candidate cannot
  silently choose an undisclosed omission.
- **Disclosure, never rejection.** A candidate with omissions is still
  **offered**, with the omitted Strands **named individually** in the rationale
  the owner reads. The cover **annotates only** — it never reorders, filters,
  drops or chooses among candidates. Anything that reduces what reaches the
  owner is on the far side of the second-proposer boundary.
- **No member set: no cover check is imposed** and the output is exactly the
  element-selection path's. A recorded selection carrying **no** member set is
  a defect against SPEC-terrain `presentation.md` — report it, never work
  around it here.

The payload, per candidate:

```
"cover": {"counted": "after-composition", "selected": 3, "placed": 2,
          "placements": {"L3": 1, "L7": 1, "L9": 0},
          "omitted": [{"index": "L9", "slug": "cache-warmth", "gloss": "…"}],
          "complete": false}
```

plus a run-level `strand_cover` summary naming each candidate's omissions.
**Present the omissions with the candidate** — the owner chooses a structure
knowing what it drops, which is the whole of the contract.
