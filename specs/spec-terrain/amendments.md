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
> 2026-07-29; the upstream gateway change merged and the hub-side manifest
> carrier closed — the
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
> disclosure, never silently resolved in either direction** (hub rule —
> owner decision record — 2026-07-29 (status conflicts are surfaced)). Decisions are NOT widened: the per-topic thread-line join
> (Story 20.22) stands, and the manifest's decision records are not enumerated
> by this amendment — Strand is the selection unit. Records unavailable (older
> gateway, undeclared manifest) degrades to the tier-1 acquisition **with the
> substitution disclosed at the point it happens** (rule 1 above), never
> silently.

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
