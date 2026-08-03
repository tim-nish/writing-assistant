# SPEC-writing-assistant — ratified amendments, 2026-08-01 onward

Companion to `SPEC.md`: the dated, ratified amendment blockquotes of this
spec. **New amendments append here, newest-last** — `SPEC.md` carries the
pointer, never the blocks.

Amendments dated **2026-07-24 -> 2026-08-01** live in `amendments-2026-07-24--2026-08-01.md`, relocated verbatim on
2026-08-01 when this file crossed the era-split threshold declared in
`scripts/check-skill-budget.sh`. That file is **closed**; nothing appends to it.

The cut is **mechanical and is not a decision** (Story 20.88, #1046): the
threshold lives in the check, which is the single enforcement copy, so no
byte figure appears here or in any spec. Ratified text is never compacted
and no already-relocated text moves — the rule is prospective.

> **Amended 2026-08-02 (triage, #1206) — a closed set overflowing the control capacity by at most two renders as a SELECTION with a disclosed overflow, and permanent block form stops being the fate of a five-member ratified set.** The #1102 amendment fixed the host control's capacity at 2–4 options and declared `control: "block"` the conforming form above it — written for the ≈50-Strand terrain listing, and silently claiming the intent gate, whose ratified closed set is exactly five. The pipeline's most central closed choice was therefore **permanently** above capacity by one: block form was not a degraded path there but the only path, on every run, by construction — and the owner's standing ruling is that rule-conformant but bad-for-the-user is incorrect design. **The contract:** a payload whose choice count exceeds `CONTROL_CAPACITY` by **at most two** declares `control: "selection"` and carries `render.overflow: [<labels>]` — the top-ranked members fill the control with the recommendation first, and every overflow member is **named in the question text** and reachable through the control's built-in free-text entry: disclosed, never hidden. Above that margin, block form stands unchanged — the ≈50-Strand case that motivated it is not reopened. The carrier check extends from existence to this form: `check-gate-payload-carrier.sh` asserts `overflow` is declared only within the margin, that a declared overflow's members are each named in the question text, and that the recommendation still leads. Rank is not pre-selection, and the overflow member is a full citizen of the choice — only its entry path differs. **What would overturn this** is the observation the gate itself named: an owner repeatedly failing to find the overflow member, which would show disclosure-by-text is hiding in practice; the remaining move is the two-render split declined here for spending a second ask on a single-axis choice. Delivery: story 20.142.

> **Amended 2026-08-02 (triage, #1207) — a brief-carrying stage-0 entry resumes only a run minted from the SAME brief; any other in-progress run is skipped fresh, and the after-the-act resume ask on the handoff path disappears with the act it confirmed.** On 2026-08-01 the terrain handoff completed with a freshly adopted brief, and workspace autostart resumed a 5h03m-old run still at `harvest` carrying a *different* thesis — the resume-confirmation gate then fired **after** the resume, its own `where` text admitting the act had already happened. Two defects, one cause: the ratified automatic-resume default (`skills/draft-article/stages/stage0.md`) was designed for a **cold** `/draft-article` invocation, and the handoff path inherited it unexamined — but a terrain-originated entry *by construction* carries a just-adopted brief, so auto-resuming any pre-existing run on that path discards the sitting's own output in favor of stale state. **The contract:** on an invocation carrying `--brief`, autostart resumes the newest in-progress run **only when that run was minted from the same brief** (brief identity, not text similarity — the recorded brief artifact/pin); otherwise it mints fresh, returning the skipped run as `fresh_skipped` with its `fresh_note`, nothing deleted — exactly the existing `--fresh` semantics, applied by data rather than by owner keystroke. The same-brief branch is what keeps a turn-ceiling casualty of the handoff's own run resumable, which the blanket-fresh alternative would have broken. **Cold invocations are untouched:** resumption there stays automatic-not-opt-in with the Story 19.10 turn-one disclosure; nothing here adds a gate, because the right answer on the handoff path is derivable from data and a recurring ask over a derivable answer is the shape the gate budget refuses. Delivery: story 20.143.

> **Amended 2026-08-02 (triage, #1182/#1097/#1185/#1209) — HARVEST IS RETIRED: stage 1 becomes `probe` (a feasibility check producing no fact sheet), per-claim `examine` runs once the structure exists, the sources gate retires with the stage that owed it, and which repositories may be examined is DERIVED from the selected Strands' `projects:` — never composed at a gate.** The governing finding: harvest ran at stage 1 while the article's structure is fixed at stage 3, so the read had to anticipate every question a not-yet-existing thesis would raise — retrieval against an unstated query, 358 files opened on the 2026-08-01 run to serve a thesis about five named mechanisms. The inverse direction is the one the model is good at: given a concrete claim, judge whether it holds and where the evidence sits. That position is ratified upstream (*owner decision record — 2026-08-01 (retrieval direction: thesis-first examination)*): read a corpus to test a stated claim, never to gather against an unstated one — pre-extraction has no denominator and no instrument can grade it, while query-time reading is scoreable per claim. Its admissibility condition travels with it: thesis-first reading is admissible exactly where a **separate surprise channel** exists, and here the thesis originates in distilled hub material with the terrain listing as the surprise channel — the repository was never the discovery channel. The prior earning trigger (a side-by-side worked example) is **rescinded by owner ruling 2026-08-01**: the fact sheet has never grounded an article claim in any dogfood run, the trigger demanded a comparison whose harvest side is unscoreable by the ratified reasoning above, and it was structurally self-blocking. **The stage contract:** `probe` (stage 1) asks whether this repository can ground anything for this brief at all and returns a handful of anchors plus a verdict — a doomed article still dies early, at a fraction of harvest's cost, and **no fact sheet exists anywhere in the pipeline**. `examine` (stage 3+) issues one question per claim needing repository grounding: claim in, pinned material out, the pin born with the claim rather than two stages before it — the model judges, the tool never does (`scripts/examine.py`, released from its untracked hold, is the adopted substrate; its known-noisy OR-matching term derivation is a design input for delivery, not a gate in front of it). Every examination **reports its coverage**: what it consulted, what it could not reach, and why — an empty result from an unreachable source is a different finding from an empty result from a read source. The typed time-axis source rule (#1184, already ratified above) is what examine reads through. **Scope is derived, not chosen (#1097, #1185):** the brief carries `harvest_scope` as the **union of the selected Strands' `projects:`**, now served by the element manifest — the `served: false` branch and its `not_served_reason` are removed (the 2026-08-01 brief carried a reason string the pinned manifest falsifies, #1208's second defect, which dies with the branch). For a selected Strand S, the repositories that may be examined for S are exactly `S.projects`: a union of one repo means the scope question is not asked; an empty `projects:` means the Strand is hub-only material — its served arc is what it has, stated plainly, never a work item; examining S against a repository outside `S.projects` is **refused, not searched** — grounding a claim in a repository the experience did not happen in is a false attribution, the read-side counterpart of the hub's write-side deny rule. **A non-repository value is a scope claim, not an attribution** (*owner decision record — 2026-07-28 (projects: axis; portfolio-wide rider)*): `portfolio-wide` renders as an explicit named section — never a silent drop, or completeness breaks — and is not a set of repositories; the 16 Strands carrying it alone are thereby distinguishable from the 4 carrying nothing. **Known limit, carried rather than papered over:** the manifest does not declare which `projects:` values are repositories, so clause-level scope cannot be fully computed from this surface — the discriminator is a hub-side obligation, requested as a carrier this sitting and **never re-derived here**; the non-repo branch beyond the served `portfolio-wide` case parks behind that carrier. **The sources gate retires with harvest (#1209):** its 2026-08-01 defect — recommending "all declared sources" (423 files, 78% code) to an episode-claims article whose members all carried served arcs — is not fixed at the gate, because the gate's own premise (a human-supplied enumeration) is the circularity the upstream ruling names; the human supplies a region at the brief, and the phase does the enumerating, per claim. Open question carried to delivery, not decided here: whether the article floor's "≥1 sourced or derived claim" changes shape when every claim is examined individually. Delivery: stories 20.144 (scope emission, #1097), 20.145 (oracle binding, #1185), 20.146 (probe), 20.147 (examine + gate retirement).

> **Amended 2026-08-02 (triage, #1221/#1222/#1225) — the 2026-07-28 ruling that the conversation layer CANNOT get a mechanical carrier inside the harness is BOUNDED, not reversed: it was true of a harness with no hooks configured, and the harness configuration is a file in this repository.** SPEC.md's owner-facing proposal contract (`SPEC.md:76`) records the ruling and its reason — *"that layer here is the agent's own composition step, **which this product does not own** … The carrier therefore goes at the last boundary this repository controls: the composed artifact."* The governing lesson agrees on the rule and is silent on where the boundary actually falls: *"when that layer belongs to another system, the carrier goes at the last boundary you control, with any gate upstream of it counting as ergonomics rather than control"* (*(owner decision record — 2026-07-26 (carry a rule at its violation layer))*). **The premise that was never checked is the factual one.** `.claude/settings.json` does not exist in this repository — verified at triage, no hooks are configured at all — so the 2026-07-28 conclusion was drawn over a harness configured with no observation point, and it correctly described *that* harness. A Claude Code Stop hook runs outside the model, observes the tool-call stream, and is configured by a file this repository owns and commits. The last boundary this repository controls is therefore the harness configuration, one layer further out than the ruling assumed, and #1221's audit of twelve prior cycles is the evidence that everything inside that boundary has now been tried.
>
> **The grant is narrow and its narrowness is the contract.** The hook asserts an **absence**: for a turn at which a declared gate was due, an `AskUserQuestion` tool-call event exists for that gate's payload. It **never reads reply prose**, so nothing here depends on classifying free text, and the standing reopen trigger #1102 recorded — *a within-capacity payload declaring `control: "selection"` reaching the owner as prose* — is retained verbatim and is **not** discharged by this amendment. What the hook removes is the remaining way to reach the owner without leaving evidence; it does not force the rendering step to call the control, and no clause here claims it does. **`gate-inventory.py --audit` stops taking `reached` self-reported by its caller** (`scripts/gate-inventory.py:13-27`, read at triage): a gate is `presented` when the transcript carries the tool-call, never when the payload file exists.
>
> **A premise of #1221 is falsified and is recorded rather than quietly dropped.** Its clause 3 asks that the >4-option capacity lockout be retired so the five-label intent gate can reach the UI, stating story 20.142's remedy *"appears uncommitted as of 2026-08-02"*. It is committed — `91a6884` (#1206), `scripts/draft_gates.py:60-144`, where `CONTROL_CAPACITY = 4`, `OVERFLOW_MARGIN` admits a small overflow, and `control = "selection" if n <= CONTROL_CAPACITY + OVERFLOW_MARGIN else "block"`. The intent gate is already reachable. Clause 3 is discharged and is **out of scope**; clauses 1–2 are what this amendment grants.
>
> **The two payload-layer contracts land beside it, on the CONSTRAIN side of the register clause's own ordering, and they are not gated on the hook.** **Ask decidability (#1222):** every owner-facing ask must be answerable with zero pipeline knowledge — naming the concrete thing being decided rather than an internal referent, carrying the evidence the decision turns on or stating explicitly that the system lacks it, and offering a recommendation with grounds or ranked alternatives with trade-offs, per the owner's stated ladder; a parameter the system can derive is never asked as a blank (the commit-range ask is the type case, and the Strands' own date ranges are the derivation); a stage transition is a Yes/No continuation with a plain statement of what happens next, never a stage name. This binds **ask content**, which the gate-item content-grounding clause already binds for *premises* and the owner-surface register clause binds for *register* — this is the third axis, **decidability**, and it is checkable over the composed payload, so it does not touch the relay layer #1176 bounds. The measured cost of its absence is the record: an abandoned run whose `answers.json` carries an editorial anchor, a falsifier and a depth decision that encode escape-clicks, consumed downstream as authoritative. **Owner-surface information budget (#1225):** an owner-facing turn carries at most one status line plus the decision payload; everything else — coverage tables, pin inventories, contract-mismatch narration, stage bookkeeping — goes to the run workspace, referenced by one pointer line, with a debug channel opt-in and off by default. This is a **default-deny on turn content**, deliberately not a list of suppressed items, and it extends a served position rather than restating one: *"A gate screen beside a complete artifact carries EXACTLY pointer + response contract + non-duplicated information … bounding content is a STRUCTURAL fix rather than a synchronization discipline"* (*(owner decision record — 2026-07-31 (article design boundary and surfaces))*) governs **gate screens**; what is new here is the extension to **every owner-facing turn, including the narration between gates**, which is where this run's evidence lives. The hook **measures** the budget and does not define it.
>
> **What would overturn this amendment,** named because the whole grant rests on one factual claim: a Stop hook that cannot actually gate the turn. If the hook can only observe and not block, it is *ergonomics rather than control* in the served line's own words, the 2026-07-28 ruling stands unbounded, and the remedy reduces to the two payload-layer contracts alone. That is a cheap check and it is story 20.151's first acceptance criterion. Delivery: stories 20.151 (hook + inventory contract), 20.152 (#1222), 20.153 (#1225).

> **Amended 2026-08-02 (triage, #1224) — the source DECLARATION is a PERMISSION BOUNDARY and stops being a COVERAGE DENOMINATOR; probe's ceiling is a configuration and permission check with a stated time budget, and anchor-finding moves to `examine`.** The 2026-08-02 #1182 amendment above mandates a model-judged feasibility read at probe returning up to seven anchors plus a verdict, with a coverage ledger accounting for every declared source. The shipped probe conforms to it — verified at triage, so the observed behaviour (a 820-file surface across five repositories, line-level anchors, minutes of wall time) is **not an implementation defect** and this is a design decision rather than a bug fix. **The contract tension is real and is quoted from the stage's own text:** *"Read against the brief only what feasibility needs — anchors, never an extraction pass"* (`skills/draft-article/stages/stage1.md:32`) against *"accounting for **every** declared source id; `record` refuses a ledger with a gap"* (`:47-53`). The second clause is what forced a 168-file read to certify an empty result from `commentary-policy`, a source that contributed zero anchors and fifteen of twenty irrelevant examination items before being dropped mid-run.
>
> **The two halves of the declaration are separated, and only one is kept.** As a **permission boundary** — what may be read at all — `writing-sources.yaml` survives unchanged, because two ratified invariants hang off it and neither is reopened here: the filter-never-widener rule (`skills/draft-article/stages/stage0.md:278-280`, restated by the #1103 amendment above) and *"out-of-scope repos never searched automatically"* (*(owner decision record — 2026-07-29 (terrain grouping and evidence model))*). `SPEC-repo-onboarding` also consumes it, and nothing here changes what it consumes. As a **coverage denominator** it is dropped: probe no longer certifies a ledger over every declared id, because certifying coverage of a *declared* universe is what makes the read cost scale with the declaration rather than with the claim.
>
> **Probe's ceiling, stated as a contract because #1224 correctly observes that no performance budget existed anywhere:** probe is a configuration and permission check — the declaration resolves, the granted repositories are reachable, issue visibility verifies — and it completes in **≤5 seconds**. It performs no surface enumeration, no anchor hunt, and emits no grounded/ungrounded feasibility verdict. **Feasibility is discovered where it binds**, at `examine`, per claim: a claim that cannot be grounded is an ungrounded *claim*, which is a finding the pipeline can act on, where an ungrounded *run* at probe time was a verdict about a thesis that did not yet exist. Anchor-finding moves to `examine`, where the scope oracle and the admissibility rules already bind, so it is a relocation rather than new machinery.
>
> **A premise of #1224's first decision was already answered upstream, and the fork is narrower than the issue states.** The #1182 amendment already rules that *"which repositories may be examined is DERIVED from the selected Strands' `projects:` — never composed at a gate"*, and that shipped at `0eed279` (#1097), which emits `harvest_scope` as exactly that union. The **repository axis** of the owner's on-demand model is therefore ratified and delivered; what this amendment decides is the **file-enumeration axis** and probe's ceiling. The stronger form #1224 also offers — retire `writing-sources.yaml` and `set-sources` outright in favour of per-repo access grants — is **declined for now and the reason is recorded so it is not reopened as an oversight**: the two invariants above are stated *in terms of* the declaration, and deleting it without designing their replacement boundary would remove the boundary while keeping the promise.
>
> **The cost this accepts, disclosed rather than assumed away, and it is this decision's own overturn condition.** The #1104 amendment made a thin read *read as thin* by denominating it — *"92% coverage of 11 declared files, with 340 files outside the declaration"* is a sentence an owner can act on. Dropping the denominator at probe risks reinstating the unfalsifiable-success defect that amendment fixed. The bet is that per-claim scoring is the better instrument — each claim is individually gradeable, which whole-corpus coverage never was — and it is falsifiable: **a sitting in which an owner cannot tell a well-grounded article from a thinly-grounded one, with per-claim results present, overturns this** and the answer becomes bounding the ledger to term-matched sources with the remainder counted-never-read, the alternative this decision rejected. Delivery: stories 20.154 (probe ceiling), 20.155 (anchor-finding relocation).

> **Amended 2026-08-02 (triage, #1245/#1247) — the #1221 grant above is ARMED and its vocabulary UNIFIED: every input the Stop-hook chain reads gets a writer, due-ness is derived from data that exists, and numbered stage labels are prohibited on every owner-facing surface by removing them from the data those surfaces are composed from.** The grant above shipped (story 20.151 → #1230 → PR #1240, `900bf00`) and **can never fire**. Reproduced on dogfood run `20260802T142948-588398`: the policy-topic ask, the depth offer and the structure choice all reached the owner as prose, `AskUserQuestion` was called once for a disambiguation composed outside the registry, and the hook let every turn close. This is the thirteenth cycle of the class, and the owner's stated position is that recurrence at this count puts the product in question. **Three joins, none with a writer, each failing toward silence — verified at triage, not asserted.** (1) `stop-gate-carrier.py:78` resolves its subject from `WA_RUN_WS` or `payload["cwd_run_ws"]`; a repository-wide grep finds `WA_RUN_WS` **in that line only**, and `cwd_run_ws` is not a field the harness supplies, so `ws` is always `None` and the hook exits 0 on every turn as "not a pipeline turn at all". (2) `gate-inventory.py:161` reads `checkpoint.json:gates_reached`, whose **only writer in this repository is the guarding check's own fixture** (`check-stop-gate-carrier.sh:43`) — sharper than #1245 states and the reason the check was green: the test manufactured the input the pipeline never produces, so it measured the harness and never the hook. (3) the `--tool-call-audit` path reads `interview-events.jsonl`, absent from the run workspace. Three independently dead inputs, each with silence as its failure mode, multiply to a firing probability of zero.
>
> **The remedy is CONSTRAIN-FIRST and the ordering is the served position's own** (*owner decision record — 2026-07-28 (constrain what the pipeline can produce, not what it can detect)*): *"an enumerated prohibition can only name yesterday's leak while a construction constraint makes tomorrow's unreachable … and the checkable tell that you are on the wrong side is a check suite growing at roughly one member per incident."* **(1) The subject gets a writer.** The stage-transition write that already persists run state (`draft-pipeline.py:3522`) also writes a session-discoverable pointer — `<state-dir>/<cwd-key>/active-run.json` carrying `{ws, next_stage, written_at}` — resolved by the hook from the Stop payload's documented `cwd` alone. `WA_RUN_WS` and `cwd_run_ws` are **deleted**, not kept as fallbacks: a fallback with no writer is what this amendment exists to end. Staleness is answered by `written_at`, never by scanning for the newest directory — the hook's own wrong-run argument (`stop-gate-carrier.py:70-73`) is untouched and is why no scan is admissible. **(2) Due-ness is derived from data that exists.** `gates_reached` is dropped. `draft_gates.GATES` already declares which gate belongs to which stage and the checkpoint already names the stage the run is entering; the two are joined directly.
>
> **(3) The vocabulary is unified on process names, which is #1247's ruling and #1245's repair in one act.** Owner ruling, 2026-08-02, verbatim: *"I prohibit the expression 'Stage N.' It becomes impossible to tell whether the system is performing Brief creation or Draft creation. By attaching a number, the system abandons its responsibility to explain which process the Human Gate belongs to. Reject every Human Gate that can only be expressed through numbering."* Today `draft_gates.py:187-280` labels gates `"stage 2"`, `"stage 3"`, `"stage 0"` while `checkpoint.json:next_stage` names the same stages by process (`interview`, `probe`) — so the join in (2) **cannot match** without a translation table, and the numbered form leaks to the owner from the payloads themselves. Both sides restate on process names, declared once. **The ruling binds every owner-facing surface** — gate payloads, `where:` lines, recaps, next-step lists, relayed journal text, docs prose — and **a gate whose identity cannot be stated as a process name is rejected**, because that is a defect in the gate rather than a naming inconvenience. **Internal identifiers are not exempt where they leak:** the registry may key gates however it likes, but any value reaching an owner surface is owner-facing vocabulary, per the harvest-vocabulary retirement precedent (#1237–#1239). **No per-word checker is added**, deliberately and on the owner's own checker-growth flag: the numbered labels are removed from the data the surfaces are composed *from*, so the prohibited form has no source to leak from, and detection rides the existing owner-surface check.
>
> **(4) One reproduction test, replacing the fixture that lied.** The real `20260802T142948-588398` workspace shape — a due gate, an emitted payload, no `AskUserQuestion` event — is fed to `stop-gate-carrier.py` as a synthetic Stop event and must exit 2 with the gate id on stderr; the settled-clean case must exit 0. This is the acceptance criterion the thirteenth cycle never had. It is **one test and not a per-symptom checker family** because it also guards every regression of (1)–(3). **(5) Indeterminacy is capped, not merely disclosed.** `gate-inventory.py` already prints its BOUND on every run (*"a clean audit is not a clean class"*) and `cannot-determine` was declared the thing to watch **with no watcher** — a rate written to a stream nobody reads. The hook records its per-turn verdict (`subject-found` / `settled` / `result`) into the run workspace, and a run completing with every turn `cannot-determine` is a finding the next sitting's opening surfaces: a fail-toward-silence chain that never determines anything is indistinguishable from no hook, and today proves that case real rather than theoretical. **(6) A dead-input lint, run once as a purge.** Every key, file, environment variable and field each check *reads* is enumerated; an input with no writer in the repository marks its check **dead on arrival** — today that finds at least `WA_RUN_WS`, `cwd_run_ws`, `gates_reached` and `interview-events.jsonl` — and dead checks are removed or fixed, never documented. Its purpose is to **shrink** the suite, which is the polarity the served line above demands; this repository's own staged analysis measured 132/172 → 161/219 scripts in four days.
>
> **(7) Closure requires the observation it names, and this clause does NOT land in this repository.** The rule: a fix for a recurrence class may close only on its reproduction test **plus one observed clean producer run** — never on merge — and a failed verification reopens rather than waiting for the owner to notice. The umbrella above was closed at PR merge with *"verifies by absence in the producer's next run"*; the producer's next run was today, the absence did not verify, nothing was watching, and the owner noticing was again the only carrier. **Written here as prose this clause would reproduce the exact defect it names** — a served line records that *"rides an existing gate is an end state that schedules nothing"*, and an unenforced closing rule is that shape a second time. The closing act belongs to `/triage-gh` and `/ship-cycle`, which live in `claude-toolkit`, so the clause is **escalated to that repository as its owning carrier** and is not delivered by any story here.
>
> **The common structure across all thirteen cycles, recorded because it is the finding rather than the fix:** each fix defined its own evidence surface and was verified against that surface at build time, by its builder, never against the failing event. The first twelve put the surface at the wrong layer; the thirteenth put it at the right layer and never connected it. **What would overturn this amendment:** a reproduction test that passes while a real producer run still lets an un-carried gate close — which would mean the fixture, not the wiring, is what the class defeats, and the answer becomes the fail-closed polarity weighed and declined at this gate (blocking the owner's turn on the pipeline's own bookkeeping failure, rejected for trading a silent-pass class for a noisy-block class with no measurement of the rate; clause (5)'s per-turn record is what would supply that measurement). Delivery: stories 20.157 (vocabulary), 20.156 (arming + reproduction test + verdict record), 20.158 (owner-facing label removal), 20.159 (dead-input purge); clause (7) as a cross-repository handoff.

> **Amended 2026-08-02 (triage, #1322) — the durable-citation convention is a WRITE-LAYER grammar, not a detector: a NEW unpinned `file:line` may not enter relocatable text, and a check's content assertion binds to an anchor token or to a spec's file SET.** Three consecutive issue chains on 2026-08-02 each ended by spawning the next, and the investigation found a **loop rather than a line**. Its three premises are all already ratified here: ratified text is append-only and is never compacted; byte ceilings are never raised; therefore a ceiling trip's only legal remedy is **relocation**. Relocation then breaks the one class of reference nothing indexes — an unpinned `file:line` citation, and a check that greps spec or skill prose by literal content — and each repair adds text, which feeds the next ceiling trip. The measured discriminator, taken in living text on 2026-08-02: **148 unpinned `file:line` citations** (46 of them inside append-only amendment blocks) and **22 content-grepping checks**, which between them broke five times in one day, against **592 `CAP-n`** and **1,127 `#issue`** anchors, of which **none** broke at all. **The repository already owns the relocation-stable reference form.** The fragile form is merely still permitted, so every forced relocation rolls dice over ~170 references. What is ratified is therefore a **grammar denied at the write layer** — which makes tomorrow's instance unreachable — and not an enumeration of today's offenders. Four alternatives were declined by name at the gate: a drift **detector** (post-hoc, the wrong side of the append-only ordering, and it inherits the repair cost it was meant to remove), a **repair sweep** (the per-incident tell — repair cannot outrun generation), **raising a ceiling**, and **compacting** anything. Consulted at the fork; the served position discriminates it and names the shape adopted — owner decision record — 2026-07-29 (the generation-side lever is the real one).
>
> **(1) What counts as RELOCATABLE is DERIVED from the ceiling, never enumerated.** Relocatable text is any **tracked Markdown file for which `scripts/check-skill-budget.sh` reports a size ceiling** — today the Markdown under `specs/` and under `skills/`, and nothing else. The scope is stated as a derivation and not as a path list for two reasons, one causal and one about remedy shape. **Causal:** the ceiling is what *forces* the relocation, so "under a ceiling" is not a proxy for the risk — it is the risk's cause, and a file that is not under a ceiling is never made to move. **Remedy shape:** an enumerated scope list is a denial list, and this repository's own `check-denial-list-growth.sh` refuses that remedy class for exactly the failure it would have here — a path family brought under the budget check later would sit outside the citation rule until someone remembered to amend it, and would read as covered meanwhile. Reading a boundary from the component that owns it, rather than restating it, is the pattern `scripts/check-relocated-artifact-boundary.sh` already carries in its note that the resolver is the contract and the path scheme an implementation detail. **The `skills/` tree is IN SCOPE on observed history, not on taste:** the budget check is named after skills, and the record carries four skill relocations in five days — `draft-article/SKILL.md` split into `stages/*.md` (2026-07-26, #744/#740), `review-article/SKILL.md` into `phases/*.md` (2026-07-27), `terrain/SKILL.md` into `steps/*.md` (2026-07-30), and the whole `skills/topic-map/` directory renamed to `skills/terrain/` (2026-07-26) — and skill prose is precisely what the 22 content-grepping checks grep. **The `docs/` tree is OUT of scope today, and by the same test:** the budget check reports no ceiling for any `docs/` path, so nothing there can be forced to move, and no file under `docs/` in the record was created as a carve-out from a parent that tripped. If `docs/` is ever brought under the budget check it becomes relocatable the same day, with no amendment to this clause — which is the property an enumeration cannot have.
>
> **(2) The pinned grammar is `path:line@sha` or `path:line-line@sha`, and the sha is checked for SHAPE — it does NOT have to resolve.** A legal pin carries at least seven hexadecimal characters after `@`; that is the grammar the two-tier grounding pin and the gate-item content-grounding clause in `SPEC.md` already use, so nothing new is coined. **Resolution is deliberately not required, and the reason is not cost.** Requiring it would deny the repository's own **declared synthetic pins** — `8f3c2d1`, `abc1234`, `0000000`, `deadbee`, `1111111`, the values `check-publication-boundary.sh` exists to make safe — which appear in every `*-formats.md` grammar example and every fixture, and are *supposed* to resolve to nothing; a resolving guard would either fail them all or need an allowlist of synthetic shas, which is a denial list defending a rule adopted to avoid denial lists. It would also make cross-repository grounding unwritable: the pins that matter most address a private surface whose objects are not present here and whose name may not be written here at all under the publication boundary. And it is not what the guard is *for*: a sha — resolving or not — is what converts a live pointer into **dated testimony**, which is the whole of the relocation-stability property. **The cost is stated rather than assumed away:** a mistyped sha passes this guard. That is a grounding-*accuracy* defect, and grounding accuracy already has its own carrier in the two-tier private record and `scripts/provenance-pin.py check`. This guard does not duplicate it and does not claim it.
>
> **(3) The deny sits in ONE diff-reading check inside the existing suite — a new git hook is declined.** The served position adopted a **commit-time `git diff` detector** as the write-boundary carrier precisely because a diff is the *artifact* while a tool call or a command string is only *intent*, so a diff-reader alone covers `sed -i`, heredocs, `git checkout` and a direct editor write from outside the agent — owner decision record — 2026-07-26 (a commit-time git diff detector is the write-boundary carrier). This repository's carrier of that shape is its **check suite**: a check reads the diff, is blind to how the bytes arrived, and — unlike a git hook — **ships in the tree**, so it is present in every clone. The one commit-time hook installed here (`.git/hooks/pre-push`) exists only because another repository's installer was run, is untracked, and is reinstalled by a command this repository does not own; siting this repository's own citation grammar there would put it in a carrier a fresh clone silently lacks. Under the rule that a control belongs at the last boundary you actually hold — owner decision record — 2026-07-23 (carry a rule at the layer where its violation occurs) — the tracked check is that boundary, and a hook here would be strictly weaker rather than stronger. **The suite budget is respected: exactly ONE check is added**, declaring `# tier:`, `# covers:`, its parallel-safety decision and a removal signal like its siblings. It runs in the per-edit loop, so a denial arrives in the iteration that caused it. **Per the guard-scope disclosure rule, a clean run reports the scope it inspected and never the class** — this carrier is after-the-fact by construction, and its silence means "no introduced violation in this diff", never "no violation".
>
> **(4) The guard binds the text a write INTRODUCES, never the file's standing content — and a verbatim MOVE introduces nothing.** This is load-bearing and is the clause most easily lost in implementation. A guard that blocked an innocent write because of a pre-existing violation would build a **quarantine that grows**: any file that ever violated becomes unwritable for every purpose until someone re-answers all of it, and the actor holding the blocked write is not the actor permitted to repair it — owner decision record — 2026-07-27 (a lint gates the text a write introduces, never standing content). So the guard's subject is the **added lines of the branch's diff against its merge-base**, and nothing else. **The move rule follows from the same principle and is not a concession:** an added line whose exact text also appears among that diff's *removed* lines is a **relocation, not an introduction**, and is admitted. Without it the guard would deny the very remedy the loop makes mandatory — a ceiling-trip relocation moves ratified text verbatim, unpinned citations and all, and a guard reading those as new writes would make legal relocation impossible while claiming to protect it. Verbatim-line matching is exact for the relocation idiom this repository actually mandates ("relocated verbatim"), and it needs no rename detection.
>
> **(5) The exemption set is CLOSED at three members, named here rather than accumulated as special cases.** **(a) The pinned form** `path:line@sha` — not an exemption so much as the legal form, stated for completeness. **(b) Content inside a fenced code block.** A line number inside a fence is a *literal being shown* — a format example, a quoted diagnostic, a command line, a JSON payload — not a pointer a reader is expected to follow, and it does not rot because nobody dereferences it. Exempt by construction and with no marker, because the alternative is hand-marking every grammar example in every `*-formats.md`. **(c) A marked positional use**, for the rare prose case where the line number *is* the subject rather than the address — a clause asserting that a shebang occupies line 1, an error message quoted inline. It is admitted by an adjacent, human-written `<!-- positional-cite: <why the number is the subject> -->`, following the `# register-exemption:` precedent in `check-denial-list-growth.sh`: what is removed is the **silent** use, never the correct one. A fourth member is an amendment, not a judgement call at the keyboard.
>
> **(6) The 148 existing citations are FINDINGS, never a quarantine, and there is no sweep.** They are repaired when the containing text is touched for another reason. The 46 inside ratified amendment blocks are reachable — pointer repair inside ratified text is legal where wording change is not — but reachable is not scheduled. A repair pass is the detect-side tell the served position names, and adopting one here would spend the argument the guard exists to make.
>
> **(7) The check idiom: a content assertion binds to an anchor token or to a spec's file SET.** This generalizes the repair `scripts/check-stage2-policy-seam.sh` already carries, where a `grep` that had matched one file now passes `SPEC.md` and `constraints.md` together, so the assertion survives the relocation that split them. A check asserting that a contract exists should grep for a `CAP-n` token, a constraint's declared name, or an `#issue` anchor — the forms with a measured survival rate of 100% — and where prose must be matched, it is matched across the spec's whole file set rather than one member. Migration is **opportunistic and rides the coverage-declaration work already in flight**, not a sweep of its own: the 22 are converted as their specs are touched.
>
> **What would overturn this amendment:** a demonstration that anchors rot here too — a `CAP-n` renumbering, or an issue-number reuse — which would mean the durable form is only durable because it has not yet been stressed, and the answer becomes an indexed reference rather than a grammar; or a ruling that a citation inside an append-only amendment block cannot be governed at all, which would put a third of the population permanently outside the convention and make the rule's scope claim false. **Success signal, unchanged from the issue:** the next forced relocation completes without producing a repair issue. Delivery: story 20.184 (the guard), story 20.185 (the check-idiom migration).

> **Amended 2026-08-03 (triage, #1339) — a reader-facing citation in an
> emitted product is CONSTRUCTED repo-qualified, and a bare sha is
> unconstructible rather than detectable.** The shipped canonical
> `articles/drafts/where-a-safeguard-binds.md` cites `commit 556ab1b` in its
> Pointers section while the GitHub references beside it carry full URLs. For
> the article's declared audience — an external reader with no portfolio
> context — a bare sha resolves to nothing: no repository is named, and the
> article mentions several.
>
> **The asymmetry this closes.** `scripts/check-citation-form.sh` governs this
> repository's **own** body text (`path:line@sha` pins); the **product's**
> reader-facing citation form had no carrier at all. So the internal citation
> discipline was enforced and the published one was not, which is backwards:
> the external reader is the party with no other way to resolve a reference.
>
> **What binds.** The emitter renders a product's commit citation from the
> examination record, which already carries `pin: <repo>@<sha>` at the read
> that produced it — so the repository qualifier is **in hand at the point of
> writing** and nothing is inferred, looked up, or re-derived. A bare,
> repo-unqualified sha therefore cannot be composed. A refusal at the `complete`
> write layer is the **backstop**, not the mechanism: it exists so a
> hand-authored product cannot re-open the hole, and it is expected never to
> fire on pipeline output.
>
> **The remedy shape is the standing one** — *owner decision record —
> 2026-07-28 (constrain generation, not post-hoc detection)* — and this is the
> constrain side of it: detection after composition would make the run loop to
> repair what it could not have written wrong. The declined alternative (a
> check on the persisted product, symmetric with the frontmatter bounds
> already enforced there) is exactly that loop.
>
> **Scope, stated so it is not read wider:** this governs **commit** references
> in emitted products. Issue and URL references already resolve and are
> untouched; `path:line@sha` pins in this repository's own text stay with
> `check-citation-form.sh`. The publication boundary is unaffected — a
> repo-qualified sha of a **public** repository is what the reader needs, and
> the boundary's prohibition on the policy hub's name and shas is unchanged
> and unweakened.
>
> **What would overturn this amendment:** drafts proving to need short internal
> references during review, with only the published variant resolving them.
> That is a product-boundary claim (the canonical is what the site publishes,
> so it does not hold today) and it would arrive as a variant-side amendment,
> not as a relaxation here.
>
> Delivery: story 20.195.

> **Amended 2026-08-03 (triage, #1355/#1356) — the check family gains an
> ADMISSION GATE whose acceptance conditions include a removal signal declared
> at birth, and a cost-ranked lean obligation; the proposed inversion of the
> `tier:` default polarity is DECLINED on a measured premise, and what stands in
> its place is closing the promotion ceiling exemption and classifying the
> pre-adoption baseline.** The filing premise was that 119 checkers sit in the
> per-edit loop and that a headerless default is what puts them there. Measured
> at triage on a clean tree, the family is **174 checks — 55 declaring
> `# tier: full`, 36 declaring `# tier: inner`, and 83 headerless** — and the
> per-edit loop is not 119 wide, because #944 and #998 already narrowed it: a
> scoped inner run selects **5 checks** when `run-checks.sh` itself is edited and
> **31** when a skill file is (30 of those 31 arriving through the `# covers:`
> union, which #1326 already rules a finding rather than a failure). The 119
> figure is the **unscoped** run, which #944 fails by design and whose named
> remedy is scoping. **Two further measurements decide the fork.** First,
> `# covers:` now stands at **174 of 174**, so #1321's promotion is fully armed:
> a `# tier: full` check whose own declaration matches a changed path runs in the
> inner tier anyway. Demotion therefore does **not** remove a check from the
> per-edit loop when its subject changes — it removes only the ceiling, since a
> promoted check is reported `PROMOTED-SLOW` rather than failed. Inverting the
> polarity would thus have traded #913's load-bearing property — *the ceiling
> polices the default, so a new slow check cannot hide* — for approximately no
> reduction in what actually runs. Second, the admission path **already** forbids
> a headerless new check: the declarations gate has required an explicit
> `# tier: inner|full` and a `# removal-signal:` of every post-adoption check
> since #922, so the default governs the 83-member pre-adoption baseline and
> nothing else. **The contract, in five rules, declared in `run-checks.sh`'s
> header beside the thresholds they govern.** (1) *Admission.* A proposal to add
> a checker is accepted only when it states the defect class it ends — a
> generation-side constraint that makes the class unproducible being the
> preferred answer, and "no checker" a valid outcome — its tier and **measured**
> runtime, and its removal signal. "Better than none" is formally inadmissible:
> it prices the benefit and not the cost, which multiplies by loop position. The
> removal-signal half already ships; the defect-class and measured-runtime halves
> are what this adds. (2) *Cost-ranked lean obligation.* The smallest set of
> checks covering ≥80% of summed per-sitting cost carries an obligation the rest
> do not — at review, compare where the check has caught meaningful defects
> against the coverage where nothing has ever fired, and remove what has shown no
> value. (3) *Frequency demotion is the default for expensive checkers*, declared
> in the check itself in the greppable-header shape `tier:` and `parallel-safe`
> already use; the burden of proof sits on frequency, not on demotion. (4)
> *Retention review*: zero failures across N **exercised** runs makes a check a
> removal candidate — reviewed, never auto-deleted, because a never-firing check
> may be deterring rather than dead. (5) *The sanctioned shrink lever is
> assertion altitude* — merging single-assertion scripts into fewer
> fixture-based checks, and removing valueless coverage under rule 2, never
> chasing a count target, which invites cosmetic merges that lower the count and
> keep the cost. Rules 2 and 4 read a per-sitting cost record and therefore
> **bind on the delivery of the ledger amended below**; they are ratified now and
> unenforceable until it lands, and that interval is stated rather than left to
> be discovered. Rules 1, 3 and 5 bind immediately and need no history. **The
> rules are themselves subject to the standard they set** — a rule corpus
> accretes exactly as a check suite does (*owner decision record — 2026-08-02
> (constrain generation, not post-hoc detection)*), which is why there are five
> and not one per collected complaint, and why rule 1 prefers a generation-side
> constraint to a new member. **What replaces act 1.** The promotion exemption
> closes: a check promoted into the inner tier by a coverage hit is subject to
> `INNER_MS` like any other inner member, because #1321 gave promotion the
> execution cost of an inner check while #1326 left it the reporting semantics of
> a full one, and that pairing is what would have made a demotion sweep look like
> relief. And the 83 headerless members declare their tier explicitly, by ratchet
> under the existing classify-when-touched adoption shape — the retrospective
> sweep stays declined. **Not licensed by this amendment:** inverting either
> default polarity, raising any ceiling, and deleting any check on count grounds.
> **What would overturn it:** evidence that sittings run the inner tier
> **unscoped** in practice, which would make 119 the real per-edit number and the
> measurement above beside the point. That is checkable from the ledger below,
> which records each invocation's scope — so the deferral owes no separate
> generating mechanism (*owner decision record — 2026-07-30 (a deferral to data
> owes its generating mechanism)*). Act 3 of #1356, the altitude merges, yields
> no story here: its own ordering makes it follow-up sittings per family, and its
> ranking input is the ledger that does not yet exist. Delivery: stories 20.196,
> 20.197, 20.198.

> **Amended 2026-08-03 (triage, #1354) — the runner MEASURES everything and
> RETAINS none of it; the family's budget gains a per-invocation ledger in the
> machine state root and a report that RECOMPUTES rather than storing counts.**
> Every ceiling this family declares — `INNER_MS`, `INNER_TOTAL_MS`,
> `FULL_TOTAL_MS`, `FULL_WALL_MS` — is computed per run and discarded at exit,
> so the two questions the owner asks cannot be answered from anything the
> repository holds: what a sitting's total elapsed time is, and what share of it
> is checker runtime. The family has bounded one scope at a time and left the
> next unwatched three times (#944 the member, #961 the tier); the **sitting** is
> the scope above the tier, and it is unbounded because it is unmeasured, which
> is the prior condition rather than the same defect. **The contract:**
> `run-checks.sh` appends one JSONL record per invocation carrying the timestamp,
> the tier, the **scope** (the glob, or unscoped), each check's name, elapsed ms
> and verdict, and the family total; and a `report` subcommand renders a
> sitting's wall clock, summed checker time, checker share, and the ranking by
> **total cost per sitting — Σ(runtime × invocations)**, never per-invocation
> runtime alone, so a one-second check invoked thirty times outranks a
> twenty-second check invoked once. The reported set is the smallest covering
> ≥80% of summed cost; the threshold is derived from the measured distribution
> and "top five" was an example, never the rule. **Emission is a side effect of
> running.** Nothing new is measured — the runner already holds every value the
> record carries; it stops discarding them, which is the same shape as the
> record-as-a-side-effect-of-the-act contract SPEC-run-record already carries.
> **The verdicts ride the same record as the timings, deliberately:** one writer,
> two consumers, because the catch record rules 2 and 4 of the amendment above
> read is the same data as the cost ranking. **Siting is settled and not
> restated:** the record is machine-readable, resumable and never opened by a
> human by intent, which is exactly the class `docs/storage-architecture.md` D2
> assigns to the machine state root. What D2 does **not** settle is retention —
> its open question defers GC "until disk or clutter", taken on the premise that
> the artifacts are debug clutter, and rules 2 and 4 above falsify that premise
> by making this record load-bearing. **So the retention rule is stated here: the
> check ledger is not GC-eligible on clutter grounds**, and any bound placed on
> it later is a decision about what a retirement review is entitled to see, never
> a disk-space cleanup. **The report stores nothing.** It is a subcommand that
> recomputes from the ledger on demand, because primary capture — a record
> written at the act, holding what no other carrier holds — is permitted while a
> stored derived tally is not; a digest that read a stored count would breach
> that rule and one that recomputes does not. **Not licensed:** a second stored
> ledger of any kind, a ceiling declared against the per-sitting quantity before
> it has been measured even once (the aspirational-ceiling failure #961 refused —
> an instrument that cries wolf on its first run), and any change to the four
> existing ceilings. **What would overturn the retention clause:** a ruling that
> rules 2 and 4 will read a bounded recent window rather than history, which
> would return this record to the ordinary state-growth class D2 already defers.
> Delivery: story 20.199.

> **Amended 2026-08-03 (implementation, #1355/#1356/#1361) — the promotion
> ceiling clause of the amendment above is WITHDRAWN the same day it was
> written; the #1321 exemption stands, and the withdrawal is recorded rather
> than edited away.** The amendment above closed the exemption on the reasoning
> that #1321 gave a coverage-promoted check the *execution cost* of an inner
> member while #1326 left it the *reporting semantics* of a full one, and that
> the pairing was an oversight. It is not an oversight. `run-checks.sh` carries
> #1321's own reasoning at the site, and it was **not read before the clause was
> written**: the per-check ceiling's stated job is to stop a check **hiding** in
> the inner tier, a promoted check is declared rather than hiding, and its named
> remedy — declare `# tier: full` — is already spent. Failing it would leave
> only fixture-ising, **charged as the price of adding a `# covers:` line**, so
> the cheapest way to keep an edit loop green becomes declaring no coverage.
> That escape is sharper now than when #1321 was written, not weaker: `# covers:`
> stands at **174 of 174**, an undeclared check is selected by name-prefix only,
> and stripping the line is a one-line change that is invisible in review as a
> deletion. The clause would therefore have put pressure on precisely the
> declaration #998 exists to collect, at the moment that collection is complete.
> **The pressure the clause wanted already exists at the right altitude:** a
> promoted check's cost still counts into `INNER_TOTAL_MS`, which **does** fail,
> and whose named remedy — narrow a too-broad glob — is the correct answer to
> promotion that costs too much. The aggregate ceiling was the instrument all
> along; the per-check one had nothing left to add. **Everything else in the
> amendment above stands unchanged** — the five governance rules, the decline of
> the `tier:` polarity inversion and its measured basis, the baseline ratchet,
> and the orphan sweep. Only the promotion clause is withdrawn. **Consequence
> for delivery: story 20.196 has no implementation left.** Its remaining
> criterion — that the rules are declared in the runner's header — was satisfied
> by the amendment's own commit, because under declare-once-in-the-enforcement
> the rules text *is* the contract. It is therefore a spec-only outcome and is
> not carried as a story. **What would overturn this withdrawal:** a measured
> case of a promoted check materially slowing an edit loop while
> `INNER_TOTAL_MS` stays green — which would show the aggregate is not catching
> it and the per-check ceiling has a job again. Delivery: stories 20.197, 20.198
> (unchanged) and 20.199 (unchanged).

> **Amended 2026-08-03 (implementation, #1356/#1363) — the retired-subject
> orphan sweep RAN and returned EMPTY; what it leaves behind is the
> DISCRIMINATOR, because the sweep's premise was true of its method and false of
> its population.** #1356 act 2 asserted that "checkers guarding retired subjects
> are pure waste detectable *without any runtime data*" and named the retired
> mechanisms to sweep for. Executed 2026-08-03 over all 174 checks: **zero
> orphans.** The three named subjects each failed for a different reason, and the
> reasons are the finding. **`check-harvest.sh` is already absent** — it was
> deleted with its subject, so the retirement had already discharged its own
> checker. **The Framework family is live**: `skills/draft-article/frameworks/`
> still holds F1 through F5, because what retired was the *vocabulary* — F1–F5
> became intent labels and remain the internal alias — not the files. **The fact
> sheet was renamed, not removed**: the 2026-08-02 amendment's "no fact sheet
> exists anywhere in the pipeline" is true of the artifact and false of the
> symbol, `--fact-sheet` survives as the flag name pointing at
> `examination-pins.txt`, `examine.md` says so at the flag itself, and
> `validate-fact-sheet.py` is reachable from `draft-pipeline.py`. **The
> discriminator is the durable half and is recorded so the next sweep does not
> re-derive it: a check's subject is what its `# covers:` globs resolve to, never
> what its text mentions.** The mention-based reading the issue implies flags ~41
> checks for "harvest" alone, and almost every one of them names harvest *while
> asserting it is gone* — a live subject, and the most valuable kind. The
> covers-glob discriminator is one loop, costs milliseconds, and returned a clean
> answer; it is available to any future sweep. **Its stated limit, so a later
> reader does not over-trust it:** it catches a check whose *file* subject
> vanished, not one whose mechanism exists but is unreachable, which is exactly
> the class the fact-sheet case nearly produced. That harder question is not left
> unowned — it is #1355 rule 4's retention review, whose instrument is a check
> that never fires across *exercised* runs, and which reads the ledger delivered
> by story 20.199. **Consequence for delivery: story 20.198 produced its mapping
> and no diff.** A story whose deliverable is a negative result cannot reach the
> merged-PR definition of done that the story lane and cleanup both use, so it is
> recorded here and closed rather than carried. Act 2 is discharged, not
> deferred. Delivery: none; story 20.198 withdrawn, #1363 closed on this record.

> **Amended 2026-08-03 (triage, #1366) — the check suite is ISOLATED from the
> state root it exercises, with no opt-out, and the substituting fallback
> ANNOUNCES itself; the "newest workspace" mechanism the filing named does not
> exist, and the correction is what makes one fix sufficient.** Two faces were
> observed on 2026-08-03: **851 tmp-derived directories** accumulated in the
> machine state root (eight more per `--tier full` run, measured), and a
> concurrent full-tier run wrote **foreign block open/close records into the
> owner's live draft run**, with `last_stop` claiming a block the real run had
> not reached — a `run_block.py rerun` at that moment would have restored a
> foreign checkpoint and moved the live run's artifacts to `invalidated/`. Data
> loss was averted by a human noticing timestamps that could not be theirs.
> **The filing attributed the second face to "the resolver fallback … newest
> workspace resolution", and that mechanism does not exist.** Read at triage:
> `run_record.workspace_of` falls back to `--ws`/`WS` and then to the
> resolver's **active-run pointer**, and its own docstring says *"never a scan
> for the newest workspace, which that resolver forbids in the same breath it
> writes the pointer"* — the same conclusion #1313 reached when it examined this
> fallback and called it *"correct rather than a guess"*. The defect was never
> the fallback's logic. It is that **the pointer lives in the state root**, so a
> fixture and a live run share one pointer for the same reason they share
> everything else. **That correction is load-bearing**, because it collapses the
> remedy: sandboxing the state root gives fixtures their own pointer, and the
> cross-run attribution becomes unreachable rather than merely refused. The
> class is already ruled — *owner decision record — 2026-07-22 (a shared-scope
> resource presenting as private must be isolated or warn loudly)*: "isolated OR
> warn loudly on collision — silence is not among the options; which of the two
> is an implementation choice." **The contract, two clauses at two layers.**
> (1) *Isolation, at the runner:* `scripts/run-checks.sh` gives every spawned
> check a sandboxed state root, both tiers, no opt-out; the invariant is stated
> at `docs/storage-architecture.md` D1, which is where the hole was. **The
> runner is not a check**: its own per-invocation ledger (#1354) resolves its
> path before the sandbox exists, and an implementation that exported the
> sandbox for the runner's own shell would delete that ledger at teardown — the
> failure mode being silence, since the report would simply find fewer
> invocations than happened. (2) *Disclosure, at the substitution:* when
> `workspace_of` resolves through the active-run pointer it says so, naming the
> command and the workspace it attributed to — *owner decision record —
> 2026-07-28 (a skipped join is reported as a producer defect)*: "make the
> fallback announce itself at the point of substitution, which is the only place
> the evidence still exists." This is the layer the runner cannot reach, a
> direct invocation outside it. **The stronger option — deleting the fallback
> and making `--ws` mandatory — is DECLINED**, and not on cost: `run_record.py`
> states the current behaviour deliberately, *"the block then runs unrecorded
> rather than failing: emission never fails a run"*, and reversing it would make
> a missing flag fail runs across at least eight check files (eleven such calls
> in `check-run-record.sh` alone) plus `stage3.md` and `gate.md`, to fix a case
> clause (1) already makes unreachable. **The 851-directory sweep is NOT
> licensed by this amendment.** Deleting them is irreversible by an automated
> actor, and *owner decision record — 2026-07-26 (undo privilege bounds
> reversibility)* routes such an act through the boundary irreversible acts get:
> it is a separately confirmed step, taken **after** isolation lands so the
> population stops regrowing first. **What would overturn clause (2):** evidence
> that the announce line is never read — it prints inside a fixture — which
> would make it the warned-plan-nobody-reads shape and reopen the stronger
> option. Delivery: stories 20.200, 20.201.

> **Amended 2026-08-03 (triage, #1356) — act 3's altitude merges are DECLINED on
> the measurement act 3 itself asked for, and the cost it was aiming at is
> located: 2,428 interpreter spawns per full tier, at a 4.6x startup penalty
> that merging files removes none of.** #1356 act 3 instructed a merge of the
> largest `check-<subject>-*` families into one fixture-based check per family,
> ranked "by member count x summed ms from the same single measured run". The
> ledger delivered by story 20.199 made that ranking computable for the first
> time, and it ranks `check-terrain-*` (16 members, 240,091ms),
> `check-policy-*` (8, 297,625ms) and `check-review-*` (13, 136,184ms) at the
> top — exactly the families act 3 anticipated. **The act still fails, because
> its saving does not exist.** Measured: the per-file `sh` floor is **~0.7ms**
> (ten spawns, 7ms), so merging `check-terrain-*` from 16 files to one removes
> fifteen files and about **10ms** from a family costing ~30,000ms per full run
> — **0.03%**. The ~0.5s figure the #944 amendment records is *interpreter*
> startup, not per-file cost, and **merging `sh` wrappers removes not one
> interpreter spawn**: `check-policy-block` makes 44, `check-review-reentry` 41,
> `check-terrain-theses-inner` 17, each measured 70–80% startup-bound. So act 3
> is the case rule 5 of the checker governance rules names in its own words —
> *"never by chasing a count target, which invites cosmetic merges that lower
> the count while keeping the cost"* — and declining it the day that rule landed
> is the rule working rather than being waived. **Where the cost is.** `python3`
> resolves through a **pyenv shim** on the measuring machine: **79ms** per spawn
> against **17ms** for the interpreter the shim itself selects. A full tier makes
> **2,428** spawns, so the shim costs **~150s of summed work — 31% of
> `FULL_TOTAL_MS`**. All of it originates in the check `*.sh` files (1,545
> invocation lines); **no python script re-invokes `python3` by name**, and
> fourteen already use `sys.executable`, so the python side is correct and this
> is not a portability defect there. **This discharges the third remedy's
> deferral.** The #944 amendment recorded interpreter batching as the third
> remedy and explicitly did not take it — *"it restructures how checks execute
> and waits on its own evidence"* — and #957 called batching "spent as a lever"
> on the strength of `check-topic-map`'s profile (55 spawns ≈ 4.1s of 22s). That
> reading was correct about that check and **does not generalise**: the families
> measured here are the opposite shape, and one work-dominated specimen was too
> narrow a base for the conclusion. The evidence the deferral asked for now
> exists. **The remedy is not batching but resolution**: the runner resolves the
> interpreter once and puts it on the PATH it *already* exports per spawn for the
> #1366 sandbox — one line, no call-site changes across 1,545 invocations.
> Measured 51% off six of the heaviest checks with all six still passing. **On a
> machine without pyenv the change is a no-op**, since `python3` already is the
> binary `sys.executable` names: the benefit is environment-specific, the
> correctness is not. **What would overturn it:** a machine where the checks are
> meant to run an interpreter *other* than `sys.executable` — a venv they should
> ignore — which was not tested. Delivery: none for act 3; the interpreter
> resolution is filed and implemented separately. #1356 closes.

> **Amended 2026-08-03 (triage, #1378) — the FULL tier's work ceiling is
> compared DISTRIBUTIONALLY, not point-wise: the 2026-07-30 ruling applied one
> scope up, and binding on the next violator-fix rather than as new
> enforcement.** The owner ruled on this exact shape at the MEMBER scope on
> 2026-07-30 — a ceiling compared point-wise against a variance-bearing
> measurement reports the variance, compliance is declared with headroom, and a
> raise is never the remedy — with a distributional criterion (p95-with-margin)
> binding when a violator is FIXED rather than as new enforcement. That
> disposition is applied here unchanged; what is decided is its scope, not the
> principle.
>
> owner decision record — 2026-07-30 (a ceiling compared point-wise against a
> variance-bearing measurement reports the variance)
>
> **The evidence, and why it is stronger at this scope.** Ten full-tier readings
> taken 2026-08-03 at one stated concurrency, same machine, over a suite that
> moved by a handful of lines, span roughly ±10% around their median. The
> declared ceiling sits inside that band's upper tail, so a reading of OVER
> carries no information about whether the suite grew. The tier scope matters
> more than the member scope did: this ceiling is explicitly the GROWTH
> instrument, and an instrument that fires on noise stops being read. Erosion is
> slow enough that ten same-day samples are the cheapest evidence this will ever
> have.
>
> **A regression was suspected and cleared by direct measurement, recorded so
> the reading is not later re-litigated.** The highest of the ten was
> investigated as a suspected cost from the state-root isolation change
> (#1366). Measured directly, the same twenty checks with and without the
> sandbox differ by **+441ms, +0.9%**, extrapolating to a few seconds across the
> full suite — an order of magnitude below what the breach would have required.
> The reading was variance.
>
> **The rule.** Compliance for the summed-work ceiling is a **distributional**
> criterion — p95 with margin over retained readings **at the same declared
> concurrency**, the like-for-like requirement the header already imposes — and
> it **binds when a violator is fixed**, never as new enforcement on the next
> run. The value itself is not restated here: `scripts/run-checks.sh` is the
> single enforcement copy and this repository's standing instruction forbids
> restating the declared numbers in any spec or check.
>
> **The substrate already exists and this builds on it rather than adding
> storage.** The per-invocation check ledger (#1354, story 20.199,
> `scripts/run-checks.sh:241-330`) records per-check rows per invocation, so a
> reading history at a stated concurrency is derivable from what the runner
> already retains. No second ledger is introduced — which is also what keeps
> this consistent with the assemble-on-demand stance the counting rules take
> elsewhere.
>
> **What is explicitly NOT decided.** Raising the ceiling. The same ruling names
> silent cap relaxation as never an exit, and #1378 refuses it in its own text.
> Re-declaring the constant at a measured p95 while keeping a point-wise
> comparison was considered and declined: a point-wise comparison against a
> variance-bearing measurement reports the variance at any threshold, so moving
> the line changes how often it misfires and never whether it can. The
> 2026-07-30 ruling named the comparison, not the value.
>
> **What would overturn this:** a p95-with-margin criterion proving unable to
> detect a real regression the point-wise one would have caught — growth that
> hides inside the band. The band is roughly ±10%, so a sub-10% regression is
> exactly what this trades away, knowingly. If one is ever missed and
> attributable, the honest correction is a second instrument sensitive to
> monotone drift, not a return to point-wise comparison. Delivery: story 20.206.
