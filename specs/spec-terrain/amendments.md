# SPEC-terrain — ratified amendments, 2026-08-01 onward

Companion to `SPEC.md`: the dated, ratified amendment blockquotes of this
spec. **New amendments append here, newest-last** — `SPEC.md` carries the
pointer, never the blocks.

Amendments dated **2026-07-30 -> 2026-08-01** live in `amendments-2026-07-30--2026-08-01.md`, relocated verbatim on
2026-08-01 when this file crossed the era-split threshold declared in
`scripts/check-skill-budget.sh`. That file is **closed**; nothing appends to it.

`amendments-archive.md` holds 2026-07-24 -> 2026-07-29 and is also closed.

The cut is **mechanical and is not a decision** (Story 20.88, #1046): the
threshold lives in the check, which is the single enforcement copy, so no
byte figure appears here or in any spec. Ratified text is never compacted
and no already-relocated text moves — the rule is prospective.

> **Amended 2026-08-03 (triage, #1331 / #1338) — a Brief has a durable
> host-repo home and an enumerated selection gate, and the run's binding to it
> is the Brief's stable ID.** The two issues were triaged as one decision
> because they are the same defect from both ends: a selection gate cannot be
> built over artifacts with no enumerable home, and a binding that lives in
> run state can be dropped by any writer that omits it.
>
> **What binds.** (a) **The Brief's home is the host repository**, beside the
> other artifacts a person works with, not a run workspace keyed by recency.
> The pipeline already distrusts the old location in its own words — the brief
> record writes `brief_source` **pins first**, "because the path is a state-dir
> location that goes stale by relocation while still looking authoritative"
> (`skills/draft-article/stages/stage0.md`). This amendment stops working
> around that and moves the artifact. (b) **`stage0` gains an enumerated
> selection gate** over the Briefs that home makes enumerable: the machine
> composes the options, the owner picks one, and the free-form override remains
> — a gate whose answer is "type a state-dir path" fails the gate-input
> contract in the same act as offering no gate at all. (c) **The run's binding
> is the Brief's stable ID**, carried where every checkpoint write must pass it
> rather than inside `run_state`, which a stage-state checkpoint can and did
> omit. A checkpoint that would leave the binding absent while one exists is
> **refused**, and autostart distinguishes three states — *bound to this
> Brief*, *bound to a different Brief*, *no binding recorded* — rather than
> reading the third as the second.
>
> **The observed cost this is written against (#1338).** On run
> `20260803T105759-992700` a checkpoint carrying no `run_state` dropped the
> binding, so a same-brief invocation read the same Brief as a different one
> and minted a fresh run — the automatic path silently taking the expensive
> branch, with nothing deleted and nothing wrong-looking. The ratified
> contract is *automatic, same-brief-only* (#1207); a discriminator that reads
> false makes the contract's cheap branch unreachable. The run also left an
> empty workspace behind, which is the cost made concrete.
>
> **Declined, and why it was genuinely available:** a machine-global Brief
> index — briefs stay in state, an index enumerates them, the gate reads the
> index. It keeps Briefs off any publication surface, which is a real property.
> It loses because the index is a **derived second ledger** over run
> workspaces: a stored artifact holding what is recomputable from the
> workspaces themselves, which then drifts and needs repair — the shape the
> standing counting stance declines. The homed artifact needs no index because
> the directory **is** the enumeration.
>
> **What would overturn this amendment:** a Brief proving to routinely name
> work that must not be published — the home is in a repository, and a Brief
> that cannot live there is evidence the index was the right shape after all.
> The migration is one-way in practice, so this is the clause to check first.
>
> Delivery: stories 20.191 (the home and its migration), 20.192 (the stage0
> selection gate), 20.193 (the non-droppable binding and autostart's three
> states).
