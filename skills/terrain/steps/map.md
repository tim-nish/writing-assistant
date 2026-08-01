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

**No writability verdict, and no host-repo join (removed 2026-08-01, #1183).**
The map once carried a writability verdict per item and per element, plus a
host-side recording worklist and its target file. All of them are gone: the
join behind them matched a hub lesson's filename stem against the target repo's
declared `journey:` files, searched **zero bytes** where no such block was
declared and stamped an absence anyway, and its key was the hub's own internal
filename stem, so the only text that could ever satisfy it was the to-do the
gap step wrote for it. **Evidence still never blocks drafting** — there is now
nothing that could, because no verdict is computed at all.

**What the map still carries about episodes** is the hub's own service: an
element's served journey arc (`journey`, `journey_cite`) with its absence typed
(`journey_unavailable`). That half was never defective and is untouched.
