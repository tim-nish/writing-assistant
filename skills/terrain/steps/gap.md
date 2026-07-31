# Step 4 — the gap artifact (only when the brief carries `gap`)

**Read this file on entry to Step 4 of [`../SKILL.md`](../SKILL.md)** — never up
front, and never because the skill was merely invoked. It carries this step's
operating detail verbatim; the dispatcher carries the sequence and the
commands.

Whenever the selected element's host-repo verdict was anything but `matched`,
the `brief` output carries a `gap` block — `episodic-unrecorded`, `no-episode`,
`cannot-determine`, or `episode-served` (the last is the section at the foot of
this file: the hub is serving the episode as the Strand's arc). **The draft still proceeds — this
step runs beside it, never instead of it.** Do both:

1. **Relay the disclosure** (`gap.disclosure`) in one or two lines: what the
   verdict means and, for `no-episode`, that the draft is offered on the
   owner-attributed framing tier, stated as such.
2. **Create the NEEDS-RECORDING tracking artifact in the target repo** from
   `gap.needs_recording`: append `entry` as a list item under a
   `## NEEDS-RECORDING` heading in the declared journey doc (`target_file`,
   creating the heading if absent) — or, when the owner prefers, open a GitHub
   Issue in `target_repo` carrying the same content. This is the one write
   this flow makes outside the run workspace and the View, and it is what
   turns a gap into a discharged backfill: recording the episode there makes
   the next run match it (the flywheel).

A `cannot-determine` gap is relayed as its disclosure alone — an absence is
asserted only where it was established, so no recording task is minted from a
lookup that did not look.

## When the hub is serving the episode (`episode-served`, Story 20.91, #1044)

Every gap now carries an `episode` block beside the host-repo join. When the
hub serves the Strand's journey arc, the gap's verdict is **`episode-served`**,
the mechanical host-repo verdict is kept under `host_join`, and `episode.arc`
carries the served rendering with its cite. **Do not relay such a Strand as an
unrecorded episode** — the system is carrying that episode, and the arc crosses
into drafting as declared source material at the recorded pin.

**Both steps above still run, unchanged.** The two things are **adjacent, not
substitutes**:

- **Recording the episode host-side** is what eventually feeds **evidence** —
  so the NEEDS-RECORDING artifact is still created, exactly as for any other
  gap, and an arriving arc never discharges it.
- **The served arc** is material that already existed and was simply never
  consumed. It is not evidence, it does not satisfy the article floor (every
  article still carries ≥1 sourced or derived claim resolving at the ship
  gate), and repositories remain harvest **scope**, never evidence binding.

Neither closes the other. When no arc is served, `episode.served` is `false`
and `not_served_reason` says which absence it is — *"no arc exists"* and *"no
arc arrived"* are different findings; relay the reason as given and never
collapse them.
