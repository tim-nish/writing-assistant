# Owner terms — what the words on the screen mean

The reader-facing codebook for terms this product uses **on surfaces the owner
reads**. It exists because a term meant to reach the owner is defined where the
owner reads it, in the act that coins it — the symmetric half of the rule that
already required a newly coined term to be added to the lint list when it is
coined (`specs/spec-writing-assistant/SPEC.md`, owner-surface register,
property (d)).

This page is **not** a glossary of implementation vocabulary. Internal terms —
stage names, framework ids, field names, enum values — do not belong on an
owner-facing surface at all, so they are not defined here; defining them would
license their use. What belongs here is the short list of terms the product
genuinely asks the owner to think in.

Every term below is declared as first-class owner-facing vocabulary in
`scripts/topic-map-directions.py` (`OWNER_TERMS`) and checked by
`scripts/check-owner-term-codebook.sh`: a declared term with no entry here
fails the check, and an entry here for a term nothing declares fails it too.

## brief

**What you want written, in your own words.** A brief is the outcome of
choosing a direction: one short statement of what to cover, which the run then
drafts from. It is not an outline, a title, or a summary of an article that
already exists — nothing is drafted until a brief exists.

Wording you accept from a machine-proposed option becomes your wording. You
can always write your own instead; free text wins over any offered choice.

## group claim

**What a group of Strands has in common.** When a listing is grouped, each
group carries one or two sentences saying why its members belong together —
the thread running through them. It is the germ of an article's thesis: if the
sentence reads as something worth arguing, the group is worth writing from.

It is written by the machine and marked as such. It never replaces a Strand's
own words, and it never decides anything — a group claim you disagree with
costs you nothing, because you still pick Strands by their own index.

**Not a fact-sheet claim.** A fact-sheet claim is evidence: it is copied
verbatim from a source and carries a provenance class. A group claim carries
neither — it describes a grouping on screen. The two words are kept apart on
purpose, so that neither is read as the other.

When the same sentence is carried into a proposed thesis, it plays that
proposal's claim role there. Same words, different job, named per surface.

## Strand

**One selectable piece of recorded material.** A Strand is a single item you
can pick and have written about — a Lesson (a rule distilled from experience)
or a Journey (how a position changed over time).

Decisions from the record are **not** Strands. They are a separate population
with their own listing, reached by topic rather than by tag. The two are kept
apart deliberately: one word covering both would let a count taken over one be
read as a statement about the other.

Strands are the unit of choice: listings show them whole and never rank or cap
them, and picking one is what produces a [brief](#brief). A count of Strands is
a signal for your judgment about where to look, never a limit on what you may
choose.
