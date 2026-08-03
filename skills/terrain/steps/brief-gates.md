<!-- steps/brief-gates.md — terrain brief companion (Story 20.212, #1411).
     SPLIT OUT of steps/brief.md when that file crossed the 600-line companion
     ceiling: the brief now carries FOUR gates, and the three that follow
     thesis adoption share one shape (composition inputs + frozen requirements
     + an after-composition cover) and one sequence. They are read together or
     not at all, which is what makes them a companion rather than a spill. -->

# The brief's post-adoption gates

Companion of [`brief.md`](brief.md). Read after a thesis is adopted: the three
gates that follow it, **in this order** — journey incorporation, structure,
plain register. Each is the same mechanism one selection later: the command
returns composition **inputs** and frozen `requirements` with `composed: false`
(literal), you compose, the gate carries the options through
`draft_gates.gate(...)`, and the **cover runs after composition**. None of the
three is a required slot: a gate whose material does not exist is simply not
raised, and its absence is a fact about the brief.

## Journey incorporation — after the thesis is adopted

**Added 2026-08-02** (Story 20.166; #1045, the 2026-07-31 owner ruling and hub
ratification). When the adopted brief's members carry served journey arcs, the
command returns `journey_incorporation` — the register question: **how does
that material enter this article?** It is the same mechanism as the candidate
theses, one selection later: the block carries the composition **inputs**
(`inputs.thesis` — the adopted reading — and `inputs.members`, each with its
served arc quoted at the pin), the `requirements` your options must satisfy,
and `composed: false`, which is literal.

**Compose the options from THIS brief's state — the adopted thesis, the
member set, each member's arc — at a professional article writer's
calibration. A fixed menu of registers is exactly what must not ship:** two
briefs with the same members and different theses may deserve entirely
different registers, and an enumeration written in advance would decide the
register where nothing about this article has been read. Relay
`journey_incorporation.line` so the owner sees how much of their selection
carries an arc; members without a served arc are already disclosed in
`without_journey` with the reason.

**The ratified requirements bind every option and you may not trade them
against each other:**

1. **Every option places every selected member's journey material or
   discloses the omission by name**, with its reason. Completeness is a
   **cover counted in placements**, and the count runs after composition.
2. **Every placement cites the member's served arc rendering at this pin.**
   The arc is quoted as served — never re-expressed, never synthesised from a
   headline.
3. **Every register offered keeps the arc shape** — before-position, what
   broke, after-position — and **never collapses to rule-statement register**.
   That is the hub's served-position constraint, applied with more force here:
   an article is where a flattened arc would be read as a rule.
4. **Options are enumerated, never ranked-and-trimmed, and free text wins** —
   the owner's own incorporation direction becomes the recorded disclosure,
   and every option is discarded when they write one.

**PUT THE OPTIONS THROUGH THE CARRIER**, exactly as the thesis candidates go:

```
draft_gates.gate("journey-incorporation", where=…, why=…, choices=[…], ws=<run ws>)
```

The gate id is declared in `draft_gates.GATES`; presenting the options as a
prose table is the defect the carrier exists to remove. Offer a
recommendation beside the options per the standing rule — naming the axes it
assessed on and what would overturn it — and nothing is trimmed or hidden for
ranking lower.

**Then run the count — not optional, and AFTER composition**, the same `cover`
command over `{"kind": "journey-incorporation", "over": [...], "pin": ...,
"options": [{"incorporation", "places", "omits": [{"index", "why"}],
"grounds": [{"index", "cite"}]}]}` — the shape the block hands you in
`journey_incorporation.answer`. Each ground cites the member's **arc** cite
(`members[].journey.arc_cite`), not its index-line cite. A refusal returns the
**whole** proposal to you, never one option while the rest go on.

To record the owner's choice, pass it back as `journey_incorporation` in the
answer **with `--incorporation <the composed options file>`** — the same
#1079 rule as thesis adoption: the rejected options are the provenance of the
choice.

**A disclosure riding the brief, never a required slot.** A brief whose
members carry no served arc simply does not raise this gate — the block is
absent, nothing nags, and its absence is a fact about the brief. The adopted
register crosses into drafting as a disclosure on the brief artifact, the way
the members' gaps do: **direction at the brief; placement belongs to the
outline; concrete design belongs to realization.** Nothing here reaches into
the fill's own instructions, and the fill does not branch on this block
existing.

## Structure — composed for THIS article, one selection later

**Added 2026-08-03** (Story 20.211; #1410, the owner ruling *(owner decision
record — 2026-08-03 (article structure proposed, not templated))*). Once a
thesis is adopted the command returns `structure_candidates` with
`composed: false`, and that is literal: it carries the composition **inputs**
(the adopted thesis, the member set with served glosses and arcs, and the
adopted journey register when one exists), the `requirements`, and the count
that verifies what comes back. **There is no framework stock to select from
— that is the ruling, not a preference.** Compose 2–3 candidates from THIS
brief's state, each stated **operationally** — ordered moves with a one-line
rationale naming the material that motivates it (*"open with the failure
case: J2 is the strongest concrete anchor for the thesis"*) — never a
framework name as the candidate. A journey-shaped candidate
(failure-case-first, reversal-led) is admissible and **names the served arc
that licenses it**; it must agree with the adopted register, which rides the
inputs so you cannot compose blind to it. A candidate *may* cite a framework
as vocabulary ("close to ki-shō-ten-ketsu") when that helps the owner
evaluate it; whatever remains of `skills/draft-article/frameworks/` after
#911's window is reference prose, and no path enumerates it for selection.

**PUT THE CANDIDATES THROUGH THE CARRIER**, exactly as the thesis and
register go:

```
draft_gates.gate("structure", where=…, why=…, choices=[…], ws=<run ws>)
```

The standing requirements bind unchanged: every candidate over the same
complete set; every candidate places every selected Strand or discloses the
omission by name; placements cite served renderings at the pin; enumerated,
never ranked-and-trimmed; a recommendation beside the candidates naming its
axes and overturn condition; free text wins. **Then run the count — after
composition, not optional** — the same `cover` command over
`{"kind": "structure-candidates", …}` (the shape the block hands you in
`structure_candidates.answer`); it additionally refuses a bare framework name
where ordered moves belong.

To record the owner's choice, pass it back as `structure` in the answer
**with `--structures <the composed candidates file>`** (the #1079 rule a
third time) **and `structure_framework_matched`** — the matched framework's
name, or the literal `bespoke` when nothing was matched. The explicit
`bespoke` is #911's instrument: the composer ignoring the reference
frameworks must be a measurement, never a silence, and the brief refuses an
adoption that omits the value. **The adopted structure crosses into drafting
as a disclosure** — direction at the brief; placement belongs to the outline;
concrete design belongs to realization — and a brief carrying one means the
stage-3 `narrative-structure` gate is **not re-raised**: a decided owner
question is asked exactly once.

## Plain register — the commitment both article ends realize

**Added 2026-08-03** (Story 20.212; #1411, the same owner ruling). Last in the
brief's sequence, the command returns `plain_register` with `composed: false`:
a **child-level translation of the adopted thesis**, plus a **child-level
rendering per selected Strand**, because both ends of the article realize it
and the close composes the simplified renderings into its restatement
(#1412). It is decided here rather than at the fill for exactly that reason.

**Compose under the operational constraints — never "write for a child".**
Asking cold for a thesis an elementary-school student can understand reliably
produces condescension, lossy stock metaphors, or a register that does not
match the article. The `requirements` therefore define plain register as
**checkable properties**: no term of art without an in-sentence explanation,
one relation per sentence, a concrete subject doing something. The article's
audience is unchanged; the register is the constraint.

**Every candidate carries its round-trip concession.** Compose the plain
version *from* the adopted thesis and each Strand's served claim, and state
what the translation loses — the original claim must be recoverable from the
plain version, and anything lost is restored or **conceded by name**. State it
even when nothing is lost, and say so: an unstated concession asserts
losslessness without being judged on it.

```
draft_gates.gate("plain-register", where=…, why=…, choices=[…], ws=<run ws>)
```

**Boundary with journey incorporation, and it is load-bearing:** that gate's
arcs are *quoted as served — never re-expressed*. This gate re-expresses the
**thesis and the Strands' claims** — a different artifact with its own gate —
and a plain-register rendering never licenses paraphrasing a served arc where
the arc itself is cited.

Run the same `cover` over `{"kind": "plain-register", …}` after composition;
it additionally refuses a candidate with no concession and a rendering with no
served-claim cite. To record the choice, pass the chosen candidate's plain
thesis back as `plain_register` **with `--register <the candidates file>`**.
**The owner's own wording IS the commitment, verbatim** — and it is a
*commitment, not a sentence*: the draft is never handed a string to paste.
