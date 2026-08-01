# Step 4 — the scope statement (only when the brief carries `gaps`)

**Read this file on entry to Step 4 of [`../SKILL.md`](../SKILL.md)** — never up
front, and never because the skill was merely invoked. It carries this step's
operating detail verbatim; the dispatcher carries the sequence and the
commands.

**This step asks the owner nothing, asserts nothing about the owner's
repository, and mints no tracking artifact.** The host-repo episode join that
used to do all three was removed (SPEC-writing-assistant and SPEC-terrain, both
amended 2026-08-01, #1183): it matched a hub lesson's filename stem against the
target repo's declared `journey:` files, searched **zero bytes** wherever no
such block was declared and reported an absence anyway, and could only ever be
satisfied by the recording to-do this step itself used to write. The four
verdicts, the `host_join` block and that to-do are gone with it.

## 1. State the scope of the selection

Relay, in one or two lines, **which selected Strands carry a bound repository
and which do not** — the host repo the run was invoked against is the binding,
and `harvest_scope` on the brief states what is and is not served for it. This
is a fact **about the selection**, derived from what the owner just picked. It
is never a claim that something is or is not recorded in the owner's tree: that
claim needs a source this flow does not read, and asserting it from an empty
lookup is what #1183 removed.

Relay `harvest_scope.not_served_reason` **as given** when the union is not
served. A scope that is owed and not served is said as such, never as "no
scope".

## 2. Relay each member's episode disclosure

Every member of the selection carries a `gaps` entry with its `disclosure` —
relay it as given. Nothing here is a gate: `drafting` states so on the payload,
and the draft proceeds beside this step exactly as it did before.

## When the hub is serving the episode (`episode-served`, Story 20.91, #1044)

Every gap carries an `episode` block. When the hub serves the Strand's journey
arc, the gap's verdict is **`episode-served`** and `episode.arc` carries the
served rendering with its cite. The arc **crosses into drafting as declared
source material at the recorded pin** — carried quoted, never re-expressed
here.

**The article floor is unchanged.** The served arc is material that already
existed and was simply never consumed. It is not evidence, it does not satisfy
the article floor (every article still carries ≥1 sourced or derived claim
resolving at the ship gate), and repositories remain harvest **scope**, never
evidence binding.

When no arc is served, `episode.served` is `false` and `not_served_reason` says
which absence it is — *"no arc exists"* and *"no arc arrived"* are different
findings; relay the reason as given and never collapse them.
