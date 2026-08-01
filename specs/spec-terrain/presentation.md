# SPEC-terrain — CAP-3, the presentation surface

Companion to `SPEC.md` (listed in its `companions:` frontmatter): **CAP-3 —
presentation and the combination move**, relocated **verbatim** from `SPEC.md`
on 2026-07-30 (#941) when the canonical file passed its byte ceiling. The
relocation moved text and changed no clause; a projection can relocate text
but never re-express it, so nothing here was compacted, reworded or
re-ordered.

**What lives here:** the screens, in-invocation navigation over held state,
set selection and claim recomposition, the coherence consultant, the Full
Report, the size switch, the View file, and the indexed hand-off — everything
governing how the terrain is *presented* and how a selection becomes a brief.
**What stays in `SPEC.md`:** CAP-1 (derived view, never stored state), CAP-2
(map content — the axes and what a screen's rows contain), CAP-4 (bounded
assembly), the open questions, and the canonical preamble.

**The amendment history is not split.** Every ratified amendment for this
spec — including those amending the clauses below — stays in the single
`amendments.md` companion, newest-last. Look there for the dated record of any
clause on this page, and append new amendments there rather than here.

- **CAP-3 (presentation and the combination move)**
  - **intent:** The map is presented **in-conversation** under the owner-facing
    proposal contract — one screen, the map plus machine-proposed candidate
    directions (including at least one cross-topic combination when the
    evidence supports one) plus a free-form response where the owner names
    their own direction or combination axis. The outcome is a **brief**: the
    owner's chosen direction, in the owner's words (machine-proposed text the
    owner accepts becomes owner-adopted wording), handed to the existing
    stage-0 `--brief` path. **No second proposer:** the map never composes
    narrative structures — structure candidates remain the shipped proposer's
    job downstream.
  - **presentation is two screens (amended 2026-07-27, #803).** The map is
    presented as **Screen 1** (the deterministic axis listing — served gloss
    tags with element counts) and **Screen 2** (the selected member's complete,
    sectioned material). Free-form is offered on both, and the outcome is the
    same brief handed to the same stage-0 `--brief` path. Navigation replaces
    filtering: no LLM decides what appears on Screen 1, and nothing is withheld
    on Screen 2.
  - **selection is a SET, and the claim is recomposed over it (amended
    2026-07-30, #937).** The exits offered after exploration were free text or
    **one** Strand as a spine, so an owner who had pointed at nineteen Strands
    had no path that composed from them — raw-artifact homework at a gate, and
    a divergence from the ratified brief-composition model (owner decision
    record — 2026-07-29 (terrain draft handoff)). So:
    - **selection accepts a set of Strand indexes**, however the owner
      assembled it — individual picks across screens, or everything they
      pointed at. Sections remain **presentation-only**: the set is per-Strand
      multi-select, never group-select, because a selectable group would make
      grouping a gate;
    - **on a set, the in-common claim is recomposed over exactly that set**
      and presented at the brief gate as a machine-composed proposal beside
      free-form override. **Free text always wins**, and machine wording
      becomes the brief only by the owner adopting it;
    - **the brief records the adopted claim, the member set it was composed
      from, each member's served gloss and cite, and the pins** (the terrain
      invocation and the hub commit). Recording the members is not
      bookkeeping: the completeness invariant follows the selected set into
      drafting — every selected Strand placed or its omission disclosed — and
      with no member set recorded, omission becomes silent;
    - **single-Strand selection remains available as the degenerate case** (a
      set of one). It stops being the only structured path.
    **This does not touch the no-second-proposer boundary, by the boundary's
    own test:** a combination becomes a proposal exactly when something other
    than the owner **narrows** the candidate set — the test being whether what
    reached the owner is smaller than what exists, not whether a machine
    computed something. Recomposition over an owner-selected set narrows
    nothing, so it is navigation, and the map still composes **no narrative
    structures**.
  - **the brief gate may carry a coherence CONSULTANT, bound by rules rather
    than by a procedure (added 2026-07-30, #939).** On a submitted set, the
    interaction may assess whether the set can support a single article
    thesis, say what structures the material could carry, and propose
    substitutions grounded in the terrain's own material. What is specified is
    deliberately **not** a deterministic mechanism — the failure avoided is a
    narrow procedure reporting success because it satisfied its own steps
    while missing what the owner asked for. Coherence is a judgment task;
    four rules bound it:
    - **gate shape** — proposals plus free-form override, the owner decides,
      nothing is adopted silently;
    - **grounding** — every assessment and every substitution proposal cites
      served renderings and group claims **at the pin**, never invented
      material;
    - **honesty** — when the set does not cohere, say so plainly rather than
      proceeding; when the consultant is unsure, disclose the uncertainty
      rather than emitting a confident structure;
    - **no hiding** — a substitution proposal **enumerates** its candidates.
      Offering the best swap while discarding weaker ones is ranking, which
      falls on the far side of the second-proposer boundary; adding material
      the owner did not point at is admissible, silently omitting the rest is
      not. This is the clause that keeps the consultant consultative.
    **The consultant is a diagnostic layer over an owner-selected set, not a
    scope originator** — the owner having already selected is the discharging
    condition for the second-proposer bar, and the consultant never runs
    upstream of a selection.
  - **the brief is a NAMED artifact with a visible lifecycle (added
    2026-07-31, #994).** Selection at the screen composes the brief — that
    boundary property is settled and is not reopened here (owner decision
    record — 2026-07-29 (terrain draft handoff)). What is added is
    consumer-side surfacing, which was missing entirely: the brief arrived as
    a chat continuation, so the owner could not tell when a brief began
    existing, where it lived, or how to return to one.
    - the gate carries a **named step identity**, so the owner can refer to
      the act that produced the brief;
    - the composed brief is **written to a durable artifact** the owner can
      inspect and re-open, under the run workspace resolved through the
      storage seam — never composed into a host working tree;
    - the lifecycle is **stated on the surface**: composed → inspected →
      adopted, with the current state legible at the gate.
    Format, artifact path and the step's name are this consumer's to choose;
    the hub ratified the boundary property only. **The never-read-back rule
    does not bind here, and the difference is the point:** a View is a
    rendering regenerated per invocation, while the brief is the owner's
    decision — re-opening it is the requirement, not a cache.
  - **what the brief CARRIES, and what it never carries (added 2026-07-31,
    #1077/#1078/#1079/#1080).** The clause above settled that the brief is a
    named artifact; its *content* stayed undocumented, and an undocumented
    crossing artifact accretes — a five-member brief measured 41 KB across 21
    top-level keys, none of it decided. Choosing the field set is this
    consumer's to do (the line above, and the hub ratifies the boundary
    property only), so it is done here rather than left implicit.
    - **CARRIES:** the owner's selected **member set** with its indexes; each
      member's **served material** (gloss, journey arc, cite) as relocated
      text; the **pins** (terrain invocation, hub commit, and the JUDGE — #1090 below); the **harvest
      scope** — the union of the members' `projects:`, per
      `SPEC-article-draft-pipeline` amendments 2026-07-29 (#896) and the owner
      decision record — 2026-07-29 (terrain draft handoff), the brief being
      the only artifact that crosses into drafting and so the one place scope
      is stated without re-deriving it; the **thesis state**, including the
      candidates that were **offered** and the recommendation with its
      declared axes and overturning conditions; the **adopted claim** with the
      member set it was composed over; and the owner's **free text**.
    - **NEVER CARRIES, named because each was observed in one artifact:**
      screen sentences (a rendered UI line stored as data), process
      self-documentation (the step's own requirements, its compliance
      self-assertion, the rationale for a design rule), fill-in templates
      sitting where a consumer reads values, and map-internal working state
      (`element_kind`, `consumed`, `depth`, `usability`, internal topic
      vocabulary). **The reason is the boundary property itself:** drafting
      must not learn Terrain's rendering, invocation or lifetime, and every
      embedded screen line couples it to exactly those — while being a second
      copy that drifts, which one already had.
    - **ONE FACT ONCE.** No key restates another. A pinned decision artifact
      whose facts appear twice invites the copies to disagree, and the
      singular/plural pair observed (`candidate` beside `members`,`gap` beside
      `gaps`) did worse: it left the true record ambiguous, because both names
      read as "the selection" and one described a single member.
    - **PROVENANCE IS SCOPED TO WHAT IT DESCRIBES,** and the **owner's slot
      holds owner text or nothing**. `owner-authored` may not attest a
      machine-composed string, and the free-text field is `null` when the
      owner said nothing — never machine prose. Recording absence as absence
      is what keeps the field first-class: a structured widening is the moment
      a free-text field quietly becomes optional (owner decision record —
      2026-07-29 (terrain draft handoff)), and filling the owner's slot with
      composer commentary inverts it, since a reader can then no longer tell
      owner speech from machine speech in the one field reserved for it.
    - **AN ADOPTED THESIS CARRIES WHAT IT WAS CHOSEN FROM.** The
      composed-elsewhere flow is unchanged and correct — the command emits
      composition *inputs* and the agent composes — but the artifact may not
      reach `adopted` while the candidates it adopted from live only in a
      sibling file nothing points at. Adoption without recorded provenance is
      the existence-vs-record gap the artifact's own read-back stance assumes
      away.
    **This list is amendable and expected to be amended** — the thesis model
    is days old. The contract is the *closure*, not permanence: a field is
    added by amending this clause, which is exactly the visibility whose
    absence let the artifact grow by accretion.
  - **a per-invocation judged surface carries a JUDGE PIN (added 2026-07-31,
    #1090).** Every pin in this architecture records *what was judged* and
    *what it was judged against* — and none recorded *what judged it*. On
    surfaces regenerated fresh every invocation by design, that makes judge
    version drift **indistinguishable from ordinary nondeterminism by
    construction**: the two cases produce identical records. Terrain is the
    primary site precisely because never-read-back is its design, so
    "recomputed fresh" silently becomes "recomputed by a different judge" the
    day the serving model changes.
    - **What is pinned:** the model-judged surfaces — composed `in common:`
      claims, thesis candidates and any recommendation, groupings (the
      journey-similarity substrate and the subgroup layer), consultant
      assessments, and the brief.
    - **What is NOT pinned:** ratified hub artifacts. A ratified `gloss:` is
      frozen by write-once plus the human approval — whatever model proposed
      it, the **owner** ratified it. Pinning there would record a
      consequence-free fact and invite the false inference that a ratified
      line is contingent on its proposing judge.
    - **The judge is DECLARED, never introspected.** The composing scripts are
      deterministic Python and cannot know which model served the judgment;
      only the agent holds that fact, so it is supplied at the boundary that
      knows it. This is declare-authority-never-infer-it at its own site: a
      value the code could only guess at is passed in or stated absent.
    - **Absence is recorded AS absence**, in the three-valued shape this spec
      already uses for a served arc — never a missing key, and never a guess.
      A pin that quietly omits the judge is indistinguishable from one taken
      before the field existed.
    **The vocabulary is the hub's and is not restated here** (owner decision
    record — 2026-07-31 (judge provenance)); this is the consumer's emitting
    half. **The companion is named because a pin alone does not close the
    loop:** the hub ratified a migration tripwire — on a change of serving
    judge, re-run one held measurement specimen and put the diff before the
    owner. The pin makes a judge change *observable*; the tripwire makes it
    *consequential*, and either alone leaves the loop open.
    **The nullable-field risk is real and is the stated reopen trigger:** if
    callers routinely omit the judge, the field measures nothing and the
    honest response is to make it required, refusing composition of a judged
    surface without it.
  - **G-ids are owner-facing SHORTHAND that expands at the screen; L-ids are
    the addresses (added 2026-07-31, #996).** Selection previously refused
    group ids outright. The refusal protected the right invariant with the
    wrong reach: a rendering is not an address (owner decision record —
    2026-07-29 (terrain draft handoff)), so a **G-id may never be recorded**,
    but it may be **typed**.
    - a G-id **expands to its member L-ids at the screen that defined it**,
      and from that moment only the members exist;
    - mixed input composes by **expand-then-set-arithmetic** — `G4 + L26,
      minus L48` — resolved in full **before the brief exists**;
    - the composed brief records **the member set and its pins, never a
      G-id**. This is what keeps the rendering-not-address rule intact while
      giving the owner the ergonomics the refusal cost them.
    **Sections stay presentation-only and this does not make grouping a
    gate:** expansion is a typing convenience over ids the owner read on a
    screen, and the resulting selection is per-Strand, identical to one typed
    member by member. Nothing downstream can tell the two apart — which is the
    test.
    **No recommendation is ever keyed on a G-id.** Proposing "other Lessons
    from the same group" would make a semantic act depend on one invocation's
    ephemeral presentation grouping. Where sibling recommendation is wanted, it
    is computed from the **substrate** (co-tags, similarity) at recommendation
    time under the proposal contract; it may coincide with a group's
    membership, but it must not reference the grouping.
  - **the gate carries an ITERATION LOOP over the member set (added
    2026-07-31, #997).** The semantics were already ratified and shipped — a
    claim is pinned to the member set it was composed over and **recomposes**
    when that set changes, a set change being a gate event rather than a
    refresh (owner decision record — 2026-07-29 (terrain draft handoff)). What
    was missing was the move: the gate offered adopt, narrow, or "go back to
    Screen 2 and pick differently", so the owner developing a thesis by trying
    members had to leave the gate and lose the composition.
    - the gate offers an **edit-set option class** — `+Lxx −Lyy → recompose` —
      in place of restarting selection;
    - **each recomposition is pinned to its own member set**, exactly as any
      other composition is;
    - **prior compositions are retained and remain visible** within the
      sitting, so the owner compares theses across set variants rather than
      remembering them.
    Retention is not a cache and does not breach the never-read-back rule: it
    is the comparison the loop exists to enable, held for the sitting.
  - **the gate proposes 2–3 CANDIDATE THESES over the selected set, not one
    (added 2026-07-31, #995).** One thesis was composed per selection, so
    every upstream step was free-form reading and free-form typing and the
    owner designed the article from scratch in chat. Filed as a **bug** under
    the standing ruling that a rule-conformant surface bad for the user is an
    incorrect design (owner decision record — 2026-07-27 (terrain cold-reader
    verdict)), and the intended shape is **article design as a sequence of
    selections**: a recognizable combination proposed, one thesis chosen from
    candidates, then a structure, and onward.
    - candidates are composed over the **same complete selected set** — they
      are alternative *readings* of one set, never a narrowing of it;
    - each candidate is **pinned to the set it was composed over** and carries
      its own grounds;
    - **free text remains a first-class exit**, as at every step.
    **This is where the completeness invariant bites, and it is checkable:**
    completeness is a **cover counted in placements** (owner decision record —
    2026-07-29 (terrain grouping and evidence model)), so a candidate thesis
    places every selected Strand **or discloses the omission** — and the count
    check runs **after** composition, since a composer that cannot omit in
    principle can still omit in fact.
    **The no-second-proposer boundary is not crossed, by its own test:** the
    narrowing already happened, by the owner, at selection. Composing several
    readings over an owner-selected set narrows nothing. The boundary engages
    when what reaches the owner is smaller than what exists — so the failure
    mode to guard is a candidate set that quietly drops a selected Strand,
    which is precisely what the placement count catches.
  - **a large selection may be proposed as k article-scoped groups (added
    2026-07-31, #988).** Reviewing fifteen Strands as one undifferentiated set
    was harder than expected, and such a set is often really *k* coherent
    theses — k candidate briefs, each pinned to its own member subset. This is
    the candidate-thesis machinery above applied to a **partition** rather than
    to one set, and it lives at the selection → brief boundary.
    - it runs under the **proposal contract** — approve / modify / decline —
      and is **never a silent restructure**;
    - **it must not filter**: every selected Strand lands in some proposed
      group, the cover discipline transferring intact, with the owner free to
      drop members **explicitly**;
    - a multi-brief outcome feeds the **drafting backlog**, not k simultaneous
      publishes.
    **This is a different capability from subdividing an oversized group on
    the serving screens, and the two stay separate.** Pre-selection
    subdivision is presentation refinement bound by the terrain invariants;
    this is post-selection and bound by the proposal contract. Conflating them
    would put a machine partition upstream of the owner's selection, which is
    the one place the second-proposer boundary does engage.
  - **navigation is in-invocation, over held state (added 2026-07-29,
    #887).** Screen 2's substrates are only usable if the owner can move
    between them — tag → co-tags → Journey similarity, and *back* when a
    grouping turns out to be a dead end. Two constraints make this
    structural rather than cosmetic: the surface has no back button, and a
    member holding ~50 Strands can neither be reprinted into the
    conversation per view nor live only in a file, which would make it
    uninspectable at the moment of selection. So:
    - **one invocation = one corpus load.** Every deterministic substrate
      join is computed once at the start; similarity is computed lazily on
      first use of the view that needs it, then **held for the invocation**.
      "Back" and "switch substrate" **re-present held state** — never
      recompute, never re-invoke `/terrain`. Recomputation is not merely
      slow here: a second computation of a model-judged substrate can
      return a different grouping, so re-deriving on "back" would make the
      owner's own history unstable.
    - **the screen shows summaries; the path holds the whole.** Each view
      prints compact section summaries (derived title, member ids, counts,
      per the label rule above); the complete rendering of the **current**
      view is written to a per-invocation path the owner may open.
    - **a section summary CARRIES ITS CLAIM (amended 2026-07-31, #1075).**
      The summary is a judgment surface, not a table of contents: without the
      claim its whole information content over the tag name is a member
      count, so every judgment requires opening the View and the screen stops
      doing the thing it exists for. This **reverses** the 2026-07-31 (#1038)
      position that claims do not ride along with the summaries, and it
      reverses it on that position's own ground — *unclipped composer prose
      is unbounded screen height*. Measured on the run that produced the
      finding: 20 composed claims, median 173 characters, longest 215, 3536
      total — roughly 25 lines, and most claims are already a single
      sentence. Height is bounded by group COUNT, which the 20%-of-placements
      sectioning cap already bounds; it was never bounded by prose length,
      and that is what the reversal fixes rather than ignores.
      **The bound is stated, because length has no cap and a claim is never
      clipped (#976):** a claim renders **whole** where it fits one line, and
      otherwise as **first sentence verbatim plus a pointer to the whole** —
      the same sanctioned reduction this companion states for served
      renderings (#1076), applied to composed prose for the same reason. A
      mid-sentence `…` is not an available rendering of a claim on any
      surface.
      **A summary that renders no claims does not announce them.** The
      observed defect was a screen opening with *"every `in common:` line is
      machine-composed at render time"* above twenty headings carrying none;
      whichever way a future amendment moves this clause, the announcement
      and the rendering move together.
    - **an ADOPTED SUBDIVISION is visible on the summary (added 2026-07-31,
      #1075).** Where subgroups were adopted, the summary says so — at
      minimum a per-group count (`G10 — also knowledge-architecture (15, 4
      subgroups)`). A screen that defines the `G<n>-<m>` id family and
      exhibits no member of it leaves the owner facing the parent's fifteen
      members exactly as before the mechanism shipped. This is a count, not
      composer prose, so the height argument above never applied to it.
    - **GROUP PRESENTATION'S RESIDUE, corrected (amended 2026-08-01,
      #1115/#1116; SUPERSEDES this clause's first form of the same date).**
      The first form ruled that the per-Strand annotation line is removed from
      the screen and the Full Report alike, and it was **wrong on both halves**
      — written from the finding's description without reading the composer,
      which is the one grounding discipline this repository states for itself.
      It is corrected here rather than quietly edited, because a clause that
      contradicted a shipped constraint was ratified and must not simply
      vanish. **What it got wrong.** (1) The Full Report **already** relocates
      that line: `_report_footnotes` collects it verbatim at the end of the
      report (Story 20.74, #987, 2026-07-31), which the composer names as *"a
      CAP-3 constraint this story must not regress"* — so specifying the
      relocation again was specifying the status quo, and specifying its
      *removal* would have regressed it. (2) The **screen keeps the line by
      design**: there *"placement is navigation"*, and two later amendments
      hang absence markers on it that have **no other carrier** — the
      `no-journey` mark (#933/#934) and `SUBSTITUTED SOURCE` (#873). Removing
      it would have silently deleted two disclosures, and three shipped checks
      say so. **What is actually left, and is this clause's whole content:**
      the report's footnote block carries **one line per Strand each repeating
      the identical hub pin** — measured at 110 on the 2026-08-01 run, where
      the View is served at one hub commit by construction. So the **shared pin
      is stated once**, in the header where it already appears, and a footnote
      line carries **Strand index → `LESSONS.md:<line>`** and no pin; a
      per-Strand pin returns only if a View can ever be served at mixed pins,
      which it cannot today. The **`also in:` co-tag list** is dropped from the
      footnote where it merely restates the parent group's axis, and kept where
      it names tags beyond it. Nothing moves surface, nothing is removed from
      the screen, and the three fields' audiences are unchanged.
    - **THE DISPLAY VIEW IS SELF-SUFFICIENT (amended 2026-08-01, #1115).**
      Unaffected by the correction above, which touches only #1116's half.
      Screen 2's instruction block — *"The complete rendering —"* through
      *"Selection is always by Strand index."* — is stated **once, in the
      View**, never on the screen: reference material standing between the
      owner and the groups inverts *the summary is a judgment surface, not a
      table of contents* above. Group headings **carry their Strand indexes**
      (`## G3 — also architecture + method — 2 Strands: L1, L2`; exact format
      is the composer's), and **SubGroups render under their parent** with id
      and claim line, extending the count-only disclosure of the clause above.
      Rendering only — the no-second-proposer boundary and the completeness
      invariant are untouched.
    - **this is the CAP-3 supersession's own shape, not an exception to
      it.** That ruling admits a file as *"a rendering of one invocation
      addressed by path — never a named entity … regenerate per invocation,
      never read back (grep-assertable), no identity the rest of the system
      can refer to"*. In-invocation memory is fine because it is not
      storage; a **cross-invocation view cache is forbidden**, and so is
      reading the written rendering back as an input.
    - **every screen carries the standing exits:** switch substrate, back
      to the member list, free-form direction, stop. An exit missing from
      one screen is the dead end this clause exists to prevent.
    - **the owner may pull a FULL REPORT for named group ids (added
      2026-07-30, #938).** The compact all-groups form shows member ids plus a
      composed claim — enough to navigate, not enough to judge whether a
      grouping makes sense, which needs the groups read whole and which the
      ratified form anticipated (owner decision record — 2026-07-29 (terrain
      draft handoff)). The report renders, **per group, in the order asked**:
      - the group's **existing** composed claim, verbatim as the screen showed
        it, and
      - every member Strand's **full served rendering** — its gloss and its
        journey arc — in prose, **untruncated** (amended 2026-07-31, #986), and
      - a **legend naming the journey label** (amended 2026-07-31, #986): the
        rendered `how it changed:` line is the **Journey**, stated on the
        surface rather than left to be inferred. Screen 2's legend defines a
        `J` row that never renders here, so the ratified vocabulary and the
        rendered label were disconnected on the one surface whose purpose is
        reading.
      **Untruncated is not a new promise — it is the whole-relay clause below,
      which the renderer was violating.** Every line was clipped to a fixed
      width, so journey arcs ended in `…` mid-sentence: in the one surface
      contracted to relay whole, the journey material was the content
      systematically cut. Read with the same-day ruling that **UX defines
      correctness** (owner decision record — 2026-07-27 (terrain cold-reader
      verdict)), a report the owner cannot read whole fails its purpose whether
      or not a clause forbade the clipping.
      The **deterministic context line moves out of the row** to a **footnote
      block at the end of the report** (amended 2026-07-31, #987). It bundles
      three things with three different audiences — cross-group placement,
      which serves *selection-screen navigation*; the audit pin, which serves
      *verification*; and a completeness attestation with no reader action —
      and on a surface whose job is reading one group whole, all three are
      noise between the reader and the material. **The information is
      relocated, never dropped:** the pins stay reachable in the footnote, so
      the report still restates what it rendered, and the selection screens
      keep the line on the row where it does serve navigation.
      Recorded because the issue reported it as a defect and it is not one:
      the line's **presence was never conditional** — it renders for every
      Strand, and only its first field varies (`in no other Topic` when a
      Strand carries no co-tags). What looked like per-member inconsistency was
      per-member **co-tagging**. The row contract was already uniform; this
      amendment changes where a uniform line lives, not whether it exists.
      Four constraints fix what it is not:
      - **it preserves claims; it never recomposes.** The claim renders over
        the unchanged, full member set it was composed from, so it stays true
        to its pin and nothing is owed. Recomposition happens only over an
        owner-selected **subset** — the selection operation above; inspection
        and selection are different acts and stay different;
      - **it selects nothing.** A group id is a **display** kind carrying no
        selection authority, and this report is why that kind is addressable;
      - **it renders from held state**, never by reading the written rendering
        back — the never-read-back rule above binds it as it binds every view;
      - **it restates the pin and the group definitions it rendered**, since
        group ids are per-screen, per-pin identifiers that do not survive a
        re-run.
      **It relays whole — a stated exception to the size switch below, not an
      oversight**, since reading each group entire is the report's purpose;
      bounded by the owner's own pointers, covering the groups named and never
      the whole member.
      **It writes no file, and the md-export request is DECLINED a second time
      (2026-07-31, #986).** The ground of the original rejection is unchanged:
      answering a mid-conversation request by rewriting a file and handing over
      a path moves the reading outside the interaction. What #986 added was not
      an argument against that ground but a *symptom* — "the displayed result
      is truncated" — and the export was proposed as the remedy for it. The
      truncation has its own cause and its own fix above, so the symptom is
      addressed at its source and the export buys nothing the whole relay does
      not now provide. Recorded rather than left silent so the next sitting
      inherits the reasoning instead of re-deciding it. **What would reopen
      it:** an owner who, having read an *untruncated* report, still cannot
      read it in a terminal — that would ground the export in terminal limits
      rather than in truncation, which is evidence neither rejection has
      weighed.
  - **size switch (amended 2026-07-23; re-based per axis member 2026-07-27,
    #803).** One screen does not scale: past a **screen budget** (~7
    candidates) a large terrain collapses into a handful of options and the map
    stops showing what it exists to show. **The budget is now measured over one
    axis member's Screen 2, not over the whole terrain** — two-screen
    navigation shrinks the overload condition without removing it, because a
    single tag can still hold many elements. The branches below are otherwise
    unchanged, and the #802 scoping of what the View contains stands.
    - **At or under the budget:** the flow above, unchanged. This branch is
      the shipped behaviour and must not regress.
    - **Above the budget:** the screen becomes a short **summary** plus the
      path of a **View file** the owner opens, and selection happens by
      **index** rather than by matching a proposed direction string.
    - **The above-budget branch proposes no less than the small one (amended
      2026-07-23, #632).** The size switch changes *where* the terrain is
      presented, never *whether* the map proposes. So the View **leads with
      candidate directions** — the same derived directions and cross-topic
      combinations CAP-3's intent declares, which the large branch already
      derives unbounded (every subtopic a candidate, the strongest combination
      per distinct axis) — before any terrain detail. A branch that shows the
      terrain and hides the directions inverts the switch's purpose, and it
      would put the owner in front of a raw machine artifact to answer from,
      which the human-gate presentation contract forbids. The directions are
      the ones already derived: the View **reuses** them and derives nothing
      of its own, so the no-second-proposer boundary is untouched — directions
      name what to cover and along which axis, never narrative structure.
  - **the View file.** A *rendering* of one invocation, at the same status as
    `--emit-debug`: written to a fixed path, fully regenerated on every
    invocation, and **never read back as an input** — grep-assertable, like
    the existing derived-never-stored check. It carries, in this order: the
    **candidate directions** above (with the subtopic indexes each names), a
    compact **one-line-per-subtopic summary**, and only then per-subtopic
    detail — stable ID, topic, depth glance, an **evidence summary**,
    lesson-seed names, and consumed marks — enough to distinguish 20+
    directions and to answer CAP-2's "why this depth?" from the same counts.
    Deleting it loses nothing.
  - **the View is a human surface, so it is budgeted (amended 2026-07-23,
    #633/#634).** The View is written for the owner to read, and the
    machine-readable form of everything on it already exists in the run's
    `map.json`. Duplicating that form into the human artifact is what turns
    the View into a log file, so:
    - **Evidence renders as a summary:** the count of distinct pointers, plus
      the pointers **aggregated per source file** (`path ×N`) and capped at a
      declared constant, with the remainder disclosed as a count — never
      silently truncated. Line-granular pointers are machine provenance: the
      full enumeration, with line numbers and per-line shas, stays in
      `map.json`; the View header already carries the pin, which is what
      reproducibility needs.
    - **Depth renders as the level plus the counts it was derived from** —
      "full article: 24 evidence pointer(s), 3 unconsumed lesson(s), 2 live
      item(s)" — because CAP-2's success clause promises exactly that the
      owner can ask "why this depth?" and be answered from those counts. What
      does **not** reach the surface is the **unmet-threshold predicate**
      ("the next level needs `evidence_pointers` 24 < 25"): that is the
      estimator's promotion rule, meaningful to the estimator and not to an
      owner choosing what to write. It stays in `map.json`, where the depth
      harness asserts it — so this is a rendering rule, and the estimate's
      explainability as recorded is unchanged.
    - **Every COMPOSED View line carries a display budget** (scoped
      2026-07-31, #1076), and each per-subtopic block a line cap, the same
      convention the screen payload's fields already follow: a list renders
      one item per line, clipped, capped, with an explicit `+N more`
      remainder. A fallback or placeholder state is named to the owner as
      **prose that states the remedy**, never as a bare internal enum value in
      a headline position.
    - **A SERVED RENDERING is exempt from that budget and renders whole**
      (added 2026-07-31, #1076) — the journey arc and the group claim. The
      budget was written for lines the View *composes*, where a shorter
      authored wording is always available; a served rendering has no shorter
      form, because it is **relocatable and never re-expressible**. The only
      sanctioned reduction of one is **first sentence verbatim plus a pointer
      to the whole**, the tier-1 index's own rule; a mid-text `…` is a third
      category the contract does not have, and it reliably keeps the belief
      and drops the break — the differentiating half of an arc whose shape is
      belief → break → new position.
      **This resolves a contradiction inside this spec rather than adding a
      promise.** The clause above holds that *the screen shows summaries; the
      path holds the whole*, while the line budget clipped the material the
      path exists to hold: measured on the 2026-07-31 run, 103 of 107 rendered
      arcs ended mid-sentence in a 64 KB file. Read with **UX defines
      correctness** (owner decision record — 2026-07-27 (terrain cold-reader
      verdict)), a surface contracted to hold the whole and unable to show it
      fails its purpose whether or not a clause forbade the clipping — the
      identical reasoning that unclipped the Full Report (#986, above), now
      applied to the surface that clause pointed at.
      **The exemption is scoped to the View FILE and does not touch the
      selection screens.** The size switch governs those, and the same row
      renderer feeds both, so a change made at the renderer rather than at the
      surface would widen this decision into screens it did not decide.
  - **where the View lives (amended 2026-07-23, #611).** "A fixed path" is
    **the `output.drafts` destination repository**, at a resolver-owned,
    host-qualified path — not a per-run workspace directory. The View is
    written for the owner to *open and read*, and a human-facing artifact
    belongs in the repository the human works in, while machine
    intermediates, caches and resumable state stay in machine-state
    directories. A per-run path is not a fixed path: it moves every
    invocation, so nothing the owner opened during a sitting can be reopened
    later.
    - It joins the destination repo's write surface as the **second
      regenerated NON-GATING view**, beside `INDEX.md` — the same class, on
      the same terms: fully regenerated per invocation, never read back,
      never gating any decision, and **named exhaustively** in the footprint
      check (`docs/storage-architecture.md` D1). The class is stated
      narrowly on purpose: "human-facing" is not a general exemption from the
      footprint invariant, and each member of the surface is enumerated.
    - The path resolves through the path resolver like every other plugin
      storage path; no skill, script or prompt composes it.
    - CAP-1's properties are unchanged and remain the binding constraints:
      deleting the View loses nothing, no code path reads it back, and no
      stored index comes into existence. Only the location moves.
    - **The location moved again (owner ruling — 2026-07-28, #874).** The
      View is **not** written into the `output.drafts` destination
      repository: Terrain is a writing-assistant feature, so its outputs —
      and its debug artifacts — belong in the writing-assistant repository.
      The destination repo's permitted surface shrinks back to `INDEX.md`
      alone, and `docs/storage-architecture.md` D1/D2 carry the scheme; the
      resolver still owns the path, so nothing that calls it changes.
      Because this repository is public and a run's intermediates carry hub
      renderings and pins, the relocation binds together with the ignore
      entry and the staged-artifact guard D2 names — a relocated artifact
      that can be committed is a publication-boundary defect, not a storage
      one.
      **The ruling is narrowed to the owner-facing OUTPUT (amended
      2026-07-30, #935).** It reached one clause too far. The View is a
      deliverable and stays in this repository, guarded as above; **run
      workspaces and debug artifacts resolve back to the machine state
      root**, being the other class — machine-readable intermediates a human
      never opens by intent (owner decision record — 2026-07-16 (artifacts
      live where the human works)). The split is drawn at the resolver, which
      already draws one, so a boundary relocates and no caller changes.
      `docs/storage-architecture.md` D2 carries the class table and both
      costs: the ignore entry and staged-artifact guard **stay** over the one
      remaining artifact, and #874's owed retention rule is discharged **by
      relocation rather than by GC**.
  - **stable indexes and the indexed hand-off.** Every subtopic in the map
    (and View) carries a stable ID (e.g. `T3.2`) from a deterministic ordering
    (topics sorted, subtopics ranked as today), **stable within a pin**; the
    View header carries the map's pin, so a selection made against a stale map
    is **refused with the pin mismatch named**, never silently re-resolved.
    **"The map's pin" is the COMPOSITE of the map's inputs (amended
    2026-07-28, #872).** The clause above was written as though the map had
    one source; it has two, and the guarded value was only ever the
    destination repository's sha. Indexes over hub material — Lessons,
    decisions, reversals, and the arcs beside them — move when the **hub**
    moves, which the destination sha does not record, so the refusal passed
    while the index it guarded had been re-pointed: exactly the silent
    re-resolution this clause forbids, running inside the mechanism meant to
    prevent it. The pin therefore carries **both** its inputs, each labelled
    on the screen, and a mismatch in **either** refuses. The rule stated
    once: **the guarded value must move whenever a guarded index can move.**
    A single displayed sha also mis-taught its reader — it was read as a
    statement about hub freshness, which it never was, and sent one triage
    after a stale pin that did not exist.
    **Publication boundary (binding on this clause):** the hub half is
    `<hub>@<sha>`, so it is displayed **in-conversation** and never written
    into tracked text; the View and any committed artifact carry the
    destination pin plus a **generic** hub label, per
    `specs/spec-writing-assistant/SPEC.md` §Publication boundary.
    Cross-pin stability stays OQ1's escape hatch (promote cluster names to
    recorded frontmatter on observed instability) — out of scope, but the ID
    scheme must not preclude it. Selection is `{index, note}`: the composed
    brief is the subtopic's coverage wording plus **the owner's note
    verbatim**. **Free text always wins**, and an adopted index is
    owner-adopted wording under the shipped rule. The composed brief goes into
    the **existing** stage-0 `--brief` path — no new entry pipeline, and
    downstream cannot tell an indexed selection from a typed brief. The note
    reaches the structure proposer only as brief text, so the single-proposer
    invariant is untouched.
  - **coverage wording is owner-readable by construction (amended 2026-07-23,
    #637).** A candidate's wording becomes the owner's brief the moment they
    adopt it, so **no internal placeholder state may appear in a direction
    string or in a composed brief** — not `(unclustered)`, not `(untracked)`,
    not an empty name. Where a cluster carries no usable name, the wording
    **describes what the cluster contains** rather than naming a subject the
    repo never declared: "cover the not-yet-clustered items under
    `<topic>`", not "cover `(unclustered)`". This is a constraint on the
    *derivation*, not on the rendering: fixing it only where the View prints
    would leave the adopted brief carrying the enum, which is the actual
    defect. The articles repo still owns subject *names* (OQ1) — this governs
    only the wording the tool composes when the repo named nothing.
  - **substance-led rendering (amended 2026-07-23, #647).** A ranked slot is
    filled by **the material's own words**, never by a description of how much
    material exists. `cover docs/stories (163 evidence pointer(s))` describes
    the corpus; a terrain shows it. So:
    - **What fills a slot** is the claim the material makes — an element's own
      summary or why, and for a subtopic a claim drawn from its strongest
      element or Lesson line. The wording is **quoted or clipped from the
      material, never composed about it**.
    - **Clipping is render-only (amended 2026-07-24, #651).** Any length bound
      (`ELEMENT_SUMMARY_CHARS`) is a *rendering* concern, applied where a line
      is printed. The wording the **derivation** composes — the string the
      brief is built from — carries the material's **full** claim, ending at a
      boundary the source actually wrote, **never mid-word**. Clipping the
      claim in the derivation hands the owner a fragment as adopted wording,
      which seeds the thesis candidate and directs harvest as a sentence
      fragment — the same derivation-vs-rendering leak the #637 rule above
      fixes, inverted (a *display* concern leaking into the derivation instead
      of a derivation concern fixed only at display).
    - **Counts demote.** Evidence-pointer counts, unconsumed/live tallies and
      depth arithmetic are map *metadata*: they may appear as a trailing
      annotation at most, and never as the content of a direction or terrain
      line. CAP-2's "why this depth?" was re-pointed at **the header's
      terrain-size line** (amended 2026-07-27, #802; previously "from the
      per-subtopic detail", which no longer exists on the view) and is
      **retired outright** by the later #803 amendment the same day, which
      removes the estimator that raised the question. The one count that
      survives is the **per-member element count on Screen 1** — an affordance
      for choosing where to look, which this clause's ban on count-only lines
      does not reach, because it is not a direction.
    - **Elements are directions.** The element projection (CAP-2, Story 18.80)
      reaches the **same** candidate list the subtopics do and is presented
      **inside** the candidate directions, not in a section of its own. Two
      lists split by internal derivation kind is an implementation detail on
      the owner surface.
    - **No fabricated claim.** Where a subtopic carries no claim-bearing
      material, the line falls back to coverage wording **explicitly** — the
      #637 rule above governs that fallback. The tool never invents a claim a
      source did not make, and never asserts substance it did not read.
    - **The boundary is unmoved.** A substance-led line still names *what to
      cover* and, for a combination, the *axis*; it is not a thesis, an
      argument or an article shape. The no-second-proposer rule above stands
      verbatim, and the brief contract is unchanged: adopted wording is the
      candidate's own wording plus the owner's note.
  - **success:** A sitting that starts at the map ends with a normal
    brief-carrying run; grepping the map implementation for structure
    composition finds none; **no direction or terrain line on a rendered View
    consists only of a subject plus counts, and the elements appear among the
    candidate directions rather than in a separate section**; the map screen offers free-form alongside its
    options every time; a small map behaves exactly as shipped; a >budget map
    produces the View plus summary, is byte-regenerated per invocation, and no
    code path reads the View back. **A >budget View's first screenful presents
    pickable candidate directions — not terrain detail — and no View line
    exceeds its display budget**; grepping the View for a raw pointer
    enumeration or for threshold arithmetic finds none.
  - **provenance (2026-07-23, owner ruling):** this supersedes CAP-3's
    original in-conversation-only reading — "never a path or artifact for the
    owner to open" — for the >budget branch only, by direct owner demand after
    a 20+-subtopic terrain was presented as a two-option screen. The
    alternative that preserved the clause literally (full terrain as
    conversation text, indexes typed into free-form) was offered and declined.
    Mechanism public, provenance private, as with the 2026-07-22 override.
