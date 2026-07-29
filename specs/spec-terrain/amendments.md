# SPEC-terrain — ratified amendments

Companion to `SPEC.md` (listed in its `companions:` frontmatter): the dated,
ratified amendment blockquotes of SPEC-terrain, relocated verbatim per the
2026-07-27 amendment-history-companion decision (#829). **Subsequent
amendments append here, newest-last** — `SPEC.md` carries the pointer, never
the blocks.

> **Amended 2026-07-24 (triage, #669)** per /triage-gh. Before a map candidate
> is offered, its usability is resolved **mechanically** against the target
> repo's declared sources — the hub lesson's Evidence pointers, its `projects:`
> attribution, and any `journey:` entry carrying the lesson's slug (#671) matched
> against the fact sheet / `resolve-writing-sources.py files` enumeration — with a
> **three-valued verdict** (deliberately the hub's own three-valued-absence
> lesson applied to itself, served: `consulted: hub@<private-pin>
> topics/knowledge-architecture.md:53` — present / absent-with-evidence /
> cannot-determine, collapsing to two-valued is the defect): **matched** (≥1
> evidence pointer resolves into declared sources → offer as draft-ready, evidence
> pre-located); **episodic-unrecorded** (the hub records a concrete episode but no
> declared source carries it → **emit a NEEDS-RECORDING task** naming the lesson
> slug, the episode, and the target repo/file — for tanuki, a `journey:` entry per
> #671 — never a silent drop; the unusable topic **is** the map's product, a named
> backfill worklist); **no-episode** (abstract lesson, no locatable episode →
> offerable only as owner-attributed framing, Story 17.1 attribution tier, stated
> as such at offer time). Silently filtering to `matched` is **rejected** — it
> reproduces the "constrained excludes silently" defect the owner ratified against
> (served: `topics/knowledge-architecture.md:57` — constrained excludes VISIBLY),
> hiding the unusable majority and starving the recording flywheel. The join
> **locates** evidence, it never **supplies** it: each verdict carries the
> pointers checked (audited), the offer is a proposal the owner ratifies (seam
> invariant 2, #670), and **no hub line ever becomes a SOURCE pointer** (invariant
> 1). It reuses harvest's shipped bounded pass — **not a second reader and not a
> second structure proposer** (served: `topics/articles.md:34`). **Legality
> precondition:** the map acting as a recommendation surface at all rests on the
> seam CAP-2 positive reframe (#670); the recording destination is the `journey:`
> element (#671). This amendment strains the seam's ≤2-topic read bound, which
> #670 deliberately does **not** widen — a separate decision (OQ, below).

> **Corrected 2026-07-26 (triage, #733).** The amendment above describes the
> join as matching **"the hub lesson's Evidence pointers"** against declared
> sources. **The seam does not serve those pointers to this consumer**, so that
> sentence describes a mechanism that cannot run here, and the correction is
> recorded rather than the wording quietly softened.
> **What is served:** one line per lesson, in the declared format
> `- [one_liner](lessons/<slug>.md) — <status> | tags: <t1, t2> | YYYY-MM-DD` —
> a one-liner, a slug, a status, tags, and a date. **No Evidence pointers.**
> Those live in the lesson **body**, which the seam does not serve; this spec
> already records that as OQ3, and the two facts were never read against each
> other.
> **What the verdict is therefore computed from:** the servable index line plus
> the target repo's declared-source enumeration. Where a lesson's evidence
> cannot be located because the pointers were never readable, the verdict is
> **`cannot-determine`**, and that leg is **contracted as designed behavior**,
> not an implementation shortfall — it is what an honest three-valued verdict
> returns when the source was not consulted, and it must never be rendered as
> "none". An absence is asserted only where it was established.
> **The ratified three-valued distinction is untouched.** `matched` /
> `episodic-unrecorded` / `no-episode` stay distinct because they route
> differently — an unrecorded episode is a recording gap that a backfill can
> discharge, and a no-episode lesson never can — and collapsing them would queue
> work that can never complete (owner decision record — 2026-07-25,
> three-valued join verdict ratified). This correction adds `cannot-determine`
> as an honest fourth outcome of the *lookup*, never as a merge of the three
> *verdicts*.
> **Not decided here:** whether to ask the seam to widen so the original
> mechanism becomes reachable. That is a hub-side ratification, contributions
> across the seam are proposals, and this spec does not spend a trigger by
> assuming the answer. Discovered by the per-paragraph join inspection (#725),
> whose report renders this leg as cannot-determine for exactly this reason.

> **Amended 2026-07-26 (triage, #726)** per /triage-gh. The mechanism is
> **renamed Terrain**, and four owner-ratified design stances are recorded.
> The rename is **owner-facing only**, by selection: see the machine-key clause
> below for what it deliberately does not touch.
>
> **Why the name changes.** "Topic" already carries a different definition in
> Tsurezure — the hub's per-realm digest files (`topics/*.md`) — and the hub's
> own internal mechanism is named **Gloss**. The map's artifacts had already
> drifted to the new word on their own: the View titles itself "the terrain"
> and describes itself in those terms throughout
> (`scripts/topic-map-directions.py:794,817,757`). The harm the rename fixes is
> a **collision in reading**, so the rename cuts exactly where reading happens.
>
> **1. Provisional framing.** Terrain is a mechanism for **surveying the Gloss
> of hub Lessons** — an overview of the article ideas represented in Tsurezure.
> When the ideas Terrain presents diverge from the owner's understanding of the
> hub Lessons, **Terrain's behavior is revised case by case**: a divergence is a
> Terrain defect signal, not a hub defect signal, by default. This is the same
> direction the CAP-2 derivation clause already takes for cluster naming ("a
> declared name a cluster disagrees with is the tool's defect, never the repo's")
> generalized from wording to the whole survey.
>
> **2. Evidence-independence.** Terrain is independent of Evidence: **Evidence
> determines whether a selected idea is currently writable, never whether it
> appears on Terrain.** An idea with insufficient Evidence still appears — that
> appearance is precisely how Terrain exposes architectural deficiencies (an
> idea the owner wants but cannot write). This **confirms and names** the
> three-valued-verdict / no-silent-filtering amendment above (2026-07-24,
> #669): matched / episodic-unrecorded / no-episode all surface, and
> **writability is a per-idea verdict attached at selection, never a display
> filter**. Nothing in the 2026-07-24 mechanism changes; it gains a name for the
> property it was already protecting.
>
> **3. Cluster representation is provisional — under dogfood.** The
> subtopic-cluster unit ships as designed (CAP-2, OQ1 closed 2026-07-23) and is
> explicitly provisional. **Named risk:** material the owner considers suitable
> for several separate articles collapsing into one large cluster — if that
> happens, Tsurezure keeps accumulating history without producing writable
> article ideas. If dogfooding confirms it, the unit may shift toward a
> **Lesson-and-Journey-centered model** (elements primary, clusters derived)
> rather than cluster-centered.
> **Tripwire (one occurrence):** a cluster the owner splits into ≥2 article
> ideas at selection time. Occurrences are recorded in
> `docs/dogfood-findings.md`, each naming the cluster and the ideas it was split
> into.
> **Partly discharged already, and stated so rather than re-promised:** OQ4's
> resolution (below) gives the map a **second projection — typed elements
> beside the subtopic cluster, not replacing it** — so the element layer is
> already first-class for the servable types (`decision`, `reversal`). The
> design obligation this stance adds is only that future work keep it that way,
> so the pivot stays a re-projection rather than a rebuild.
>
> **4. Gap exposure is a feature.** The NEEDS-RECORDING worklist and the
> writability verdicts are **products, not noise**. Terrain's exposure of the
> gap between the article ideas the owner wants and the Lessons and Journeys
> actually available is a stated strength, and no future change may treat that
> output as an error condition to be suppressed.
>
> **Machine keys are out of scope, by selection (#726, Alternative A).** The
> rename cuts at the boundary between what a *reader* reads and what a
> *machine* keys on. Owner-facing surfaces take the new name: this spec's id and
> directory, the skill's name and invocation wording, the View's header, and
> owner-facing prose. The following are **internal machine keys with no
> owner-facing reading and are deliberately unchanged** — script filenames
> (`scripts/topic-map.py`, `scripts/topic-map-directions.py`), the depth-
> threshold config (`config/topic-depth-thresholds.yaml`), the CAP-3 fixed View
> path and its constants (`<destination-repo>/topic-map/<repo-key>/topic-map-view.md`,
> `scripts/resolve-paths.py:157-158,189-191`), the `topic-map-view` subcommand
> name, and the map's internal `topic`/`subtopic` grouping keys. This **extends
> the existing owner-readable-wording clause** (CAP-2, "'Good' governs the
> WORDING too") from cluster names to the whole naming surface: the clause
> already held that an internal placeholder reaching owner-facing wording is the
> tool's defect — this states the converse, that owner-facing vocabulary is not
> owed to a path. Where an internal `topic` grouping key remains visible, its
> wording must not be readable as a Tsurezure Topic.
> **Consequence, stated so it is not rediscovered:** the CAP-3 View path is a
> published-artifact location with a live file today
> (`<articles>/topic-map/<repo-key>/topic-map-view.md`) and no discovery
> mechanism pointing at any other name. A future change renaming it must supply
> the migration rather than assume regeneration covers it.
> **Forward-only.** Closed stories and merged issue titles keep their original
> wording; nothing is retrofitted.
> **Consult:** `policy_lookup` returned no served position on spec-rename scope
> or on forward-only versus retrofit sweeps (`coverage: low`) — this decision is
> the owner's, taken without a discriminating served line.

> **Amended 2026-07-27 (#799) — the stance-3 tripwire FIRED; the pivot
> executes.** Fired by **direct owner report**, at a severity beyond the
> recorded tripwire: the shipped flow announced it would cluster and placed
> almost the whole Lesson/Journey corpus into **one cluster**, so the corpus
> yielded exactly one article idea — and the owner could not split it, because
> **selection at the element level did not exist as a surface**. The tripwire
> was written for a cluster split into ≥2 ideas at selection time; what was
> observed was a terrain with no selection to split. Two ratified stances were
> additionally violated in shipped behavior: the flow refused to draft when
> Evidence was judged missing (stance 2), and with no element surface the
> owner could never reach the place where a recording gap would be visible, so
> the NEEDS-RECORDING product never materialized (stance 4). Owner ruling: "a
> mechanism is not correct merely because it behaves according to its own
> internal rules — if the user experience is bad, it is a mechanism built on
> an incorrect design."
>
> **1. Elements are the PRIMARY selection unit.** The terrain lists **typed
> elements — hub Lessons and Journeys — as the primary, individually
> selectable article-idea units**: N elements are N distinct selectable ideas,
> in their own index namespaces (`L<n>` lessons, `J<n>` journey renderings,
> `E<topic>.<n>` decisions/reversals — stable within a pin, pin mismatch
> refused, exactly as `T<topic>.<subtopic>`). This supersedes CAP-2's "the
> subtopic cluster remains the map's primary unit" sentence. The **cluster is
> demoted to a derived, secondary grouping**: it stays on the View below the
> elements, labeled as derived, and **clusters never gate what is selectable**
> — the flow no longer opens by clustering. This is the re-projection stance 3
> pre-arranged (elements were already first-class), not a rebuild; CAP-1's
> derived-never-stored properties are untouched.
>
> **2. Each element slot quotes the Gloss.** The slot's text is the served
> `gloss:` / `journey_gloss:` rendering — the plain-register field the hub
> ratifies at its distill gate (the hub's gloss contract; the ratified work
> order carried on #726, step 3 — hub side complete, provenance private) —
> reached through the seam's two-tier `gloss_index`
> surface, **never the recall one-liner** (the pre-ratified "exactly one
> amendment": quote the field instead of the one-liner). The one-liner remains
> identification. Where the rendering is not served — the tool absent from the
> deployed gateway, the surface undeclared in operator config, or no entry for
> the lesson — the slot **discloses the absence with its reason**; nothing is
> substituted for a ratified rendering, and serving it is a hub-side act,
> never a consumer-side workaround.
>
> **3. Evidence-independence is enforced end to end.** Every element carries
> its three-valued writability verdict **visibly on its row** — matched (with
> the evidence pointers checked) / episodic-unrecorded / no-episode — plus
> `cannot-determine` as the lookup's honest fourth outcome where no join key
> exists (decision/reversal elements). Verdicts are **surfacing, never
> filters, and never refusals**: an unmatched element stays selectable, and
> selecting one yields the **gap disclosure plus a NEEDS-RECORDING tracking
> artifact in the target repo** (an Issue, or an append under a
> `## NEEDS-RECORDING` heading in the declared journey doc — the map names the
> target on `recording_target`) while the draft **proceeds**. `no-episode`
> ideas are offerable on the owner-attributed framing tier (a framing
> contribution, not sourced claims), stated as such. The do-not-write-on-
> missing-Evidence behavior is removed and may not return: there is no refusal
> path on evidence anywhere in this surface.
>
> **Unchanged, stated so it is not re-litigated:** one screen, capped and
> ranked, candidate directions plus free-form every time; the chosen direction
> hands off to the existing stage-0 `--brief` path as brief text only (no
> second structure proposer); all intermediates resolve through the path
> resolver into the run workspace; the View is regenerated whole and never
> read back; no cluster or topic name is invented — an unnamed grouping is
> described by its contents; coverage and bounds stay disclosed per family
> (the gloss surface is a declared family with the same
> declared-but-not-enumerated disclosure shape).
> **Forward-only.** Closed stories keep their wording; the hub-side companion
> record (the ratification-seam half of the tripwire firing) is staged in the
> hub's own intake, proposal-only, per the dogfood-findings-venue rule —
> mechanism public, provenance private.

> **Amended 2026-07-27 (triage, #802) — the View is the header plus Candidate
> Directions, and nothing else.** Owner review of a 2,511-line generated view
> (pinned `b574b37`): roughly **2,300 lines** after Candidate Directions —
> "The terrain at a glance", "Maintenance", "Diagnostics" — served no function
> the owner could identify ("the sections contained information whose purpose
> was impossible to understand"), making them pure size and token cost. Two
> clauses were holding them in place and both are amended above rather than
> worked around: CAP-2's depth answerability, which pointed *at the
> per-subtopic detail* and now points at the header's terrain-size line; and
> CAP-4's disclosure duty, which is satisfied by a **line** and never by a
> section. **Removal is of the emitting code paths, not just the rendering**,
> so the assembly cost disappears with the output — a section deleted at
> render time is still paid for. This is cheap to reverse and cheap to
> supersede: the View is explicitly "a RENDERING … fully regenerated every
> invocation and NEVER read back by any code path. Deleting it loses nothing"
> (`scripts/topic-map-directions.py:894-898`). **Scope stated:** this decides
> what the View *contains* under the current selection model; it does not
> decide the model. The clustering-removal and Topic-first navigation proposal
> (#803) is **escalated to its own spec session** and may supersede this
> amendment wholesale — accepted deliberately, because the dead sections cost
> tokens on every invocation until then and die under every candidate outcome
> of that session.

> **Amended 2026-07-27 (spec sitting, #803) — clustering is removed; Terrain
> navigates in two screens over the SERVED GLOSS TAG.** The second dogfood run
> spent its whole budget to produce one usable line while the host-sources
> family emitted ~190 junk directions, so the subtopic cluster is **abandoned,
> not tuned**. The replacement navigates and never filters: **Screen 1** is a
> deterministic listing of the axis members with an element count each;
> **Screen 2** is ALL of the selected member's Lessons and Journeys arranged
> into presentation-only sections. Two mechanically checkable invariants
> replace the tuning: **sectioning is a permutation** (every element appears
> exactly once; count in == count out asserted by a check script, so
> information loss is structurally impossible and the worst case is a badly
> grouped but complete list), and **sections are presentation-only** (a title
> and nothing else — they gate nothing, so a wrong grouping costs zero).
>
> **The axis is the served gloss tag, NOT the hub Topic — the proposal's
> premise was disproved at this sitting.** #803 asserted that "Topics are the
> pre-existing, human-maintained structure with deterministic membership; the
> served gloss index is already per-tag, so this screen is a cheap
> deterministic listing." Consulting the surface refutes it: the hub carries
> **9 topic files** and **14 gloss shard tags**, and **only 3 names occur in
> both**; 6 of the 9 topics have no lessons gloss shard at all, and the
> decisions shards cover 2 of 9. **No served surface maps a Lesson to a
> Topic.** Deterministic membership therefore holds for the *tag* and not for
> the *Topic*, and the two are different views of the corpus rather than one
> renamed. Recorded so the premise is not reconstructed:
> `owner decision record — 2026-07-27 (terrain axis, sections, depth)`.
>
> **Topic-as-axis stays open, and is an UPSTREAM ask.** A consumer-side
> tag→Topic mapping is **not** the fallback: consumer-side re-expression of
> ratified hub lines is Declined upstream, and CAP-4 already states that
> widening the served scope "is a hub-side ratification, never a map-side
> workaround". So Topic navigation waits on a served Lesson→Topic membership
> surface; see OQ8.
>
> **Depth demotes to a count (Fork B).** The depth estimate and the
> evidence-density signal were derived *per subtopic*, and the subtopic unit is
> gone — so they retire with it, along with their thresholds. What survives is
> a bare **element count per axis member on Screen 1**, a screen-1 affordance
> for choosing where to look, never a direction line and never a gate.
>
> **The View survives, re-based (Fork C).** CAP-3's size switch is retained but
> its budget is measured **per axis member** rather than over the whole
> terrain: two-screen navigation shrinks the overload condition without
> removing it, since one tag can still hold many elements. The #802 amendment
> above therefore stands and its story remains in scope.
>
> **Host sources leave the candidate set entirely** — article material is
> Lessons and Journeys. **Journeys degrade with a named disclosure** until the
> hub's Journey-addressability issue lands (upstream, open at this sitting):
> journey shard tags are shadowed by same-named lesson shards, so a run that
> cannot address them says so on the screen rather than silently omitting them.
> Free-form answer, element-level selection, and the hand-off to the existing
> stage-0 `--brief` path are all unchanged — there is still no second proposer.

> **RESOLVED 2026-07-27 (upstream gate, same day) — the axis suspension below
> is LIFTED: the upstream ratified the SERVED TAG VOCABULARY as Screen 1's
> axis.** The conflict this amendment records was surfaced to the upstream's
> own gate through its intake, and the gate answered: the axis members are the
> served tags (14 today); building a Lesson→Topic join to rescue the
> "Topic-first" wording is **Declined**; and the UI word "Topic" is **retired
> for the axis** to end the collision with the upstream's own topic files. The
> consumer measured the fact; the upstream re-made the decision — per-axis
> precedence working as intended. Three further rulings land with it, binding
> on the held stories: **no within-axis cap** — a large member (measured: five
> members at 40–53 entries) is served WHOLE with its count disclosed, and the
> future remedy if one is ever needed is a second navigation step, not a cap
> and not a re-tag; **presentation-only is re-worded** — a section carries
> **no selection authority** (labels, counts and annotations are fine; only
> gating is forbidden — "a title and nothing else" was mechanism-as-rule);
> and the **three-valued writability verdict is preserved** under the
> depth/density deletion. The tag-axis amendment above therefore resumes as
> written, subject to those wordings. OQ8 is CLOSED. Recorded:
> `owner decision record — 2026-07-27 (terrain axis resolved: served tags;
> no cap; no-selection-authority)`.

> **Amended 2026-07-27 (re-triage of #809, later the same day) — the AXIS
> decision above is SUSPENDED** *(suspension lifted the same day — see the
> resolution immediately above)* **, and the cross-topic combination move
> SURVIVES the cluster removal.** Two corrections to the sitting recorded immediately
> above, both found by consulting the served surface rather than by reasoning
> from this repository.
>
> **1. The axis is unresolved, and this spec says so rather than picking.** The
> amendment above chose the served gloss tag as Screen 1's axis, on a verified
> fact that still stands: there is **no served Lesson→Topic membership**, the
> two vocabularies share only 3 names, and 6 of 9 topics carry no lessons
> shard. Later the same day the upstream surface was found to have **ratified
> "Topic-first navigation" by name**, together with the abandonment of the
> cluster unit. Both cannot be honoured at once: the upstream verdict takes
> precedence, and it is **not implementable by a consumer** — ratifying
> Topic-first does not bring a membership surface into existence, and both
> escape routes are already closed (a consumer-side tag→Topic mapping is
> Declined upstream; CAP-4 forbids a map-side workaround). **So neither is
> adopted here.** The conflict is recorded as a conflict — per the standing
> rule that a later-dated upstream verdict wins **and the conflict is a finding
> to surface, never to resolve silently** — and the axis is decided in its own
> sitting, against the upstream, not inside this spec. **OQ8 is therefore no
> longer a footnote: it is the blocking item.** Until it closes, Screen 1's
> axis is **undecided**, and any story that would encode an axis is held.
> Recorded: `owner decision record — 2026-07-27 (terrain axis suspended;
> combinations re-based)`.
>
> **CORRECTED 2026-07-27 (later the same day, #809) — clause 2 below rested on
> a FALSE PREMISE, and the combination move is DEFERRED behind OQ3 rather than
> re-based.** The clause states that "Strands carry an `evidence` cite list, so
> the rule transfers to a different field", marked verified in code. What was
> verified is that the FIELD exists; what it CONTAINS was not checked. A
> Strand's evidence is its own index-line cite — `lesson_item` says so outright,
> "Its own index line is its evidence pointer" — so pairing on shared sources
> makes every cross-topic pair share `LESSONS.md`. Measured on three unrelated
> lessons in three distinct topics: **two combinations proposed, both with axis
> `LESSONS.md`**, growing quadratically. That is the same junk class the cluster
> removal exists to delete.
> **What is decided:** the CAP-3 promise STANDS and the implementation does
> not. A Strand carries no subject-matter evidence because **lesson bodies are
> unservable — OQ3**, and the Evidence pointers that would name a shared
> subject never reach this consumer. So the move is deferred behind that
> already-recorded, observable condition rather than retired on a temporary
> limitation. **Reopen trigger:** Strands carry evidence pointers naming
> something other than the surface they were read from — i.e. OQ3 closes, or
> the seam begins serving per-Lesson Evidence. Until then no combination is
> derived, and CAP-3's promise is explicitly undelivered rather than quietly
> broken. Pairing on tags or shard membership instead was offered and declined:
> a shared tag is not a shared subject (`workflow` alone has 53 members), and
> CAP-3's own rule is that "a combination with nothing shared is a hunch, and a
> hunch is the owner's to voice at the free-form entry, not the machine's to
> propose."
> *(Method note: the error was certifying a claim as code-verified after reading
> a field's existence rather than its contents. "Verified in code" means the
> value was read.)*
>
> **2. Cross-topic combinations are re-based, not retired.** *(SUPERSEDED by
> the correction immediately above — retained unstruck because its reasoning
> about WHY the move should survive the cluster removal is confirmed, not
> reversed; only the mechanism was wrong.)* Removing the
> subtopic unit would have deleted the combination move as a side effect —
> `candidates()` derives combinations *only* from subtopic pairs — and CAP-3
> calls that move "the 'connect these topics along this axis' move that is the
> reason the map exists". Nothing in the dogfood evidence rejected it: the runs
> rejected **clustering**, and the combination move was collateral. **It
> survives, re-based onto the selection unit**: two units from different axis
> members that **share evidence** propose a combination, on the same rule as
> today — a shared evidence source names the axis, and a pair with nothing
> shared is a hunch the owner may voice at free-form and the machine may not
> propose. Feasibility is verified, not assumed: the pairing rule reads shared
> evidence-source stems, and the units carry an `evidence` cite list, so the
> rule transfers to a different field. This is a derivation change, not a
> rename. *(No served position exists on the combination move — consulted
> 2026-07-27, miss. This is a consumer decision and is recorded as one.)*
>
> **3. Vocabulary: the unit is a STRAND, and `Seed` is rejected.** The upstream
> gate of 2026-07-27 ratified **Strand** (one Lesson or Journey selected as
> material; the selectable unit) and **Thesis**, and **rejected `Seed`** on a
> two-way name collision. #803's body and the story text derived from it say
> "Seeds"; that wording is superseded. This spec uses **Strand** for the
> selectable unit from here.

> **Amended 2026-07-27 (spec sitting, #844) — Screen 2 Strands gain
> deterministic context fields; section background prose is pre-ratified or
> absent.** The owner's cold-read of a member listing found adjacent Strands
> with "no visible relationship, or any relationship that exists is enclosed
> in machine-side reasoning so completely that the user cannot perceive it",
> and proposed section-level shared-background prose with render-time LLM
> composition explicitly on the table (cost grounds set aside). The fork was
> half-covered: the served surface had already superseded consumer render-time
> re-expression of a *single* element ("an UNRATIFIED machine paraphrase of
> ratified policy") and declined interpretation-at-consult because a live
> output cannot be pinned — but carried no position on *cross-Strand*
> background narrative (owner decision record — 2026-07-27 (triage #844:
> consumer render-time re-expression superseded; interpretation-at-consult
> declined); the full pin is in the private provenance store). The owner
> resolved the uncovered half at this sitting's single pause:
>
> **1. Per-Strand context fields, deterministic, now.** Each Strand line on
> Screen 2 carries the Topics it belongs to beyond the member's own tag, its
> origin, and whether it holds both a claim and its reasoning — all read from
> served artifacts or the map. This is presentation within CAP-3's
> owner-readable rule; sectioning stays a permutation and sections still gate
> nothing.
>
> **2. Section background prose only as a served, pre-ratified rendering —
> held, not refused.** The section key is stable (member tag + co-tag), so a
> background rendering *is* ratifiable in advance, which is the served
> surface's adopted pattern for exactly this competence class. Until the hub
> serves such an artifact class (its counterpart proposal is staged in the
> hub's own intake), sections remain title-only. The clause activates when
> the artifact class is served; it is not re-decided then. **Reopen trigger
> for the rejected arm:** if the pre-ratified form proves untrue of the
> Strands that land in a section — the co-tag key too crude for one written
> background to hold — that is the served surface's own reopen condition (a
> question class no pre-ratifiable artifact answers), and render-time
> composition returns as a live alternative rather than a settled refusal.
>
> The no-LLM clause is untouched: it governed selection before and after;
> narration stays out of the render loop by construction, not by that clause.

> **Amended 2026-07-27 (triage, #850, coupled with #844) — the hub's
> cold-reader verdicts land: the join is the defect, identifiers are
> kind-qualified, the composition reopen is taken up, and two owner rulings
> enter CAP-2.** The hub ratified four verdicts over the same cold-reader
> review that produced #841–#844 (owner decision record — 2026-07-27 (#850
> D1–D4); the full pin is in the private provenance store; the issue quotes
> them verbatim under the ratified-rendering rule).
>
> **1. D1 — the raw-prose defect is a consumer JOIN failure.** The ratified
> renderings exist (111/111 lessons, 102/104 journey-bearing, and served
> decision shards); `topic-map.py` simply has no code path reading the
> decisions shards, and the Journey renderings were shadowed by a basename
> collision fixed upstream. Story 20.22 wires the join. The #848 disclosure
> shape remains the fallback surface — a surface that falls back to source
> must say so at the point of substitution.
>
> **2. D2 — kind-qualified identifiers: already discharged.** The obligation
> (every identifier kind-qualified; the surface declares its kinds) shipped
> in Story 20.20/#848 — `L`/`J`/`E` prefixes plus the row-kind legend on both
> reading surfaces. No story is decomposed; recorded so the verdict meets its
> evidence rather than an unexplained gap.
>
> **3. D3 — the pre-ratified-or-absent hold is SUPERSEDED, not activated.**
> The earlier same-day clause held sections title-only until the hub served a
> pre-ratified background artifact class. The hub answered differently: it
> recorded that the reopen's ground (cost) was withdrawn by the owner and the
> render-time composition is admissible — a writing-assistant decision, which
> this amendment makes: composed section background is adopted under the
> hub-hardened invariants (permutation extends to composed sections;
> background never substitutes for a Strand's served text; machine-composed
> marking). Story 20.24 (umbrella #844) delivers it — #844's twice-stated
> ask, so that umbrella closes on delivery, not on this text.
> **Carried question (cannot-determine, pending at the hub):** whether
> "sections-by-Topic" means the served tag vocabulary or a `topics/*.md`
> join — staged hub-side; Story 20.24 carries it as a story question and
> composes against the served tag key until answered.
>
> **4. D4 — two owner rulings enter CAP-2 verbatim-scoped:** a missing Gloss
> rendering is an abnormal condition to fix immediately (Story 20.22's
> disclosure shape), and no direct parent section holds more than 20% of the
> member's Strands (Story 20.23 implements the subdivision; the existing
> co-tag grouping rule stays free to change — the contract is the bound, not
> the grouping).

> **Amended 2026-07-29 (spec sitting, #884)** per tsurezure-gateway#76 (ratified
> 2026-07-29; gateway PR #77 merged, hub manifest product-lab#112 closed — the
> served element manifest carries 117 lesson, 109 journey, and 87 decision
> records). **CAP-1's hub-gloss family acquires Strand MEMBERSHIP from the
> served element manifest** (`element_survey` through the seam's new `elements`
> subcommand): which Strands exist, their tags, and which carry a Journey arc
> are read from labelled record fields — the tier-1 `GLOSS_LINE` markdown parse
> is **retired as the enumeration source** and retained solely as the
> headline-TEXT join (by slug; the ratified rendering is still quoted verbatim,
> and the manifest deliberately embeds no bodies). The tier-1 journey *marker*
> hands its discovery role to the journey records' kind-qualified rendering
> pointers; the tagged `journeys/<tag>` read itself is unchanged (#871: arcs
> attach to their lessons, never independently selectable — record-kind
> `journey` does not create a selectable unit). **Three invariants become
> mechanically checkable and are CHECKED per run:** composed-Strand count
> equals lesson-record count (count-in = count-out against a served
> denominator); journey attachment equals journey-record count; and a record
> with no tier-1 line or a tier-1 line with no record is a **finding in the
> disclosure, never silently resolved in either direction** (hub rule,
> product-lab#98). Decisions are NOT widened: the per-topic thread-line join
> (Story 20.22) stands, and the manifest's decision records are not enumerated
> by this amendment — Strand is the selection unit. Records unavailable (older
> gateway, undeclared manifest) degrades to the tier-1 acquisition **with the
> substitution disclosed at the point it happens** (rule 1 above), never
> silently.
