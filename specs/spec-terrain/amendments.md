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

> **Amended 2026-08-03 (triage, #1410) — STRUCTURE IS COMPOSED PER-ARTICLE FROM THE BRIEF'S OWN STATE, never selected from a framework stock; a `structure` gate joins the brief's selection sequence.** *(owner decision record — 2026-08-03 (article structure proposed, not templated))*. The system maintains no menu of predefined structural frameworks to pick from per article. Instead the brief's sequence — already stated in `skills/terrain/steps/brief.md` as *"a thesis chosen from candidates, then a structure, and onward"* — gains its missing member: after journey incorporation, a **`structure` gate** (declared in `draft_gates.GATES`, in pipeline order, same mechanism as the `thesis` and `journey-incorporation` gates) carries 2–3 candidate structures **composed from this Brief's adopted thesis, selected member set with served glosses, and each member's served arc at the pin**. A candidate is stated **operationally** — ordered moves, never a framework name — with a one-line rationale naming the material that motivates it (*"open with the failure case: J2 is the strongest concrete anchor for the thesis"*). Journey-shaped options (failure-case-first, reversal-led) fold into this gate and say which served arc licenses them.
>
> **Relation to #911's window, stated so neither governs the other's half.** #911 demoted F1–F5 to candidates with a removal window (default REMOVE at expiry); this ruling removes the **menu path now** — no path enumerates a framework list for selection — while the window keeps governing the **assets**: whatever remains of `skills/draft-article/frameworks/` serves as reference prose a candidate *may* cite ("this is close to ki-shō-ten-ketsu") when that helps the owner evaluate it. #911's bespoke-provenance instrument survives unchanged: every accepted structure records its provenance with an explicit `bespoke` value, so the proposer ignoring the reference prose stays a measurement, never a silence.
>
> **Relation to the stage-3 `narrative-structure` gate, named rather than left to collide.** The shipped `structures` sub-command derives candidates from the selected elements' evidence kinds at stage 3. Under this ruling the owner's structure decision is made **at the brief**; a brief-adopted structure crosses into drafting as a **disclosure** — direction at the brief; placement belongs to the outline; concrete design belongs to realization, the same crossing the journey register uses — and the stage-3 gate is **not re-raised** over a brief that carries one, because a decided owner question is asked exactly once. A run whose brief carries no structure disclosure (a direct-path draft with no brief) keeps the stage-3 mechanism as its fallback; nothing here removes it.
>
> **Requirements inherited unchanged, cited not restated:** every candidate is composed over the same complete selected set; every candidate places every selected Strand or discloses the omission by name; placements cite served renderings at the pin; enumerated never ranked-and-trimmed; the recommendation rides beside the candidates with its axes and overturn condition; free text wins. Delivery: story 20.211.

> **Amended 2026-08-03 (triage, #1411) — THE BRIEF CARRIES A PLAIN-REGISTER COMMITMENT, derived under operational controls at a `plain-register` gate; never a naive "explain for a child" prompt.** *(owner decision record — 2026-08-03 (article structure proposed, not templated))*. The commitment is a **child-level translation of the adopted thesis plus a child-level rendering per selected Strand**, determined at the brief — not improvised at the fill — because both article ends realize it and the close composes the simplified Strand renderings (companion #1412). The derivation hazard the owner named is built out, not filtered after: asking cold for a child-comprehensible thesis reliably produces condescension or lossy stock metaphors, so the gate's `requirements` define plain register as **checkable constraints** — no term of art without an in-sentence explanation, one relation per sentence, a concrete subject doing something — and never as audience impersonation; the article's audience is unchanged, the register is the constraint.
>
> **Every candidate carries its round-trip concession.** The plain version is composed *from* the adopted thesis (and each Strand's served claim), and the candidate states what the translation loses: the original claim must be recoverable from the plain version, and anything lost is restored or conceded by name on the candidate. 2–3 candidates through `draft_gates.gate("plain-register", …)`, gate id declared in `GATES` in pipeline order; recommendation beside the candidates per the standing rule; free text wins and the owner's own wording is the commitment.
>
> **Boundary, restated because the two blocks are adjacent:** journey incorporation's *"quoted as served — never re-expressed"* is untouched. This gate re-expresses the **thesis and Strand claims** — a different artifact with its own gate — and a plain-register Strand rendering never licenses paraphrasing a served arc where the arc itself is cited. Omissions disclosed by name; cover counted in placements; the adopted commitment crosses into drafting as a **brief disclosure** exactly as the journey register and the #1410 structure do. **It is a semantic commitment, not a sentence** — the draft is never handed a string to paste; what is fixed is the proposition a reader must be able to state after either end. Delivery: story 20.212 (file-overlap scheduled after 20.211 — both touch `scripts/draft_gates.py` and `skills/terrain/steps/brief.md`; an overlap edge, not a dependency).
