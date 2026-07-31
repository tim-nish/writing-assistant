---
id: SPEC-terrain
companions:
  - amendments.md            # ratified amendments, 2026-07-30 onward — new ones append here
  - amendments-archive.md    # ratified amendments, 2026-07-24 → 2026-07-29 (relocated verbatim 2026-07-31; closed)
  - presentation.md   # CAP-3, the presentation surface (relocated verbatim 2026-07-30, #941)
sources:
  - ../spec-article-draft-pipeline/SPEC.md   # CAP-9 / the coverage brief and structure proposer this map feeds
  - ../spec-article-plan/SPEC.md             # plan/backlog surfaces the map reads
  # Ratifying owner decision: direct owner demand 2026-07-22 ("a topic map seems
  # essential for routine use"), explicitly superseding the browse-entry-point
  # demand-trigger deferral of 2026-07-22 (hub record; staged for distill).
  # Mechanism public, provenance private.
---

> **Canonical contract.** This SPEC introduces the **topic map**: a read-only,
> derived overview of what the owner *could* write about — topics, their
> subtopic clusters, how much evidence each holds, and how deep an article each
> could carry — presented at the article-creation entry point so the owner can
> steer the free-form story direction (the coverage brief) from an informed
> view, including combining topics along an owner-named axis. **Provenance
> note:** the browsable candidate-story list was deliberately deferred
> (2026-07-22) behind a demand trigger (≥3 sittings where the owner cannot name
> a story and rejects Quick Start). The owner overrode that deferral by direct
> demand the same day, after the first real free-form sitting failed for
> exactly the anticipated reason — no overview to steer by. Per that earlier
> decision's own design note, the free-form entry point's usage is the evidence
> for what this map must contain: it exists to *feed* the brief, not to replace
> it.

> **Ratified amendments** (2026-07-24 → 2026-07-31) live in two companions,
> cut at a **date boundary** — relocated verbatim per the amendment-history
> companion decision (#829, spec sitting 2026-07-27) and, one level down, on
> 2026-07-31 when that companion reached its own byte ceiling.
> `amendments-archive.md` holds **2026-07-24 → 2026-07-29** and is **closed**;
> `amendments.md` holds **2026-07-30 onward**. New amendments are appended to
> `amendments.md`, newest-last, never here and never to the archive —
> **including amendments to CAP-3**, whose clause text now lives in
> `presentation.md`. The cut is by **date and never by CAP**: one spec, one
> dated record, read archive-then-current. Splitting the history alongside
> `presentation.md` would put one sitting's ratifications in two files and
> stays refused.
>
> **The date cut is now MECHANICAL and is no longer a decision** (2026-07-31,
> #1046). Amendment-history companions are their own budgeted file class under
> `SPEC-writing-assistant`'s per-file-class criterion, and the era-split fires
> on a threshold declared in `scripts/check-skill-budget.sh` — the single
> enforcement copy, so no byte figure appears here. When the append target
> crosses it, the closing sitting renames it to its own date range, opens a
> fresh `amendments.md`, and updates this pointer. **What is decided per
> incident is nothing; what is decided once is this rule.** The two splits
> already taken (2026-07-27, 2026-07-31) are its retrospective instances and
> are not re-litigated.
>
> **CAP-3's clauses live in the companion `presentation.md`** (relocated
> verbatim 2026-07-30, #941, when this file passed its byte ceiling). The
> pointer under CAP-3 below names what is there, so a reader learns the
> contents without opening it.

# Terrain

## Why

The free-form story direction (brief → brief-informed structure candidates →
one selection gate, Stories 18.24/18.26/18.45–18.47) assumes the owner can
name the story they want. The first real sitting showed the assumption's limit:
without an overall view of which topics exist, which subtopics live under them,
how much material each holds, and how deep each could support an article, the
owner cannot compose an effective brief — and cannot see cross-topic
combinations ("connect these two topics along this axis") at all. The failure
modes this spec prevents: the owner steering blind (briefs that under- or
over-reach the available evidence); a stored topic index that drifts from repo
reality (every stored-flag design this portfolio has tried has been declined in
favour of derived views); and a second story proposer growing beside the
shipped one (18.45's single-proposer invariant).

The architecture: **the map is a derived, read-only view assembled at
invocation from state that already exists — never stored, never a new
authority; its output is an informed owner, and the owner's chosen direction
flows into the existing brief/structures path unchanged.**

## Capabilities

- **CAP-1 (derived view, never stored state)**
  - **intent:** The map is recomputed at each invocation from authoritative
    sources, enumerated as declared **source families**:
    - **articles-items** — the articles repo (backlog items with
      status/track/evidence pointers, drafts, published set);
    - **hub-lessons** — the hub's Lesson corpus as its **index lines**, served
      through the shipped policy seam (`read-policy-source.py read --only
      LESSONS.md`, the gateway's `lessons_index`: every index line at its true
      line number). Each index line is one lesson seed. *Lesson bodies and
      per-Lesson files are out of scope here — see OQ3.*
      **A lesson's Journey rendering is fetched with it, as part of this
      family (amended 2026-07-28, #871):** the tagged read
      (`gloss --tag journeys/<tag>`) is issued for the tags a member holds,
      and each arc attaches to its lesson rather than enumerating as a family
      of its own — there is no `hub-journeys` family, because there is no
      independently selectable Journey (CAP-2).
    - **host-sources** — the host repo's **declared writing sources**, from the
      single enumerator (`resolve-writing-sources.py files`), read at
      frontmatter/heading level only. **Removed from the candidate set
      2026-07-27 (#803):** article material is Lessons and Journeys, and this
      family emitted ~190 junk directions in the second dogfood ("cover
      check-topic-map" — repo check scripts are evidence, not article
      material). The family is no longer enumerated for candidate derivation;
      dropping it is the removal of the *emitting* path, not a filter over its
      output.

    Plus the track↔topic mapping in per-repo config (articles repo owns track
    names, hub owns topic names, mapping is consumer config under declared
    precedence — ratified 2026-07-21), and the Lesson-consumption derived view
    (a Lesson is available iff no live or ever-published item cites it —
    ratified 2026-07-22). No map file is
    written for later reuse; a persisted copy in the run workspace is a debug
    artifact, never an input. *(Families widened 2026-07-23 — see the
    provenance note under CAP-4.)*
  - **success:** Two invocations straddling a repo change differ exactly where
    the repo changed; deleting the run workspace loses nothing; no new stored
    index exists anywhere.

- **CAP-2 (map content — two screens over the served gloss tag)**
  - **superseded in its unit and its depth signal (2026-07-27, #803).** The
    subtopic cluster below is **removed**, and with it the evidence-density
    signal, the depth estimate and their thresholds — all three were derived
    per subtopic and have no carrier once the unit is gone. Read the clause
    that follows as the historical design; the binding content is:
    - **Screen 1 offers TWO named axes (amended 2026-07-28, #860/#859),**
      each listed deterministically with **an element count per member** —
      the only surviving depth affordance, a cue for choosing where to look,
      never a direction line and never a gate:
      - **by tag** — the served gloss tag, over Lessons and Journeys;
      - **by topic** — the served decision topic, over decisions.
      **The axis label names `decisions` alone, and this is a served fact
      rather than a scoping choice (amended 2026-07-29, #886).** The served
      element vocabulary is exactly three kinds — `decision`, `journey`,
      `lesson` (measured 2026-07-29 against the served surface: 87 / 109 /
      117 records) — and **no `reversal` kind is served at all.** The
      earlier label promised a kind the recall surface does not carry, which
      is a claim about someone else's surface made without consulting it.
      The upstream reason is recorded, not inferred: *"decisions shard by
      TOPIC because that is the only classification a decision line
      carries"* (owner decision record — 2026-07-28 (a decision line's only classification is its topic)). Widening
      the axis back to reversals is therefore a **hub-side extension**, never
      a consumer re-derivation — see the not-served clause on the element
      projection below.
      **Neither axis joins anything.** Each corpus is keyed by the only
      classification it carries, and both keys are *already* shard keys on
      the served side (`gloss/lessons/<tag>`, `gloss/decisions/<topic>`;
      owner decision record — 2026-07-28 (decision axis reopen)). This is
      why the axis pair is not the Lesson→Topic join OQ8 declined — see the
      scoping clause on OQ8 below.
      **Each axis carries its own kind label and its own denominator**, and a
      member is selected within its axis: a shared count line would be false
      for both, and the two vocabularies overlap by name (measured: 2 of 3
      served decision topics are also lessons tags), so an unlabelled member
      list would mint a rival key with no declared precedence — the same
      defect that declined per-entry tags on decision renderings.
      Both members lead to the **same Screen 2**, which is unchanged: no
      screen is added, and the two-screen presentation below still binds;
    - **Screen 2 is that member's complete material** — all its Lessons and
      Journeys, arranged into **presentation-only sections** whose first line
      is a derived group title. Each Strand's line carries its **deterministic
      context fields** (amended 2026-07-27, #844): the Topics (tags) it
      belongs to beyond the member's own, where it originated, and whether it
      carries both a claim and its reasoning — every field **read** from the
      served artifacts or the map, never composed at render time;
      **Journey presence is one of those read fields, and it is marked by
      ABSENCE (amended 2026-07-30, #933/#934).** Three clauses, which bind
      together:
      - a Strand's journey presence is **read from the paired journey record**
        in the served element manifest — never asserted from a literal, and
        never inferred from whether that record's arc rendering happened to be
        addressable. The two are different facts: a journey record whose
        renderings carry no `journeys/`-prefixed path exists while its pointer
        does not resolve, and a row marked *no-journey* for a lesson that has
        one is the same wrong-kind claim this amendment exists to stop.
        Measured 2026-07-30: 117 lessons, 109 journey records, 109 paired, 109
        pointers resolving — **divergence 0**, so this is stated as an
        invariant before it can bite rather than after.
        **Which internal field carries the bit is not this spec's business
        (corrected 2026-07-30, #933).** The clause first written here named a
        consumer dict key, and named it with `journey` — a word this spec
        already binds to one of the three served record *kinds*. Two questions
        collapsed into one token: *is this entry an arc?* (the kind
        discriminator, whose literal `False` on the record-authoritative path
        is **correct**) and *does this lesson have an arc?* (presence). A story
        then implemented the clause faithfully, which would have rerouted 109
        of 117 served lesson renderings out of the lessons lookup. **The
        convention that broke, stated so it holds:** this spec names
        served-side and config vocabulary; a consumer's private field names
        are the implementation's, fixed by its own checks;
      - a Strand row carries **no marker where an arc is present** and an
        explicit **`no-journey` marker where none is**. Presence-marking was
        designed against ~50% coverage and inverts at 109/117: it decorates
        nearly every row, while the thin Strands are the actionable set the
        writability verdict already treats as such;
      - every screen rendering Strand rows **states the coverage
        denominator** — *n of m Strands carry journey material*. This half is
        load-bearing: absence-marking is correct only while coverage stays
        high, so the denominator is what makes the next inversion visible on
        the screen rather than discovered late. Marker without denominator is
        incomplete.
      **No screen may assert that no Journey material falls under a member**
      unless the served records say so — the corrected failure was a
      wrong-kind claim logged as success, and an unrenderable signal is
      indistinguishable from an absent one.
    - **section background prose may be machine-composed at render time
      (amended 2026-07-27, #850 — supersedes the same-day pre-ratified-or-
      absent hold, whose activation condition the hub answered differently):**
      the render-time composition reopen is admissible — its ground was cost,
      and the owner withdrew it (owner decision record — 2026-07-27 (#850 D3:
      composition reopen admissible; invariants bind harder)). The clause
      binds the composer, not just the renderer:
      - composed prose asserts **only what the members of the group have in
        common**, and its authoring class is **declared on the surface**; a
        Strand's own text still quotes **only** its served rendering or the
        not-served disclosure — a composer's paraphrase never substitutes for
        either (the no-silent-fallback rule, #850 D1);
        **the declaration is once per surface, not once per line (amended
        2026-07-30, #936).** Where every line of a visual class is composed,
        the preamble's declaration discharges the obligation and the per-line
        parenthetical is dropped. A **per-line marker is owed again** the
        moment a screen mixes composed and quoted lines of the **same visual
        class** — and then it marks the **minority** class, because that is
        where the reader's default is wrong. The obligation is unchanged in
        force; only its carrier is bounded: a constant repeated on every line
        of a declared class carries zero information per line while costing
        attention on each (unverified — the supporting 2026-07-27 owner ruling
        is cited from the issue body, with no served line returned for it).
        **This does not weaken the violation-layer rule** (owner decision
        record — 2026-07-26 (carry a rule at its violation layer)): the
        preamble sits on the same screen, at the render layer, where the
        reader acts — that rule requires the carrier be where the human looks,
        not one carrier per line;
        **"background" is retired here, and the retirement is a correction of
        meaning rather than of taste (amended 2026-07-29, #888).** For a
        co-tag group the composed sentence states the group's *reason for
        existing* — the germ of a Thesis — and "background" invited reading it
        as context standing behind the members, which is decoration. The
        constraint above is **unchanged in force**: what the composer may
        assert is narrower than before only in the sense that it is now named
        correctly. Where a noun is needed the term is **group claim**, defined
        for the owner in `docs/owner-terms.md` in the act of coining and
        declared in the owner-facing vocabulary list, with an explicit
        boundary: it is **not** a fact-sheet claim. Bare "claim" was
        unavailable — `docs/pipeline-vocabulary.md` already owns it for the
        provenance-classed, verbatim-copied fact-sheet unit, and the composed
        line carries no provenance class, so one word over both objects is the
        two-things-contend-for-one-name failure the kind-qualification rule
        exists to prevent (owner decision record — 2026-07-27 (every
        identifier on a served surface is kind-qualified), which also holds
        that the rendering is the consumer's call while the obligation is
        not). The compound was collision-checked by the method that rejected
        `Seed` — whole-word, case-insensitive, across both repositories —
        and returned zero hits in each (measured 2026-07-29).
        **The same sentence lifted into a thesis-candidate proposal plays that
        proposal's claim role there:** same text, role named per surface,
        which is why the term is defined once with its surfaces rather than
        duplicated per screen. The internal payload key that carries these
        inputs is **not** renamed — a field name is not owner-facing
        vocabulary, and `docs/owner-terms.md` says so in its own preamble;
      - **the permutation and no-selection-authority invariants extend to
        composed sections and bind harder with a model in the loop**: every
        Strand appears exactly once (`count in == count out`, asserted by the
        check script), and a composer able to omit or merge a Strand is the
        grouping-upstream-of-selection defect arriving again, wearing prose;
      - the two-screen no-LLM clause below is unchanged in scope: it governs
        **selection**; composition narrates what is already selected and
        withholds nothing;
    - **sectioning contract (owner ruling, 2026-07-27, #850 D4):** no direct
      parent section may hold more than 20% of the member's Strands —
      subdivide until every direct parent is under the threshold; and **a
      missing served rendering is an abnormal condition to fix immediately**,
      rendered as a loud disclosure at the point of substitution, never a
      tolerated gap;
    - **sectioning is a permutation**: every element of the member appears
      **exactly once**, `count in == count out`, asserted by a check script.
      Completeness is structural, so a wrong grouping is a cosmetic defect and
      never information loss;
    - **grouping runs on a named SUBSTRATE, and completeness is a COVER
      counted in PLACEMENTS (added 2026-07-29, #887).** A substrate is a
      named function from the member's Strand set to named sections. The
      owner picks which substrate is active; substrates **compose** (a
      co-tag sectioning refined by Journey similarity), and each composition
      step carries the same contract as a single one.
      The exactly-once wording above is **corrected, not weakened**: it was
      written for a single-valued key and is false for a multi-valued one —
      a Strand carrying four tags belongs in four co-tag sections, and
      forcing it into one requires a tie-break, which is a machine deciding
      which relationship the owner is allowed to see. The ratified form is
      the one the hub states: *"An axis is admissible on the two ratified
      invariants — completeness and presentation-only — NEVER on being a
      partition … The ratified tag axis is already multi-valued, so
      multi-valuedness disqualifies nothing"*, and *"because the field is
      multi-valued the >20% cap is computed against PLACEMENTS rather than
      elements or it silently under-reports"*
      (owner decision record — 2026-07-28 (axis admissibility; placements as the counting unit)). So:
      - **completeness** — every Strand appears in **at least one** section;
        `count in ≤ count out` and **every Strand accounted for**, asserted
        by a check script exactly as the permutation form was;
      - **placements are the counting unit** — the 20% sectioning cap above
        is computed against placements, never against distinct Strands;
      - **a Strand with no relation under the active substrate renders in an
        explicit named section** ("no shared batch", "no cross-links"),
        never a silent drop — the same rider the hub attached to the
        `projects:` portfolio-wide case;
      - where a substrate **is** single-valued, exactly-once still holds and
        is the stronger check; the cover form is the floor, not a licence.
    - **the composer may partition and may never narrow (added 2026-07-29,
      #887).** A model in the render loop is admissible (the cost ground was
      withdrawn 2026-07-27), and this clause states where the line falls,
      because a similarity substrate is a *scoring* operation by nature and
      scoring is the barred act's own vocabulary. The boundary, quoted:
      *"a combination becomes a PROPOSAL exactly when something other than
      the owner narrows the candidate set. Enumerating every combination,
      letting the owner filter, sorting deterministically by a declared key,
      and offering the owner's own approaches as modes are all navigation;
      ranking, scoring, recommending a subset, or hiding low-scoring
      combinations are proposals and fall on the far side of the ban"*
      (owner decision record — 2026-07-28 (the second-proposer boundary)). Applied here: a substrate **may**
      place Strands into sections and derive each section's title; it **may
      not** rank sections, order them by score, surface only the strongest,
      hide a weak section, or omit a Strand. Section order is a **declared
      deterministic key**, never a quality judgment. The count check runs
      **after** composition, on the composed output, because a composer that
      cannot omit in principle can still omit in fact.
    - **two substrates ship, and the other two are NOT SERVED (added
      2026-07-29, #887).** Reachability is a property of the seam, measured
      rather than assumed, and the measurement corrects a coverage table
      taken hub-side:
      - **co-tags** — the manifest's `tags` field. Served as data.
      - **Journey similarity** — over the **served** arc renderings
        (`gloss --tag journeys/<tag>`, the read CAP-1 already issues).
        Served as data. Built, and held unoffered until measured once
        (amended 2026-07-29, #889); **OFFERED since 2026-07-31**, when that
        measurement run passed its owner verdict — see the offering gate
        below, which records what was measured.
      - **shared source batch** — served only as prose, inside a shard
        trailer line (a `Source: … · origin: <batch> (<date>) · tags: …` trailer).
        **Not projected**: extracting it is consumer re-derivation of hub
        data by markdown parsing, which is the named defect class — *"serve
        structure so there is nothing to parse … Every 2026-07-28 defect was
        consumer RE-DERIVATION of hub data"*
        (owner decision record — 2026-07-28 (constrain generation, not post-hoc detection)). The route is a
        served `origin` **field**, asked upstream.
      - **`[[slug]]` cross-links** — **not served at all**: measured
        2026-07-29, the served `gloss/lessons/<tag>` shard contains zero
        `[[` occurrences, and the graph lives in lesson bodies, which OQ3
        records as unservable. The 426-edge measurement in the request was
        taken hub-side, against files a consumer cannot read. The route is a
        served `links` field, asked upstream.
      Both absences are **disclosed as a line** where the substrate would
      have been offered, so "this substrate is missing" is distinguishable
      from "this substrate found nothing";
    - **a model-judged substrate is offered only after one measurement run
      (added 2026-07-29, #889).** A deterministic substrate is offered as
      soon as it is built: its output is inspectable by reading the key it
      grouped on. A **model-judged** one is not, because whether its groups
      read as *one shared background* is the very thing at issue, and the
      owner had not yet seen one. So Journey similarity was **built and
      exercised, and withheld from the offered set**, until:
      - one run over the `agents` member renders its groups in the screen's
        compact form, each with its `in common:` line stating the shared arc;
      - the remainder renders in an explicit **"no shared path"** section —
        never a silent drop;
      - completeness is checked mechanically. This substrate is expected to
        be **single-valued** (a Strand sits in one shared-path group), so the
        stronger exactly-once form applies to it, per the cover clause above,
        which holds exactly-once as the floor's stronger case rather than as
        a competing rule;
      - the **owner** verdicts whether the groups read as real backgrounds.
        Pass → it joins the offered set. Fail → the finding (which substrate
        combination, if any, to try next) is the output, and the substrate
        does not ship anyway.
      **THE GATE RAN ON 2026-07-31 AND PASSED, so Journey similarity IS
      OFFERED (discharged 2026-07-31, #889 measured, #1031 offered).** The
      clause above is recorded as written and is not rewritten to match its
      own outcome: what changed is that its condition was met. The run took
      the `agents` member (51 Strands), rendered **10** machine-composed
      shared-path groups in the compact form, placed **48 of 51** Strands and
      accounted for the remaining **3** explicitly in the two named residues,
      and checked the permutation mechanically — count-in 51 = count-out 51,
      no drops, no duplicates, no invented ids. The **owner verdicted PASS**
      on 2026-07-31, recorded on the measurement issue itself (#889, closed on
      that verdict; #1018 is the discussion record filed from it) — the
      verdict-holder the gate named, discharging the gate by the single
      identifiable act it was written to be dischargeable by.
      Offering is **not promoting**: co-tags remains the default substrate for
      a run that names none. What the discharge does **not** license, stated
      because inheriting a boundary is cheaper than re-arguing it: the
      hub-wide Journey-coverage figure was **not** re-measured — the run
      measured 49 of 51 for one member, a different denominator — and no
      ranking of groups by strength, size or judged quality is admitted; the
      declared sort key stays presentational.
      **The gate names its own generating mechanism deliberately**, because a
      deferral to data that does not is indefinite by construction and reads
      as patience rather than as a gap: the corpus, the judgment input (the
      served arc renderings), the render form, the completeness check and the
      verdict-holder are all fixed above, so the condition is dischargeable by
      a single identifiable act.
      **This is not a general ceremony for new substrates.** The
      discriminator is *model-judged versus deterministic*, and the
      precedent is specific: a presentation-only unit shipped provisionally
      once before, and two dogfood runs produced the anticipated failure
      verbatim — one placing nearly the whole corpus in a single group. The
      presentation-only invariant bounds the *damage* of a wrong grouping; it
      does not make an unreadable one useful.
    - **groups carry a `G` id, and it is a DISPLAY kind (added 2026-07-29,
      #889).** A group is addressable so the owner can refer to one, and the
      surface declares the kind — every identifier on a surface is
      kind-qualified, and a reader who is not told the kinds never learns the
      others exist. `G` confers **no selection authority**: selection remains
      by element id, per the presentation-only invariant. Stated explicitly
      because an id that looks selectable and is not is precisely the defect
      that retired the `J<n>` namespace.
    - **elements remain the selectable unit** (`E<tag>.<n>` in the tag's
      namespace), and selection still composes an ordinary brief.
    - **A Journey is an arc ON its lesson's row, not a Strand of its own
      (amended 2026-07-28, #871).** The selectable units are `L<n>` (Lesson)
      and `E<topic>.<n>` (decision or reversal); the `J<n>` namespace is
      **retired**, having never once been populated in production. Where a
      lesson carries a served `journey_gloss:` rendering, that rendering is
      **displayed on the lesson's own row** as how the position changed, and
      the lesson is what the owner selects. The correspondence is why:
      Journey↔Lesson is 1:0..1 — a Journey **is** its lesson's arc, and the
      hub's tier-1 discovery marker is per-lesson by ratified design, so an
      independently selectable Journey would assert a reachability the served
      shape does not carry. **This is the boundary to watch, not a settled
      preference:** the hub recorded, live and against its own decision, that
      a consumer needing to select a Journey *without* first selecting its
      lesson turns that marker into a subordination the selection model does
      not have
      (owner decision record — 2026-07-28 (terrain membership and journey display)).
      Adopting independent Journey selection later is
      therefore a **hub-side conversation**, never a quiet consumer change.
      Nothing is withheld by this: every served arc appears, on the row the
      owner reaches it from.
      **The retirement owes a consumer-side cleanup (amended 2026-07-30,
      #933).** Retiring a namespace in spec text left the code that mints it
      standing — a `journey` counter and a `J` prefix branch, reachable only
      on a kind the record path never emits. Dead code implementing a retired
      contract is not inert: it is why a screen could be written as though `J`
      rows might appear. The branch **goes**, and what a Journey arc's
      presence means on a row is carried by the absence-marking clause under
      Screen 2, not by an id.
    - **The by-topic axis's members are the served `decisions/<topic>`
      shards** — enumerated, never consumer-declared (see CAP-4's amended
      denominator clause). The E Strands under a member are built from that
      shard's **ratified entries**, each quoting its served rendering, so the
      axis needs no raw `topics/*.md` read to be complete over its own
      denominator.
      **The enumeration is the served element manifest, not a shard read
      (amended 2026-07-29, #886).** Every `decision` record carries its own
      `topic` and its `decisions/<topic>` rendering as **labelled fields**,
      so one manifest read yields the axis members, their per-member counts,
      and the E Strands under them together. Measured 2026-07-29 against the served
      surface: 87 decision records over 4 topics
      (`knowledge-architecture` 50, `articles` 33, `claude-code-ops` 2,
      `monetization` 2), each sourced at `topics/<topic>.md:<line>`.
      This is **the same acquisition path CAP-1 already binds for Strand
      membership** (amended 2026-07-29, #884) — not a second mechanism —
      and it is chosen over re-reading the shard renderings for the reason
      the hub states: consumer **re-derivation** of data the hub already
      serves as fields is the defect class, and a consumer that receives an
      element as fields cannot mis-parse it
      (owner decision record — 2026-07-28 (constrain generation, not post-hoc detection)). Records unavailable
      degrades exactly as CAP-1's Strand acquisition does — to the read it
      can still make, **with the substitution named**, never silently.
  - **intent (historical — subtopic clustering, removed 2026-07-27):** Per
    topic, the map shows: its subtopic clusters (grouped from
    backlog items, unconsumed Lessons, and evidence pointers sharing a
    subject — under OQ1's declared precedence as closed 2026-07-23: a
    declared `subtopic:` key in the articles repo names the cluster, and a
    **path-family** derivation is the fallback for undeclared items, with
    each cluster disclosing which basis named it); per subtopic, an
    **evidence-density signal** (count of distinct
    evidence pointers, unconsumed Lessons citing it, backlog items and their
    status) and a **depth estimate** — what the material supports today
    (seed-only / short note / full article / article series), derived from the
    density signal by declared thresholds, presented as a signal for the
    owner's judgment and never as a gate (thresholds gate surfacing, never
    what the owner may pick). Already-consumed material is shown as consumed,
    not hidden — the owner may still pick it at the free-form entry.
  - **elements — a second projection, not a replacement (added 2026-07-23,
    #631/OQ4).** Beside the subtopic clusters, the map projects **typed
    elements** from the recall surface: `decision` (a dated `topics/*.md` line
    with its reasoning and `the hub decision archive` pointer) and `reversal` (a Declined or
    struck-through topic line, or a `LESSONS.md` index line whose lesson
    records one). Each element carries a one-line summary, the situation it
    was recorded in (its date and source line), a consumed mark, and its
    evidence pointer. **The subtopic cluster remains the map's primary unit**
    — clusters answer "what material do I have?", elements answer "what did I
    decide, and what changed my mind?", and the owner picks from either.
    - **`reversal` is NOT SERVED, and is therefore not projected (amended
      2026-07-29, #886).** The clause above is kept rather than deleted,
      because the *promise* is not withdrawn — what is recorded is that the
      recall surface carries no such kind to project. The served element
      vocabulary is `decision`, `journey`, `lesson` and nothing else
      (measured 2026-07-29 against the served surface); a decision line's only
      classification is its topic
      (owner decision record — 2026-07-28 (a decision line's only classification is its topic)). The two derivations
      the original clause named — "a Declined or struck-through topic line"
      and "a `LESSONS.md` index line whose lesson records one" — are
      **consumer inference over rendering prose, and are forbidden**: a
      consumer quotes a ratified field and never paraphrases one into
      existence. So the projection **discloses the absence as a line** per
      the disclosure-is-a-line rule, and the route to reversals is a
      **hub-side extension of the manifest**, requested as an obligation and
      never re-derived here. Until it lands, "no reversal is shown" means
      *not served*, which is distinct from *none exists* — and the screen
      says which.
    - **`thinking` is deliberately absent** until OQ3 closes: its payload is
      the `## Journey` body in `lessons/*.md`, which the seam cannot serve.
      No projection may synthesize it from what is readable.
    - **Elements carry their own index namespace** (`E<topic>.<n>`, stable
      within a pin, ranked deterministically) so an indexed selection is
      unambiguous against the subtopic `T<topic>.<subtopic>` scheme. Selection
      and brief composition are otherwise unchanged: `{index, note}` in, one
      ordinary brief out.
    - Elements are **derived per invocation and stored nowhere**, exactly as
      CAP-1 requires of everything else on this map.
  - **success (rewritten 2026-07-27, #803 — the depth question is retired, not
    re-pointed):** Screen 1 lists every served gloss tag with its element
    count, so a rich member and a thin one are visibly different at a glance.
    For any member selected, Screen 2 shows **all** of its elements: the
    permutation check passes (`count in == count out`), every element appears
    exactly once, and grepping the section machinery finds no gate — sections
    carry a title and nothing else. *(The former success clause promised the
    owner could ask "why this depth?" and be answered from pointer counts. The
    #802 amendment re-pointed that answer at the header's size line; this
    amendment retires the question itself, because the estimator that raised
    it is gone.)*

- **CAP-3 (presentation and the combination move)** — **relocated to the
  companion `presentation.md` (2026-07-30, #941).** The canonical file passed
  its byte ceiling, and the growth was measured before anything moved: CAP-2
  and CAP-3 together were 63% of it. CAP-3 moved **verbatim** — no clause was
  compacted, reworded or re-ordered, because a projection may relocate text
  and never re-express it.
  **What is there, named rather than left to a lookup:** the two screens and
  the standing exits; in-invocation navigation over held state (one corpus
  load, back and switch-substrate re-present held state, no cross-invocation
  cache); **set selection and claim recomposition** over an owner-selected
  Strand set, with the brief recording its member set and pins; the
  **coherence consultant** and its four bounding rules; the **Full Report**
  over named group ids; the **size switch** and its budget; the **View file**
  and its never-read-back rule; and the indexed hand-off with its composite
  pin. The no-second-proposer boundary is stated there, with CAP-3's intent.
  **The amendment history did not move** — every dated amendment for this
  spec, including those amending CAP-3's clauses, stays in `amendments.md`.

- **CAP-4 (bounded assembly, disclosed per family)**
  - **intent:** The map is assembled from **index and frontmatter surfaces**
    — backlog frontmatter, INDEX files, Lesson index lines, declared-source
    frontmatter/headings, evidence-pointer lists — never a full-body fan-out
    over article prose or the hub's history, and **never a drafting-stage
    extraction pass**: harvest's per-source budgeted extraction is a cost the
    map does not pay, so "show me the terrain" stays index-scale.
    Enumeration is **per family** (CAP-1), and disclosure names its own
    denominator: the coverage manifest lists **which source families were
    enumerated** and **which declared families were not**, alongside the
    per-surface read/skipped lists. When a declared corpus exceeds the read
    bound, the map discloses the exclusion (which surfaces were not read)
    rather than silently narrowing — the same coverage-disclosure convention
    harvest uses. **"Complete" is complete over a named denominator**: a
    coverage claim that does not name the families it covers is the defect
    this clause exists to prevent.
    **Disclosure is a LINE, never a section (amended 2026-07-27, #802).** The
    duty above is satisfied by the one-line coverage and gloss disclosures
    that already sit directly under the candidate directions
    (`_element_coverage_line`, `_gloss_disclosure_line` in
    `scripts/terrain_text.py`), and by at most a one-line note in the
    header when the assembly was bounded. A disclosure that grows into its own
    section is **not** better disclosure: the observed failure is that ~2,300
    of a 2,511-line view served no purpose the owner could identify, so the
    duty was being discharged by volume rather than by legibility. What is
    owed is that the denominator is *named*, not that it is *expanded*.
  - **the element family is bounded by the seam, and says so (added
    2026-07-23, #631/OQ4).** CAP-2's element projection reads the recall
    surface through the pinned read-only pointer, which serves `GLOSSARY.md`,
    `LESSONS.md` and **at most 2 `topics/*.md` per read**
    (`scripts/read-policy-source.py:100`). The hub currently carries 9 topic
    files, so **element coverage is partial by construction**: a run projects
    elements only from the topics it already selected, and the coverage
    manifest names which topics were read and which were not — the same
    disclosed-denominator rule this capability already states for every other
    family. Widening that scope is a **hub-side ratification**, never a
    map-side workaround; a run may not issue extra reads to synthesize whole
    coverage, and no element is invented for a topic that was not read.
  - **each axis is served whole, and Journeys degrade loudly (amended
    2026-07-27, #803; made per-axis 2026-07-28, #860).** Screen 1's
    denominator is **the served shard listing itself**, which the seam
    returns in one bounded enumeration — so an axis listing is complete by
    construction and the `≤2 topics/*.md per read` bound above stops being
    load-bearing for it.
    **The carve-out that kept the bound on the element projection is struck
    (amended 2026-07-28, #873).** It read "it still binds the
    `decision`/`reversal` element projection, unchanged", and it cannot stand
    beside the denominator sentence above: an axis may not list three topics
    whose Strands a run is forbidden to reach. What was measured is that the
    two clauses composed into a silently config-bounded axis — the by-topic
    element set was the consumer's declared `policy_source.track_topics`
    capped at two, so one member appeared where the hub served three, and
    Screen 1's "nothing is withheld" stance was false without saying so.
    The resolution: **the topic axis and the Strands under it both derive from
    the served `decisions/<topic>` shard listing**, whose ratified entries
    carry their own renderings, so no raw thread read is required to project
    them. The `≤2 topics/*.md` bound survives unchanged for anything that
    still reads a raw `topics/*.md` thread, and its disclosure with it.
    **Membership is never consumer-declared:** `track_topics` keeps its
    track↔topic mapping role and stops being an axis denominator — a config
    key deciding what the owner may reach is the withholding this axis exists
    to prevent.
    **Stated as an implementation obligation, because the promise above
    shipped and the code did not (amended 2026-07-29, #886).** The clause
    was written 2026-07-28 and the axis still enumerated from
    `policy_source.track_topics` bounded by `ELEMENT_TOPIC_BOUND=2`
    (`scripts/terrain_map.py:1071-1078, 1155-1156, 1273-1275`), so on every
    repo declaring no mapping — the default — the axis offered **0 members**
    while the hub served 4 topics and 87 decisions. A promise whose
    implementation is unwritten reads exactly like a promise being kept:
    nothing failed, and the screen's own disclosure said the axis was empty
    *because no topic was declared*, which was true and was the defect.
    So the obligation is written as one: **for this axis, `track_topics` and
    `ELEMENT_TOPIC_BOUND` bound nothing** — neither the member list, nor the
    per-member count, nor the E Strands beneath it — and a run may not
    reintroduce a consumer-side bound under any name. The `≤2 topics/*.md`
    bound survives unchanged for anything that still reads a raw thread.
    **The denominator is the served manifest's decision records for that
    topic**, disclosed against the axis, per the manifest clause in CAP-2.
    **The denominator is per axis, never pooled:** the tag axis's
    denominator is the served `lessons/<tag>` shard listing and the topic
    axis's is the served `decisions/<topic>` shard listing, each disclosed
    against its own axis. Pooling them would produce a count that is a
    completeness claim over neither corpus.
    **A consequence, stated so it is not lost:** while decisions and
    reversals had no axis, Screen 1 disclosed them as a residue outside the
    axis ("N Strand(s) carry no served tag"). That line is **false the
    moment the topic axis is offered** — those Strands are now reachable —
    and it is **retired, never extended**. What survives is the per-axis
    denominator above; a Strand outside *every* axis is still disclosed as a
    line, per the disclosure-is-a-line rule.
    **Journeys are requested, not awaited (amended 2026-07-28, #871 —
    supersedes the shadowed-shard clause below).** A run **issues the tagged
    read** for the member's tags (`gloss --tag journeys/<tag>`) and renders
    each arc on its lesson's row per CAP-2. The shard **address** was fixed
    upstream and **discovery** is the per-lesson tier-1 marker the map already
    parses, so neither conjunct is outstanding; what was outstanding was the
    request itself. A shard the run cannot address is **named on the screen**
    as a line, per the disclosure-is-a-line rule above, and never omitted
    silently.
    **A corpus that was not requested is never reported as not served
    (added 2026-07-28, #871/#872).** The two are different facts about
    different parties, and reporting the first as the second attributes a
    consumer's omission to the source. This is not hypothetical: a run
    displaying "no Journey renderings were served at this pin" — while
    issuing only the untagged tier-1 call, so no journey shard was ever asked
    for — sent a real triage looking for a stale pin and a hub gap that did
    not exist. Each disclosure line therefore names **which** of the three it
    reports: requested-and-served, requested-and-missing (the abnormal
    condition CAP-2 requires be fixed immediately), or not-requested.
    *(Superseded, kept for the record: "journey shard tags are shadowed by
    same-named lesson shards upstream, so until the hub's addressability issue
    lands a run names the shortfall on the screen." The upstream fix landed;
    the shortfall outlived it because nothing asked.)*
    **A served path that differs from the requested one is an abnormal
    condition, announced at the point of substitution (added 2026-07-29,
    #873).** The map **cites the path the seam actually served**, never one
    recomposed from what it asked for; where the two differ the run says so on
    the screen, as a line, and the affected material is marked rather than
    presented as the thing that was requested. A recomposed cite is not a
    cosmetic shortcut — it is what makes a substitution *unobservable*, and an
    unobservable substitution is indistinguishable from a correct read.
    Measured, twice, on this exact seam: a request for `topics/<t>.md` was
    served `topics/archive/<t>.md`, and because the cite was rebuilt from the
    requested topic key the screen displayed archived decisions as the live
    record with nothing anywhere reporting it. **The consumer never relies on
    an upstream fix to make this visible:** the detection is the consumer's
    own, because the failure this rule exists to catch is precisely the one
    where the upstream fix is believed to have landed and has not. The
    general form is the same rule CAP-2 states for a missing rendering — an
    abnormal condition is fixed, not tolerated — applied to a *substituted*
    one, which is the harder case because nothing is missing.
  - **success:** Map assembly cost scales with index size, not corpus body
    size; an over-bound invocation's output names what it skipped; the closed
    accounting (`read + skipped == matched`) holds **per family**; a reader of
    the manifest can tell which families a "complete" claim covers and which
    declared families it does not.
  - **provenance (2026-07-23, owner ruling):** CAP-1's source list and CAP-4's
    index-and-frontmatter-only wording were widened by direct owner demand
    after the first large-corpus invocation returned 2 topics / 2 subtopics
    with an honest "coverage complete" — true over the wrong corpus, because
    enumeration reached only the articles repo's own items. The widening is
    deliberately **index-level and consumer-side**: no gateway grant is
    required and no harvest pass is invoked, so the cost promise above
    survives the corpus growing. Mechanism public, provenance private, as with
    the 2026-07-22 deferral override.

## Open questions

- **OQ1 — subtopic clustering authority. CLOSED 2026-07-23 (#614).**
  *Original question:* whether subtopic clusters are computed per invocation
  (pure derivation, may vary run to run) or proposed once and recorded as
  backlog frontmatter (stable names, but a stored vocabulary to maintain —
  the articles repo would own it, per "the repo's schema is the API"). The
  original answer was: start pure-derived; promote to recorded frontmatter on
  observed instability.
  **Trigger amended.** The promotion trigger read *observed instability*
  (names moving between pins). The failure actually observed at corpus scale
  is **degeneracy**: a 147-subtopic map whose clusters were stable and
  useless — one subtopic per file, because the derivation's fallback is an
  evidence-pointer *file stem* and host-source items cite only themselves.
  Stable-but-degenerate is a distinct failure from unstable, and it is
  equally disqualifying, so the trigger now names both.
  **Resolution — both mechanisms, under declared precedence:**
  - **The articles repo owns subtopic names.** A declared `subtopic:` (or
    `cluster:`) key in backlog frontmatter is authoritative, consistent with
    "the article repo is separate permanently; the repo's frontmatter schema
    is the API, the tool never owns state" and with the ratified
    track↔topic vocabulary-ownership split. A declared name that a cluster
    disagrees with is the tool's defect, never the repo's.
  - **The derivation is the fallback, and must be good.** Undeclared items
    still cluster, by **path family** rather than by file stem — the corpus
    cannot be annotated in one sitting, and a map that stays degenerate until
    a backfill completes fails the owner for the whole interval. The
    derivation invents no stored state: it is recomputed per invocation and
    recorded nowhere, so CAP-1 is untouched.
    **"Good" governs the WORDING too (2026-07-23, #637), not only the
    clustering.** A cluster the derivation could not name still has to be
    describable to the owner, because its coverage wording becomes their brief
    on adoption (see CAP-3's owner-readable-wording clause). An internal
    placeholder reaching that wording is the tool's defect, never the repo's —
    the same rule this section already states for a declared name a cluster
    disagrees with.
  - **The basis is disclosed.** Each cluster states whether its name is
    `declared` or derived, so the owner can always tell which authority
    produced it — the mismatch check is recomputation, never reconciliation,
    and no vocabulary is cached on the tool side.
  Cross-pin ID stability (CAP-3) now has its escape hatch in the declared
  key, exactly as that clause anticipated.
- **OQ2 — relationship to a "decide for me" entry point.** *(Restated
  2026-07-22, triage #583.)* **`unverified — no such surface ships today`:**
  "Quick Start" names no capability, skill, script, or contract in this
  repository — the term appears only in this spec. The original phrasing read
  as a binding to an existing entry point, which would be an unverified
  inference, so the question is restated at the altitude it actually sits at:
  **should a machine-selected "decide for me" entry point exist at all**, and
  if one is ever built, does it absorb, feed, or sit beside the map? The two
  answer different questions ("decide for me" vs "show me the terrain"), and
  side-by-side entry points sharing CAP-1's assembly remains the leaning — but
  nothing here may be written as though the counterpart exists. **This spec
  binds only to surfaces that ship**: CAP-3's outcome is handed to the
  **existing stage-0 `--brief` path** (`skills/draft-article/SKILL.md`, owner
  coverage brief, Story 18.24 / #505), and CAP-1 reads the shipped
  `track_topics` config mapping (`scripts/resolve-writing-sources.py`, #525).

- **OQ3 — Lesson bodies are unservable, so depth from a Lesson is coarse.**
  *(Raised 2026-07-23 with the CAP-1 widening.)* CAP-1's `hub-lessons` family
  reads **index lines only**, because the policy seam's read scope is
  code-enforced to `GLOSSARY.md`, `LESSONS.md` and ≤2 `topics/*.md`
  (`scripts/read-policy-source.py:101`, `:286`), and that boundary is enforced
  server-side by the gateway's grant table as well (`:21-22`) — per-Lesson
  files are structurally unreadable *and* unservable from here. Consequently a
  richer per-Lesson signal (notably the `## Journey` marker the working-note
  workflow selects on) **cannot be read consumer-side today**, and nothing in
  this spec may be written as though it can. Obtaining it would require a
  hub-side grant change, which is the hub's decision and not this repository's
  to make (gateway read-only, grants hub-owned). Open: whether to request that
  grant, or to accept index-line seeds as the permanent shape and let depth
  from lessons stay coarse.

- **OQ4 — is the map's unit a subtopic cluster or a typed element?** *(Raised
  2026-07-23 with #631; deliberately left open by that issue's resolution.)*
  #631 asks for the map's unit to become a **typed element** — `lesson |
  failure-retro | reversal | decision | thinking`, each with a one-line
  summary, the situation it was recorded in, a consumed mark, and 1–3 evidence
  pointers — grouped by situation or by similar meaning, rather than the
  path-family subtopic cluster CAP-2 declares and OQ1 closed. The rendering
  half of that direction was resolved above (the View leads with directions,
  and is budgeted); **the unit itself was not**, for a reason that is a fact
  about the substrate rather than a preference:
  - CAP-4's declared families are exactly `articles-items`, `hub-lessons` and
    `host-sources` (`scripts/terrain_map.py:153-155`), and `hub-lessons` is one
    seed per `LESSONS.md` **index line** (`:328-335`). Nothing this repository
    can read records a **reversal**, a **decision with its why**, or
    **thinking-at-the-time** as a typed record. Three of the five proposed
    element types are therefore not projectable today.
  - Reaching them means widening the policy seam's read scope, which is
    **hub-side ratification, not a map-side change** — the same boundary OQ3
    documents, and #631 states this itself.
  So the unit question is blocked on the same upstream decision as OQ3, and
  adopting the element unit before that grant exists would write this spec as
  though it can read what it cannot. Open: whether to request the grant (with
  OQ3, as one hub-side ask), or to keep the subtopic cluster as the permanent
  unit and treat typed elements as a projection the hub itself would have to
  serve. Until this closes, #631 stays open against it.

  **CORRECTED AND CLOSED 2026-07-23 — the blocking claim above was false.**
  It was written from the consumer's family list without consulting the served
  surface. A consultation the same day
  (`hub@<private-pin>`) shows all three "missing" types are recorded, and
  **inside the existing whitelist** — no grant is required:
  - **Decisions with their why** are the topic lines themselves: every
    `topics/*.md` entry is dated, states its reasoning, and carries a hub-decision-archive
    provenance pointer (e.g. `topics/knowledge-architecture.md:9,21,39`).
  - **Reversals** are recorded natively — "topic Declined lines and
    struck-through superseded decision lines (**the recall surface's native
    reversal records**)" (`topics/articles.md:30@<private-pin>`), alongside the
    reversal-capture lesson at `LESSONS.md:23`.
  - **Thinking-at-the-time** has a typed producer: distill-checklist item `N`
    (narrative candidate), payload "original framing verbatim → the actual
    question it became → what moved it"
    (`topics/knowledge-architecture.md:67@<private-pin>`).

  What is genuinely unreachable is only the **`## Journey` body**, which lives
  in `lessons/*.md` — unservable, and already tracked as **OQ3**. The
  existence and one-line form of a reversal are on the index and topic lines
  and are readable today.

  **Resolution:** the map gains a **second projection** — typed elements
  beside the subtopic cluster (CAP-2), not replacing it — over what is
  actually servable: `decision` and `reversal`. `thinking` is **out of scope
  until OQ3 closes**, and no spec text may claim it. The real constraint is
  **breadth, not access**: `MAX_TOPICS = 2` per read
  (`scripts/read-policy-source.py:100`) against 9 topic files, so element
  coverage is partial by construction and is **disclosed**, per CAP-4.
  *(Method note: the false claim survived a whole sitting because the spec
  lane grounded in the consumer's code and not in the served surface. Grounding
  a claim about an upstream surface means consulting that surface.)*

- **OQ8 — can the hub Topic ever be the navigation axis? CLOSED 2026-07-27:
  NO — the axis is the served tag vocabulary, ratified upstream.** The
  upstream gate answered the staged question: Topics-with-a-new-join is
  Declined, the axis members are the served tags, and the UI word "Topic" is
  retired for the axis. Screen 1's axis is decided; stories may encode it.
  **SCOPED 2026-07-28 (#860/#859) — this closure covers a Lesson→Topic
  JOIN, and nothing else.** What was declined is *building a join* to give
  Lessons a Topic membership they do not have: measured, 6 of 9 Topics carry
  no lessons shard and only 3 of 9 names overlap, so the membership had to be
  manufactured. A **decisions-by-topic axis manufactures nothing** — it runs
  over a different corpus in the opposite direction, and a decision line's
  topic *is already its shard key* (verified by bounded enumeration:
  `gloss/decisions/` serves 3 topic shards; owner decision record —
  2026-07-28 (decision axis reopen)). CAP-2 therefore now carries two axes,
  and the decline above stands untouched — it is simply not about this.
  *(Method note: the collision was asserted, then disproved by consulting the
  served surface — the same method this OQ's own note prescribes. Being the
  rule's author is not exemption from it.)*
  *(Historical text below, kept as the record of why it was blocking.)*
  **(raised
  2026-07-27 by the #803 sitting, which disproved the premise that it already
  could be; escalated to blocking the same day by the #809 re-triage, which
  found the upstream had ratified Topic-first navigation by name).** While this
  is open, **Screen 1's axis is undecided and no story may encode one** — the
  consumer cannot honour the upstream ratification without a served membership
  surface, and it will not diverge from it silently either.
  The gloss tag was chosen as the axis on 2026-07-27 because that is the axis
  whose membership the seam actually serves; **that choice is suspended, not in
  force** (see the re-triage amendment above). The hub Topic is the structure
  the owner actually maintains by hand, and the upstream has now ratified
  Topic-first navigation by name — but
  there is **no served Lesson→Topic membership**, the two vocabularies overlap
  in only 3 names, and 6 of 9 topics carry no lessons shard at all. Two
  non-answers, both already ruled out rather than merely unattractive:
  - a **consumer-side tag→Topic mapping** is Declined upstream as
    consumer-side re-expression of ratified lines — N consumers would make N
    unratified restatements of the hub's own structure;
  - a **map-side workaround** issuing extra reads to synthesize membership is
    forbidden by CAP-4's own clause ("a hub-side ratification, never a map-side
    workaround").
  So this closes only if the hub ratifies a served membership surface. **The
  ask belongs upstream and is not this repo's to make** — until then the axis
  is the tag, the spec says so plainly, and no code approximates the mapping.
  *(Method note: the same one as OQ4 above, one sitting later — the premise
  that the gloss index was per-Topic was written from consumer-side reasoning
  and survived into an accepted issue body. One `surface_names` call refuted
  it. Grounding a claim about an upstream surface means consulting that
  surface.)*

- **OQ9 — is Screen 1 an axis chooser or an APPROACH chooser? OPEN, raised
  2026-07-29 (#886).** CAP-2 above models Screen 1 as **two named axes** side
  by side (amended 2026-07-28). One day later the hub ratified a different
  shape: *"screen 1 selects an APPROACH, each approach carries its own axis
  over its own population, and topic selection lives only inside the Decision
  flow"* — by-repository on the attribution field, Decisions-within-one-Topic
  on the topic, Lessons-plus-Journeys on tags
  (owner decision record — 2026-07-28 (screen 1 selects an approach), which names this issue chain as its carrier).
  The divergence is **recorded here and deliberately not resolved under
  #886**, whose mandate is an axis returning 0 members; rewriting the screen
  model would be a larger act than the report, decided without the owner at
  the fork. What is *not* in doubt is the half both shapes share and #886
  executes: enumeration comes from the served side, and `track_topics` +
  `ELEMENT_TOPIC_BOUND` bound nothing.
  Two facts to carry into whichever sitting closes this:
  - the **owner's own vocabulary** in #886 and #887 is "entry point 2" /
    "entry point 3" — the approach model, not the axis model;
  - the hub line claims the 132-Strands-outside-the-axis gap *"vanishes once
    approach 2 exists"*, and approach 2 runs on the decision **attribution**
    field, whose backfill is **prospective only**
    (owner decision record — 2026-07-28 (decision attribution at the gate)) — so that approach is
    near-empty today, which is the stated reason the owner deferred it.
    A closing sitting that adopts approaches inherits an approach with almost
    no data, and should say so rather than discover it.
