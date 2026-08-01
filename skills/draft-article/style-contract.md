<!-- style-contract.md — draft-article companion (Story 20.139, #1201; umbrella
     #1191). Read on entry to stage 3, alongside stages/stage3.md: the style
     contract is consumed AT GENERATION. -->

## The style contract — read once per run, at generation

The owner keeps **one versioned style contract** in the articles repository
(the `output.drafts` destination). It is an **onboarding-lifetime** fact, not a
per-article one: the point of the artifact is that the styling decision was
made once and is **removed from every article's production loop**. So this
stage **reads** it and composes against it. It never asks the owner a style
question, never proposes a per-run style, and never opens a gate here.

Read it **before the per-section fill**, once:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/style-contract.py read --root <host-repo>
```

`--repo <articles-repo>` bypasses resolution when the destination is passed
directly. `--json` returns the same payload machine-readably.

### What comes back, and what to do with each section

The contract's sections are sorted by **what can carry them**, and that sort is
the instruction — the reader labels each section with its carrier:

| Section | Carrier | What this stage does with it |
|---|---|---|
| `REGISTER` | judgment | compose to it — the assumed reader background is a composition input, and re-expression happens **here, at the source**, because no downstream check can repair a register mismatch |
| `STRUCTURAL VOICE` | judgment | compose to it — it constrains the argument plan and the section shapes, alongside the structure the owner chose |
| `LEXICON` | mechanical | nothing new: the **existing** coinage lint already carries it (the quality gate's dim-3 first-use-gloss pass). Do not add a second lexical check |
| `FIGURES` | already ratified | a **pointer** to `SPEC-article-visuals` — the visual-set plan and the fallback ladder in `stages/stage3.md` are unchanged and are not re-derived from the contract |
| `SYNTAX PROFILE` | **none, deliberately** | read the clause and write to it as judgment. **Measure nothing** — see below |

**The syntax profile carries no instrument, and that is the design.** Sentence
length, hedging density, person and voice are the only section a machine can
measure cheaply, which is exactly why the section attracts enforcement; a
distribution check is a **proxy for voice rather than voice**, and an
instrument that measures the measurable *neighbour* of a property teaches
conformance to the neighbour. Do not count sentences, compute a hedge ratio, or
emit a syntax score anywhere in this run — a syntax metric added here has
**failed** this contract rather than implemented it.

**Exemplars are declared and empty.** The contract declares exemplar slots
looked up by contract **section id** (`register`, `structural-voice`) and ships
them empty: no accepted articles exist to pin yet. When a slot is empty, there
is nothing to imitate — **never substitute an article, a rendering, or your own
sample for a missing exemplar.** When a slot is filled, the reader returns its
pointer and the named passage is the reference for that section.

### When the contract is absent, or malformed

**Absent — proceed, and say so.** The reader exits 0 with the absence stated
verbatim; the plugin **never creates the file**. The contract is owner-authored
and this tool's only interaction with it is a read, so an absent contract is a
fact about the destination, never a prompt, a gate, or a setup offer. Compose
the draft as the pipeline otherwise does and carry the reader's line into the
completion summary's informational bucket.

**Malformed — relay verbatim, then degrade.** A missing version field, a
missing section, or a section declaring the wrong carrier exits 4 naming the
defect. Relay those lines to the owner **verbatim** (the global relay-and-stop
rule) and continue **without a contract** — a half-applied contract is worse
than a declared absence, and fixing the file is the owner's act, not this run's.

**A section with no authored clause is not a defect.** The contract's structure
ships ahead of its content; a section marked `NOT YET AUTHORED` carries no
constraint, and nothing is inferred to fill it.

### The record format

The canonical format is printed by the reader itself —
`python3 ${CLAUDE_PLUGIN_ROOT}/scripts/style-contract.py format` — and is
restated nowhere, here included. An enumeration copied into a second place goes
stale silently; if an owner asks what to author, show them that output.
