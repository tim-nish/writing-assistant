# SPEC-terrain — ratified amendments, 2026-07-30 onward

Companion to `SPEC.md` (listed in its `companions:` frontmatter): the dated,
ratified amendment blockquotes of SPEC-terrain, relocated verbatim per the
2026-07-27 amendment-history-companion decision (#829). **Subsequent
amendments append here, newest-last** — `SPEC.md` carries the pointer, never
the blocks.

Amendments dated **2026-07-24 through 2026-07-29** live in
`amendments-archive.md`, relocated verbatim on 2026-07-31 when this file
reached the 72,000-byte spec ceiling. That file is closed; nothing appends
to it.

> **Amended 2026-07-30 (triage, #933/#934)** per /triage-gh. Journey presence
> on a Strand row is **derived and marked by absence**, with the coverage
> denominator stated on every Strand-row screen. Three facts drove it. The
> flag never reached the renderer: the record-authoritative path composed a
> literal `False` on every entry while holding the shard pointer that answers
> the question, so a screen asserted that no Journey material fell under a tag
> carrying 49 paired journey records — a wrong-kind claim logged as success.
> Coverage inverted the marker's information content: the marker was designed
> against ~50% and the served manifest carries 109 journeys against 117
> lessons, so marking presence decorates nearly every row while the thin
> Strands are the actionable set the writability verdict already treats as
> such. And the retirement of the `J<n>` namespace (2026-07-28, #871) left the
> code that mints it standing — a `journey` counter and a `J` prefix branch
> reachable only on a kind the record path never emits, which is why a screen
> could be written as though `J` rows might appear. The denominator is the
> **load-bearing half**, not decoration: absence-marking is correct only while
> coverage stays high, so the denominator is what makes the next inversion
> visible on the screen rather than discovered late. Rejected: threshold-
> conditional presence marking (a magic number in the spec, and a marker that
> appears and disappears makes two screens non-comparable and every check over
> it conditional); dropping the marker entirely in favour of the writability
> verdict (smallest surface and no rot, but the owner then finds the thin rows
> by noticing the count is 49 rather than 51 and hunting — the glance signal
> is the marker's whole purpose).

> **Amended 2026-07-30 (triage, #935)** per /triage-gh. The 2026-07-28 #874
> location ruling is **narrowed to Terrain's owner-facing output**. The View
> stays in this repository, guarded by the committed ignore entry and the
> staged-artifact check; **run workspaces and debug artifacts resolve back to
> the machine state root**. Ground: the portfolio-wide class split places
> human-facing artifacts in the working repo and machine-readable
> intermediates, caches and resumable state in machine-state dirs (owner
> decision record — 2026-07-16 (artifacts live where the human works)), and
> #874 reached one clause past the deliverable. Observed cost of the wider
> form: roughly forty repo-key directories accumulated in a working tree with
> no GC, most of them `-tmp-*` leftovers from test and dogfood runs, deleted
> by hand. The split is drawn at the resolver, which already drew one — the
> draft pipeline's caches and checkpoints never moved — so a boundary
> relocates and no caller changes. #874's owed retention rule is discharged
> **by relocation rather than by GC**: growth was non-deferrable because the
> runs sat in a working tree. Two things stay undischarged and are named
> rather than assumed: the accumulation already on disk (a one-time deletion
> no code owns) and, until this lands, test runs keying a real repository.
> Rejected: keeping the location and writing the retention rule #874 owed (it
> discharges an existing obligation with a smaller spec surface, but leaves
> verbatim hub renderings and pins in a public tree defended by a guard rather
> than by absence, and contradicts the served class split); relocating the
> View too (publication risk to zero and two mechanisms deleted, but it loses
> the immediate-inspection affordance the owner stated, and a printed path is
> not a file already open in the tree).

> **Amended 2026-07-30 (triage, #936)** per /triage-gh. The composed group
> line's provenance is **declared once per surface, not once per line**. Where
> every line of a visual class is composed, the preamble's declaration
> discharges the obligation; a per-line marker is owed again when a screen
> mixes composed and quoted lines of the same visual class, and then it marks
> the **minority** class. The obligation is unchanged in force — only its
> carrier is bounded, and the no-silent-fallback rule (#850 D1) is untouched.
> Observed: the parenthetical appeared on all twenty group summary lines of a
> screen whose preamble had already declared the class, carrying zero
> information per line while costing attention on every one. The
> violation-layer rule is **satisfied, not weakened** (owner decision record —
> 2026-07-26 (carry a rule at its violation layer)): it requires the carrier
> to sit where the human acts, which the preamble does — same screen, same
> read — not one carrier per line. Rejected: keeping a per-line carrier in a
> shorter form (honours the violation-layer rule with no interpretive step and
> keeps the check unconditional, but a shorter constant is still zero bits per
> line, so it leaves the reported defect in place in a smaller font);
> inverting the polarity to mark quoted lines by their citations (the signal
> would then carry information and be verifiable, but an unmarked composed
> line is close to what the no-silent-fallback rule was written against, and
> that failure is silent rather than loud).

> **Amended 2026-07-30 (triage, #937/#939)** per /triage-gh. **Selection
> accepts a SET of Strand indexes, and the in-common claim is recomposed over
> exactly that set** at the brief gate, as a machine-composed proposal beside
> free-form override; the brief records the adopted claim, its member set,
> each member's served gloss and cite, and the pins. Single-Strand selection
> becomes the degenerate case rather than the only structured path. Observed
> divergence: an owner who had explored a tag and pointed at four co-tag
> sections (19 distinct Strands) was offered exactly two exits — free text, or
> one Strand as a spine with "the other 18 stay available as harvest material"
> — so no path composed from the selection, and the gate asked for a
> one-sentence summary in the owner's own words, which is raw-artifact
> homework. The ratified model says otherwise (owner decision record —
> 2026-07-29 (terrain draft handoff)): a claim composed over a member set is
> pinned to that set, a subset selection recomposes and re-offers it, and the
> brief records the adopted claim together with its members. **The
> no-second-proposer boundary is untouched, by its own test** — a combination
> becomes a proposal exactly when something other than the owner narrows the
> candidate set, and the owner did the narrowing here; the map still composes
> no narrative structures. Recording the member set is not bookkeeping: the
> completeness invariant follows the selected set into drafting, and with no
> members recorded, omission becomes silent — which is what that invariant was
> corrected to prevent. **The brief gate may additionally carry a coherence
> CONSULTANT (#939), bound by four rules and deliberately not by a
> procedure:** gate shape (proposals plus free-form override, nothing adopted
> silently); grounding (assessments and substitutions cite served renderings
> and group claims at the pin, never invented material); honesty (say plainly
> when a set does not cohere, disclose uncertainty rather than emitting a
> confident structure); and **no hiding** — a substitution proposal enumerates
> its candidates, because offering the best swap while discarding weaker ones
> is ranking, which falls on the far side of the boundary while merely adding
> unselected material does not. The consultant is diagnostic over an
> owner-selected set and never runs upstream of a selection. Rejected:
> shipping the selection half now and routing the substitution boundary to a
> hub conversation (the issue itself invites that, and the consultant would be
> specified against an observed failure instead of an imagined one — but the
> brief gate would ship with no coherence assessment, so an incoherent set
> freezes into a brief and the cost lands in drafting); recomposing at the
> gate while leaving the brief a plain string (much the smallest change and
> nothing downstream learns a new shape, but the completeness invariant then
> has no member set to follow and omission becomes silent).

> **Amended 2026-07-30 (triage, #938)** per /triage-gh. The owner may pull a
> **Full Report for named group ids**, rendering per group, in the order
> asked: the group's existing composed claim verbatim, then every member
> Strand's full served rendering — gloss, deterministic context line, journey
> arc — in prose. The compact all-groups form shows member ids plus a claim,
> which is enough to navigate and not enough to judge whether a grouping makes
> sense; the ratified form anticipated the report (owner decision record —
> 2026-07-29 (terrain draft handoff)). Four constraints fix what it is not: it
> **preserves** claims and never recomposes (the claim renders over the
> unchanged full member set it was composed from, so it stays true to its pin;
> recomposition belongs to subset selection, and inspection and selection stay
> different acts); it **selects nothing**; it renders from **held state**,
> never by reading the written rendering back; and it **restates the pin and
> the group definitions**, since group ids are per-screen, per-pin identifiers
> that do not survive a re-run. It **relays whole**, a stated exception to the
> size switch rather than an oversight — reading each group entire is the
> report's purpose — bounded by the owner's own pointers, covering the groups
> named and never the whole member. Rejected: extending the per-invocation
> View file (reuses a ratified artifact and has no screen-budget question, but
> answers a mid-conversation request by rewriting a file and handing over a
> path, moving the reading outside the interaction where the judgment
> happens); a relay obligation in prose with no code path (cheapest, and the
> material is already in the payload — but prose binding a model is advisory
> at the layer where it breaks, and the reported defect *was* a relay doing
> its best, flattening nineteen Strands into headline one-liners).

> **Amended 2026-07-30 (triage, #941)** per /triage-gh. **CAP-3 is relocated
> verbatim to the companion `presentation.md`**; `SPEC.md` carries a pointer
> that *names* what moved rather than deferring to a lookup, and this record
> stays the single dated history for the whole spec — one spec, one amendment
> file, including for CAP-3's own clauses. Trigger: the byte ceiling fired
> (80,902 against 72,000) after five amendments landed in one sitting on a file
> that had been 71,264 bytes — 736 bytes under the ceiling — so the next
> normative clause of any size was going to trip it. **The growth was measured
> before anything moved**, which is the ordering the standing rule requires:
> ship the ceiling, hold restructure until the ceiling produces a breakdown of
> which content classes dominate, because restructure claims the organisation
> is wrong while a ceiling only measures size (owner decision record —
> 2026-07-26 (ship the ceiling, hold restructure on its own evidence)). The
> breakdown: CAP-2 26,432 bytes (33%), CAP-3 24,587 (30%), open questions
> 13,937 (17%), CAP-4 6,149 (8%), preamble 3,044 (4%), CAP-1 2,426 (3%). Two
> capabilities were 63% of the file, and no large block of superseded prose
> existed to pointer-ify (six occurrences of historical/superseded markers
> corpus-wide in the file). **Nothing was compacted** — ratified text never is,
> and a projection may relocate text but never re-express it, so the move
> changed no clause. Blast radius verified rather than assumed: six inbound
> citations across four files, exactly one of them line-ranged
> (`spec-policy-editorial-direction/SPEC.md:50` → the preamble, unaffected),
> and **no check reads this spec's content at all**. Result: `SPEC.md` 57,560
> bytes, `presentation.md` 25,848, both under the ceiling. **Two alternatives
> rejected**, and one dismissed on arithmetic: splitting the open questions out
> as well (durable headroom at ~42 KB, but three companions for one spec is the
> larger restructure the ordering rule says to hold until measurement supports
> *how much* to move, which it does not); splitting into two peer specs at the
> assembly↔presentation seam (a peer spec states independence a companion only
> implies, and the citation cost was verified small — rejected because CAP-2
> already contains screen-level rules, so a spec boundary drawn there runs
> through a seam the existing text crosses, and every future amendment would
> face a which-file question whose wrong answer splits one contract silently);
> and relocating *only* the open questions, which leaves 5,035 bytes of
> headroom against ~9,600 bytes of amendments observed in a single sitting —
> a deferral wearing a fix's clothes. **Never available:** raising the ceiling
> or adding this file to the ratchet list. The check's own text forbids raising
> a ratchet to absorb growth, and an exemption minted for another file cannot
> be inherited unless the new member states the original justification in its
> own terms, which "five amendments landed at once" is not (owner decision
> record — 2026-07-27 (an inherited exemption signals nothing)).

> **Corrected 2026-07-30 (triage, #933)** per /triage-gh — a same-day
> correction of the #933/#934 amendment above, not a new decision. That
> amendment's first clause read *"the entry's `journey` field is **derived** —
> a paired journey record exists, i.e. the shard pointer is not null — and is
> never a literal"*, and it is **not implementable**: on the
> record-authoritative path `journey` is a **kind discriminator** ("this entry
> IS an arc rendering"), set from the served file path and consumed to split
> served renderings into the lessons and journeys lookups. Measured on the live
> corpus: deriving it from presence moves **109 of 117** lesson renderings out
> of the lessons lookup, which breaks the journey-shard enumeration (it
> iterates that lookup) and collapses the attachment count. The literal `False`
> there is correct. **Presence was never dropped in composition** — the paired
> record's pointer is set on every composed entry — so #933's mechanical claim
> is right about the symptom and wrong about the site: the gap is at the
> renderer, which never consumes it. The clause now binds **the observable and
> its source of truth**: presence is read from the paired journey *record*,
> never from a literal, and never inferred from a rendering path's
> addressability (117 lessons, 109 journey records, 109 paired, 109 pointers
> resolving — divergence 0 today, so the invariant is stated before it bites).
> Bullets two and three — absence-marking and the coverage denominator — are
> #934's decision and are **unchanged**. **The transferable half:** this spec
> names served-side and config vocabulary, and the failed clause named a
> consumer's private dict key using a word the spec already binds to a served
> record kind, so two questions collapsed into one token and a story
> implemented the wrong one faithfully. A spec clause that names an internal
> field can be wrong in a way no reader of the spec can detect and no check
> catches — **all four terrain checks passed with the misrouting change in
> place**, because none exercises the lessons/journeys split. Rejected:
> declaring a separate `has_journey` field in spec text (one carrier named
> once, and the name would document the distinction — but it re-commits the
> spec to naming internal shapes, which is the category of statement that just
> failed, and it adds redundant state a reader must arbitrate between); naming
> the shard pointer instead (smallest diff and correct today, but it conflates
> "a journey exists" with "its rendering was addressable", which is the same
> wrong-kind-claim class as the bug being fixed, silently wrong the first time
> the two diverge).

> **Amended 2026-07-30 (triage, #976/#977 — one decision, two issues) — screen 2 is COMPOSED BY THE SCRIPT end to end; the model supplies group claims and never retypes a Strand row.** The screen-2 flow asked the model to *"relay the returned `listing` as given … each Strand quoting its served rendering with its deterministic context line"* (`skills/terrain/steps/screens.md:57`), and the 2026-07-30 dogfood shows the relay is not faithful: L116 rendered in G8 as *"…is a harness gap, not a wording problem"* and in G9 as *"…is a harness gap"*, **both expanded rows**, so one was silently shortened; and L56's expanded row in G6 carried no `no-journey` mark although the screen header promised one and the compressed groups G12/G15 showed it. **Both are one defect, and neither is a code defect.** The rows are deterministic script output — the mark is added in `_strand_context_line`, which both expanded paths call — so the data was right in each case and the *relay* dropped or reworded it. What was missing is a carrier: "relay as given" is an obligation, violated by omission, with no event to gate and nothing making the absence visible, which is precisely the layer at which a rule stated in prose is enforced by whatever consideration is strongest when the moment arrives. **The remedy removes the opportunity rather than restating the instruction:** the model composes only the `in common:` claims and passes them back through the **existing** `--claims` round-trip (`screens.md:111`, whose path already *"carries them verbatim"*, `:118`), and the script emits the final screen — rows and claims together. The View and report paths are already script-composed end to end; this makes the at-or-under-budget screen-2 path match them, so a reworded headline and a dropped absence-mark both become structurally impossible rather than detectable after the owner has read the wrong line. **A bounded question the delivering story must answer rather than assume:** claim text now round-trips through a CLI argument, so quoting, embedded newlines and shell-safety are part of the contract — the View path may already have solved this, and the story checks that before inventing an encoding. **Not licensed:** permitting marked compression of an expanded row. That was the issue's own second horn and it is declined — a mark the same model must remember to add is enforced by exactly nothing that the verbatim rule was not already, so it would trade a silent violation for a differently-silent one while recording the weaker guarantee permanently. Delivery is story 20.66. **#977 was classified `story` at the batch gate and RECLASSIFIED to `spec` before any story was written**, because its criteria decide this same relay-fidelity invariant rather than a local rendering bug; the reclassification is recorded here rather than made silently.

> **Amended 2026-07-30 (triage, #979/#980 — one decision, two issues) — a compressed group GLOSSES each member on its first appearance, and a claim that cannot state a commonality SAYS SO; the proposed member cap is DECLINED on measurement.** The 2026-07-30 dogfood reports two group-level defects. The first is real and gets an obligation: compressed groups vary in whether they help, and G17 (`L21 · L22 · L70 · L77 · L83 · L95 · L117`) and G18 are bare index chains, so a reader entering there has no handle beyond the group's `in common:` line and must scroll back to recover each member's headline — while G12/G13/G15 already gloss members not yet seen. **That practice becomes a rule: every compressed group glosses each member on its FIRST appearance**, which costs nothing where the behaviour is already correct and closes the case where it is not. **The second is a premise correction.** The issue proposes a soft member cap because G10 (15 members) and G12 (13) "exceed what one in-common claim can honestly state" — but the ratified sectioning cap is **20% of PLACEMENTS** (`specs/spec-terrain/SPEC.md:254,278,284`), which for the reported 107 placements is `max(3, int(107 × 0.2)) = 21`. **Neither group was ever in breach**, and no second, tighter cap is licensed: this file already records that *"the future remedy if one is ever needed is a second navigation step, not a cap"* (the 2026-07-27 within-topic-cap decision, whose own decline states it was named in advance **so that a cap would not be invented under time pressure later** — *owner decision record — 2026-07-27 (no within-axis cap; a second navigation step)*; consulted at the pin, coverage partial, **covered** on this fork). Inventing one here would also re-introduce the ranking judgment the compact all-groups form was adopted to remove. **What the issue actually found is a COMPOSER signal, not a size signal:** G12's claim visibly trailing into an enumeration (*"…trials exercised, coverage explored, ignorance…"*) is the composer failing to find a commonality, so the honest response is disclosure — **the claim declares that it could not state a single commonality** — rather than resizing the group until the sentence reads better. Silent restructuring on a machine judgment about prose quality is the shape that turns grouping into a gate wearing navigation's clothes, and the existing cap is arithmetic for exactly that reason. **Watch trigger, this decision's own weakness as an observable:** degenerate-claim disclosures appearing on many groups at once would mean the grouping, not the composer, is wrong — at which point subdivision on that signal (the ratified second navigation step, already implemented) becomes right and this disclosure was only the instrument that showed it. Delivery is story 20.67.

> **Amended 2026-07-31 (triage, #986/#987 — one decision, two issues) — the Full Report relays UNTRUNCATED and names its journey label; the deterministic context line moves to a FOOTNOTE; the md export is DECLINED a second time.** The 2026-07-30 dogfood reports the Full Report truncating exactly the material it exists to show: every `how it changed:` line ends in `…` mid-sentence. **This was never a gap in the contract — it was a violation of it.** CAP-3 already binds *"it relays whole — a stated exception to the size switch below, not an oversight"*, while the renderer clipped every line to a fixed width (`VIEW_LINE_CHARS`), so in the one surface exempted from the size switch the journey arc — the thing screen 2 advertises 49 of 51 Strands as carrying — was the content systematically cut. Read with the same-day ruling that **UX defines correctness** (*owner decision record — 2026-07-27 (terrain cold-reader verdict)*; consulted at the pin, coverage partial, **covered** on this fork), a report the owner cannot read whole fails its purpose whether or not a clause forbade the clipping. The clause is honoured, not amended. **A legend is added** because the owner asked whether `how it changed:` shows journeys: it does, but nothing on the surface said so, while screen 2's legend defines a `J` row that never renders here — the ratified vocabulary and the rendered label disconnected on the reading surface. **The context line moves to an end-of-report footnote.** It bundles cross-group placement (which serves selection-screen navigation), the audit pin (which serves verification) and a completeness attestation with no reader action attached — three audiences, none of them the reader of one group read whole. It is **relocated, never dropped**: the pins stay reachable, so the report still restates what it rendered, and the selection screens keep the line on the row where it does serve navigation. **A premise correction the issue's second half rests on.** #987 reports the line present for every G4 member and only for L112 in G10, and argues that per-member presence with no rule is a defect either way. **Presence was never conditional.** `_strand_context_line` emits it for every Strand and only its first field varies — a Strand with no co-tags renders `in no other Topic`. G4 and G10 differ in **co-tagging**, not in row contract; the contract was already uniform, and this amendment changes where a uniform line lives rather than whether it exists. Recorded because acting on the reported shape would have "fixed" a rule that was not broken. **A latent check bug found at the same site and owed by the delivering story:** `check-terrain-report-inner.sh` asserts `body.count("(also in:") == len(strands)`, which fails on any co-tagless Strand and passes today only because every fixture Strand happens to be co-tagged — the assertion encodes the same wrong premise the issue did. **The md export is DECLINED a second time.** This file already records the rejection (*answering a mid-conversation request by rewriting a file and handing over a path moves the reading outside the interaction*), and a shipped assertion enforces it by failing on a path in the report body. #986 offers no argument against that ground; it offers a **symptom** — "the displayed result is truncated" — with the export as its remedy. The truncation has its own cause and its own fix, so the symptom is addressed at source and the export buys nothing the whole relay does not now provide. **What would reopen it, named so the next sitting inherits the reasoning instead of re-deciding it:** an owner who, having read an *untruncated* report, still cannot read it in a terminal — grounding the export in terminal limits rather than in truncation, which is evidence neither rejection has weighed. Delivery is stories 20.73 and 20.74.

> **Amended 2026-07-31 (triage, #988/#994/#995/#996/#997 — one decision, five issues) — the brief becomes a NAMED artifact with a visible lifecycle, G-ids become expanding shorthand, the gate gains an ITERATION LOOP and 2–3 CANDIDATE THESES, and a large selection may be proposed as k article-scoped groups.** The owner's verdict after the first real end-to-end run: *"It continuously displays information and requires the user to design everything from scratch in ordinary chat. That is the worst possible UX for this workflow."* Filed as a **bug** under the standing ruling that a rule-conformant surface bad for the user is an incorrect design. Five issues, one decision, because all five land at the selection → brief boundary and deciding them apart would decide the same thing several times differently. **The five are not one kind of change, and the distinction is what makes the decision safe.** #994/#996/#997 add **ergonomics** to a flow the owner already drives; #995/#988 add a **machine partition or re-reading of the owner's selection**, which is the act the second-proposer boundary polices. Both are admissible, but only for a stated reason: the boundary engages when something other than the owner **narrows** the candidate set, and at the brief gate the narrowing has already happened, by the owner, at selection. Composing several readings over an owner-selected set narrows nothing. **So the guard is not the boundary but the completeness invariant** — a **cover counted in placements** (*owner decision record — 2026-07-29 (terrain grouping and evidence model)*) — and it is checkable: a candidate thesis places every selected Strand or discloses the omission, and **the count check runs after composition**, since a composer that cannot omit in principle can still omit in fact. That check is the delivering stories' own falsifier. **#994 is consumer-side surfacing only.** That selection composes the brief is settled (*owner decision record — 2026-07-29 (terrain draft handoff)*) and is not reopened; what was missing is that the brief had no identity, no artifact and no stated lifecycle, so the owner could not tell when a brief began existing or how to return to one. The never-read-back rule does not transfer, and the difference is the point: a View is a rendering regenerated per invocation, while the brief is the owner's decision — re-opening it is the requirement, not a cache. **#996 relaxes a refusal that protected the right invariant with the wrong reach.** Selection refused group ids outright on the ground that a rendering is not an address. That ground survives exactly: a G-id may never be **recorded**, but it may be **typed** — expanding to its member L-ids at the screen that defined it, with mixed input composing by expand-then-set-arithmetic before the brief exists. Nothing downstream can distinguish the result from a selection typed member by member, which is the test. **A related recollection was checked against the record and NOT found:** a design in which the Brief screen recommends other Lessons from the same Group id. No such decision exists, and it is declined on the merits — keying a semantic act on one invocation's ephemeral presentation grouping. Sibling recommendation, if wanted, is computed from the **substrate** at recommendation time under the proposal contract; it may coincide with a group's membership but must not reference the grouping. **#997's semantics were already ratified and shipped** — a claim is pinned to its member set and recomposes when that set changes, a set change being a **gate event** rather than a refresh — so what is added is only the move: an edit-set option class in place of "go back to Screen 2", each recomposition pinned to its own set, prior compositions retained so the owner compares theses across set variants rather than remembering them. **#988 is the candidate-thesis machinery applied to a partition**, and stays deliberately separate from subdividing an oversized group on the *serving* screens: that is pre-selection presentation refinement bound by the terrain invariants, this is post-selection and bound by the proposal contract. Conflating them would put a machine partition **upstream** of the owner's selection, which is the one place the boundary does engage. **Grounding correction the delivering stories must not inherit:** #995 states that *"today's coherence-consultant pass already computes the material"* for candidate theses. It does not. The consultant computes a subject list and a complete unranked substitution pool and nothing else; the core-vs-adjacent split the owner observed is unpersisted judgment at the gate, and the consultant's rules are deliberately **not** a fixed procedure — an existing check grep-asserts that no procedure has been smuggled in. Candidate theses are therefore **new composition**, not a rendering of something already computed, and the story that builds them must not weaken that check to do it. **Observed good behavior preserved:** on five selected Strands the gate identified the stronger subset unprompted and offered narrowing as a ranked option with grounds and an overturn condition. Delivery is stories 20.75–20.79.

> **Amended 2026-07-31 (#889/#1018/#1031 — the offering gate DISCHARGED) — Journey similarity joins the OFFERED substrate set; co-tags remains the default.** The gate added 2026-07-29 held the model-judged substrate out of the offered set until one measurement run answered *do the machine-judged shared journey paths form groups the owner recognizes as one background?* **That run happened on 2026-07-31 and the owner verdicted PASS**, so this entry records a ratified conditional discharging — *"Pass → it joins the offered set"* was already the clause's own text — and not a new decision. **What was measured:** the `agents` member, 51 Strands; **10** machine-composed shared-path groups rendered in the approved compact form, each with its `in common:` line stating the shared arc; **48 of 51** Strands placed in a group and the remaining **3** accounted for explicitly in the two named residues; the permutation checked mechanically — count-in 51 = count-out 51, no drops, no duplicates, no invented ids. **The gate clause is left standing as written** rather than rewritten to match its outcome: a discharged condition is evidence about the design, and a clause edited into agreement with its own result leaves nothing to check the result against. **The verified constraints travel with the axis, unchanged** — presentation-only (sections gate nothing), all groups shown with no machine narrowing, section order a declared key and never a strength ranking, composed `in common:` lines marked machine-composed, and the `G` group-id kind declared on the surface that renders it. Two of those had no carrier on screen 2 until now: the composed listing printed `G` ids without saying what kind they are, and a judged grouping named neither its substrate nor its ordering rule on the reading surface, so both are stated there — on the judged path only, leaving the co-tag screen byte-identical, because a co-tag section's key is readable on every row and a judged one's is not. **The two residues stay DISTINCT and are never merged.** "No served journey arc" and "no shared path" answer different questions: the first Strand was never eligible for judgment, the second was judged and matched nothing, and folding them together would report a judgment that never happened. The measurement kept them apart (G11 vs G12) and the shipped fixtures exercise both. **Offering is not promoting:** a run naming no substrate still composes on co-tags, because the argument that admitted this axis is that the owner may now *choose* it, not that it groups better. **Two boundaries inherited rather than quietly closed:** the hub-wide Journey-coverage figure is **not** re-measured — the run measured 49 of 51 for one member, a different denominator, and said so — and **no ranking of groups** by strength, size or judged quality is admitted, since ranking is the far side of the second-proposer boundary and the compact all-groups form was adopted to remove exactly that judgment. **The unoffered set survives as an empty holding pen**, not deleted: the gate is a standing rule for model-judged substrates and the next one lands there until its own run passes. **What would reverse this:** groups that read as after-the-fact labels on a second member — the verdict rests on one corpus, which is the measurement's own stated reach. Delivery is story 20.82.
