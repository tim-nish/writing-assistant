# Step 1 — assemble the map

**Read this file on entry to Step 1 of [`../SKILL.md`](../SKILL.md)** — never up
front, and never because the skill was merely invoked. It carries this step's
operating detail verbatim; the dispatcher carries the sequence and the
commands.

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/terrain_map.py assemble --root <host-repo> > "$WS/map.json"
```

The map is **derived, never stored**: it is recomputed from the articles repo
and the shipped consumption view at every invocation, and nothing it writes is
read back. Exit 3 means no articles repo is resolvable — relay the error, which
already names the declaration that is missing, and stop.

Read, but do not re-explain, what it carries: the **elements** — every hub
Lesson and every served Journey rendering, each its own selectable idea, each
quoting the served `gloss:` / `journey_gloss:` rendering (the plain-language
text the hub ratified at its distill gate — **never the recall one-liner**;
where the rendering is not being served the map says so, `gloss.reason`, and
you relay the disclosure rather than substituting other text) — plus the
coverage disclosure. The per-member Strand count on Screen 1 is **the only
depth affordance** — a cue for choosing where to look, never a gate — and a
consumed Strand is shown **marked consumed, not hidden**.

If `coverage.complete` is false, say so in one line with the count the
disclosure names: the map read up to its bound and the rest is listed, not
silently dropped.

**Decision/reversal Strands (E rows) have their own axis** (Story 20.25,
#860; SPEC-terrain CAP-2 as amended 2026-07-28). Screen 1 offers **two**
axes: **by tag** over Lessons and Journeys, and **by topic** over decisions
and reversals. A decision line's topic *is* its shard key, so nothing is
joined or derived for either. Relay both listings — an E row is reached
under its topic, not hunted for under a tag and never given one.

The two vocabularies **overlap by name** (a name can be both a served tag
and a served decision topic, holding different material), so always carry
the axis word with the member when you present or resolve a choice. A
Strand belonging to neither axis appears in the **outside-both disclosure
line**; relay that line as given.

**Usability verdict per candidate (the topic↔evidence join, #669; enforced on
every element, #799).** Each item AND each element carries a `usability`
verdict resolving whether the target repo can *evidence* it, and the map's
`needs_recording` list is the join's product. The verdict is **surfacing,
never a filter and never a refusal**: every element appears whatever its
verdict says, every element stays selectable, and selecting an unmatched one
yields the gap disclosure plus its tracking artifact (Step 4) while the draft
proceeds. A flow that refuses to draft on a missing-Evidence verdict is the
defect this pivot removed (owner ruling, #799):

- **matched** — a declared source (for a hub lesson, a `journey:` entry carrying
  its slug — #671) resolves into the read boundary → offer as **draft-ready**,
  evidence pre-located. The verdict carries the pointers `checked` (audited).
- **episodic-unrecorded** — a hub lesson no declared source carries → it appears
  in `needs_recording` as a **NEEDS-RECORDING task** naming the lesson slug, the
  episode, and the target `journey:` file. **Present this list — never silently
  filter to matched**: the unusable topic IS the map's product, a named backfill
  worklist (recording an episode there makes the next harvest match it — the
  flywheel).
- **no-episode** — a hub lesson with no locatable episode: **still selectable
  and still drafted** — offered on the **owner-attributed framing tier** (the
  Story 17.1 attribution tier: a framing contribution, not sourced claims),
  stated as such. The seam serves index lines and renderings, not lesson
  bodies, so the map cannot mechanically tell `no-episode` from
  `episodic-unrecorded` (cannot-determine); it defaults an unmatched hub
  lesson to `episodic-unrecorded` and leaves the `no-episode` call to the
  owner at offer.

The join **locates** evidence, it never **supplies** it: no hub line becomes a
SOURCE pointer, and every offer stays a proposal the owner ratifies.
