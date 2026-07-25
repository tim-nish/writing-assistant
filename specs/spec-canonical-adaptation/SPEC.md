---
id: SPEC-canonical-adaptation
companions: []
sources:
  - ../spec-platform-variants/SPEC.md          # variants stay pure packaging; this spec supplies the matching canonical
  - ../spec-article-draft-pipeline/SPEC.md     # the draft flow that produces the source canonical
  # Ratifying owner decision (two-canonical architecture: one draft flow, one EN
  # canonical, adaptation as an explicit per-language derivation step) is held in
  # the owner's private knowledge hub, 2026-07-22 conversation record; staged for
  # distill. Mechanism public, provenance private.
---

> **Amended 2026-07-25 (triage, #693)** per /triage-gh on an unreachable re-derivation: CAP-4's write went through the pipeline's one canonical write path with **no ownership channel** (`scripts/adapt-canonical.py:561-562` passed neither `ws`, `owned`, nor `replace`), so the #666 no-clobber gate refused every re-derivation of an already-derived slug while the first one succeeded, and CAP-5's clearing instruction — "re-adaptation is a FRESH owner decision through this invocation" — pointed at an invocation that dead-ended at the refusal. **The owner's recorded answer at the CAP-3 gate IS the ownership token for the derived slug**: a `write` whose workspace holds a presented payload for *this* derived slug and a latest recorded answer of `approve` or `modify` is authorized to replace the existing derived canonical, and the refusal for a **foreign** collision (no gate, no recorded answer) survives unchanged. The token is that **verified conjunction**, never a bare override flag — `adapt-canonical write` exposes no `--replace-canonical`, so the only path to a re-derivation remains the gate itself (`consulted: product-lab@34a6119666896f232e1aa00789c3f916bc2b6dad topics/knowledge-architecture.md:67, topics/claude-code-ops.md:19`). Note the mechanism this cannot reuse: an adaptation workspace holds `presented-payloads.jsonl` but **no** `checkpoint.json`, so the draft flow's checkpoint-based `_ws_owns_slug` discriminator (`scripts/draft-pipeline.py:4744-4759`) is false by construction here — ownership is read from the **recorded-answer log**, which is the artifact this invocation actually produces. The gate's comparison basis and the trailer's demotion to a non-authoritative attestation are SPEC-article-draft-pipeline's (amended same sitting, #693/#695); this spec states only what authorizes the adaptation write.

> **Amended 2026-07-25 (triage, #700)** per /triage-gh on the first real derived canonical's inherited metadata (`drafts/tanuki-honest-automation.ja.md`): the derivation re-declared only `slug`, `title`, `language`, `audience`, `audience_id` (`scripts/adapt-canonical.py:441`) and inherited every other frontmatter field verbatim, so a file declaring `language: ja` carried an **English `summary`** and the **source's creation date**. Two fields, two different authorities, and the decision splits along that line. **`summary` is TELLING, so the adaptation re-decides it** — "adaptation re-decides telling, never truth" (`consulted: product-lab@34a6119666896f232e1aa00789c3f916bc2b6dad topics/articles.md:55`; note the ratified per-article list names *structure and depth*, so this **extends** that line to metadata rather than merely applying it). `summary` therefore joins CAP-3's authored slots and CAP-4's re-declared fields: the owner approves the target-language summary at the **same gate** that already carries the plan, so no new interaction appears. **`date` stays inherited, and this spec declares only that.** What the field *means* — the date this canonical came into being, or the date of the underlying work — is **undeclared anywhere today**: the articles repo's `## Schemas` block declares drafts' additions and the `adapted_from` pin but carries no `date` field, and this tool's config declares `date  # YYYY-MM-DD` (`config/user-config.example.yaml:82`), which is a format and not a semantics. That meaning belongs to the **articles-repo schema**, which is the declared authority for the field set a canonical carries (`consulted: product-lab@34a6119666896f232e1aa00789c3f916bc2b6dad topics/articles.md:32` — schema-is-the-API; a shipped-ahead writer does not amend a ratified decision by fait accompli, which is the *first-derivation-fixes-the-shape* failure this very artifact would otherwise commit). It is carried below as an **open question routed there**, not answered here, and the derivation's behavior for `date` is unchanged. Everything still outside CAP-4's re-declared set remains inherited verbatim by design.

> **Amended 2026-07-25 (triage, #705)** per /triage-gh on a gate that presented a **replacement as a creation**: `compose_payload` stated the writing choices as "writes the derived canonical `{derived}` from this plan; the source canonical is untouched" (`scripts/adapt-canonical.py`) with nothing about the derived canonical **already on disk**. Observed the same day: a committed derivation existed for `tanuki-honest-automation.ja` (articles repo `26f7c51`, pinned `@48f0c62b…`, stale against the source's current content `f9adc03b…`); the owner approved that wording and the write replaced it wholesale, and the re-derivation **regressed a claim the previous derivation had rendered correctly** (#699 — the EN ordinal became a difficulty ranking with an invented contrast). Note when this became reachable: before #693 the no-clobber gate refused this write outright, so the refusal was accidentally the thing preventing a silent replacement — authorizing it from the recorded answer was correct, but **the disclosure half of that change was never written**, so a guard was removed without the gate learning to say what it now permits. **CAP-3's success criterion therefore carries an explicit disclosure duty:** when a derived canonical already exists at the target slug, the presented effect **names it and states that it is replaced**, and when its recorded `adapted_from` pin no longer matches the source's current content hash, the gate **reports the hash pair** so the owner sees why re-derivation is the sanctioned clearing act (CAP-5) rather than a collision. Both facts are already cheap where the payload is composed — the destination is computed there, and the pin-vs-current comparison is what CAP-5's staleness check reads. Scope stated: this makes the *replacement* visible; it does **not** compare the existing derivation's claims against the proposed one, which cannot happen at this gate because the body is authored **after** the answer (CAP-3 → CAP-4). That comparison gap is deliberately left open with its own tracking artifact rather than folded in here.

> **Amended 2026-07-25 (triage, #704)** per /triage-gh on a reviewed derivation that could not reach a checkpoint: `review-article`'s post-arbitration re-entry requires a rebuilt provenance map (`review-reentry --map` is a required argument, `scripts/draft-pipeline.py`), while CAP-4 below says a derived canonical's claim **verification does not re-run** because claims are inherited under CAP-2 — so the artifact class has no map by design and the command that writes its `done/reviewed` checkpoint cannot run without one. Observed 2026-07-25: a review of `tanuki-honest-automation.ja` applied nine accepted findings (two blockers), no provenance map existed for the derivation **or** its EN source anywhere under the state root, synthesising one would have re-attested claims the derivation does not own, and hand-writing the checkpoint is forbidden (`skills/review-article/SKILL.md`, #362) — so the run correctly could not report the draft publishable, and the canonical's trailer stayed stale because **the re-entry gate is the sanctioned write that re-stamps it** (#695). **The evidence class is now typed by artifact class:** a draft carrying `adapted_from` re-enters through the derived-canonical path, whose completion evidence is its **ancestry** rather than a provenance map — `lint-ancestry` clean (the pin resolves to a real source at a real content hash), the reviewed content persisted through the **one** canonical write path so the trailer re-stamps, and the checkpoint **recording which evidence class was used** so "reviewed" never silently means two different things. Claim parity remains CAP-2's business, unchanged. This applies the ratified rule that completion evidence is typed by deliverable class, an item whose class has no matching evidence class being born unreachable-done (`consulted: product-lab@34a6119666896f232e1aa00789c3f916bc2b6dad topics/knowledge-architecture.md:73`). **Known cost, stated rather than assumed away:** this is *weaker* evidence than a map — nothing mechanically checks that review-authored sentences introduced no unsourced claim, and #699 is proof that new wording can drift. The risk is carried explicitly, not papered over with a map that would not have caught it either.

> **Amended 2026-07-25 (re-triage, #704)** — the same-day #704 amendment above said **what** the derived class's re-entry evidence is and left **who verifies it** undecided; an implementation attempt then made the gap concrete, so it is settled here. Verifying the pin resolves requires the ancestry lint, and having `review-reentry` invoke it puts `draft-pipeline` in reference to `adapt-canonical` — which **reverses a one-way dependency** (`scripts/adapt-canonical.py:130` loads the pipeline; nothing loads back) and trips CAP-1's boundary guard, which forbids the draft pipeline from so much as *mentioning* adaptation (`scripts/check-canonical-adaptation.sh:252`). **Resolution: the gate verifies what it can reach and REPORTS the rest, exactly as it already does for the authored class.** `review-reentry` itself checks only that the draft carries a **well-formed** `adapted_from` pin, using its own frontmatter reader — no import, no subprocess, no reference across the boundary — and adds `lint-ancestry` to the **required-checks worklist it emits**, the identical status `verify-provenance` holds for an authored canonical: "this command spawns NO judges; it emits the worklist" (`scripts/draft-pipeline.py:5124`, worklist at `:5232`). The invoking skill runs it, as it already runs `verify-provenance`. **Accepted cost, stated rather than discovered later:** the checkpoint is therefore written **before** the ancestry lint is known clean, so a `reviewed` record can exist over a pin that turns out not to resolve. That is weaker than a fail-closed refusal, and it is chosen for consistency with how this gate already treats the check it cannot run — consistency with the existing shape, not a claim that the risk is absent. A **malformed** pin still refuses at the gate; only *unresolvable* is deferred to the reported check. CAP-1's boundary is untouched and its guard stays crude on purpose: a grep for a module name catches what a verb-scoped rule would wave through.

> **Amended 2026-07-25 (triage, #710)** per /triage-gh on inherited packaging routing: CAP-4's inherited-by-design set carried the source's **`syndication` block** verbatim, so `drafts/tanuki-engineering-lessons.ja.md` — a `language: ja` canonical — declared `syndication.devto.canonical_url` pointing at the **English** piece, while its own emission target is zenn. **`syndication` is now DROPPED rather than inherited** — the first stated exception to that set, and it is stated because the field is neither *telling* (which CAP-3 re-decides) nor semantics the articles repo owns (like `date`, OQ3) but **packaging routing for a different canonical**. The ratified chain assigns routing per canonical per language: "variants stay pure per-platform packaging of whichever canonical matches their profile — EN → devto, EN → adapt → JA → zenn" (`consulted: product-lab@34a6119666896f232e1aa00789c3f916bc2b6dad topics/articles.md:55`; reinforced at `:91`, where a *language* mismatch "means the wrong canonical was selected for that profile"). So the EN canonical's dev.to entry is the EN canonical's fact, and carrying it onto the derivation states a route the architecture assigns elsewhere. **Dropped rather than re-declared**, because emission resolves platforms from `syndication.policy.<language>` in config and never reads the draft's frontmatter for them — verified: `variants --list-platforms` returns `available: ["zenn"]` for the ja canonical from config alone. A re-declared block would be a second place the same routing is written **with no reader**, which is the conformance-copy shape declined absent declared precedence and a mechanical mismatch check (`consulted: product-lab@34a6119666896f232e1aa00789c3f916bc2b6dad topics/knowledge-architecture.md:94, topics/articles.md:58`). **Known cost, stated:** CAP-4's clean "everything outside the set is inherited verbatim" rule is now conditional, and the next oddly-fitting field will ask for the same exception — the reason for exception is therefore stated as a *class* (packaging routing belongs to the canonical whose profile it names), not as a field name. The two already-shipped derivations keep their inherited block until re-derived; a change to a derivation is a fresh adaptation, never an in-place edit.

> **Canonical contract.** This SPEC introduces the **adaptation step**: a
> standalone, owner-gated invocation that derives a target-language canonical
> (first target: Japanese) from a reviewed English canonical. It exists to keep
> SPEC-platform-variants honest: variants are *projections* and must stay pure
> packaging, so a platform whose reader differs in language/audience/register
> gets its own **derived canonical** first, and then emits as a same-reader
> variant with no retarget trigger. Where this spec and SPEC-platform-variants
> disagree about the adaptation step, this spec wins; the variant stage's own
> contract is untouched.

# Canonical Adaptation (EN canonical → JA canonical)

## Why

The first real cross-language emission (2026-07-22, `tanuki-engineering-lessons`
→ Zenn) produced a spec-conformant but unpublishable artifact: an approved
Japanese lede over an English title, English headings, and an English body, on a
platform whose profile names a ja-practitioner reader (writing-assistant#574).
The variant contract is "projection, not rewrite" — correctly, because claims
must not drift per platform — so adaptation depth cannot live in the variant
stage. The failure modes this spec prevents: asking the lede-retarget mechanism
to do adaptation work (mixed-language publishes); running the draft flow twice
from source material (forks claim discovery and verification, lets the two
articles' claims drift); and translating mechanically (a JA reader gets an EN
article's structure and framing with Japanese words on it).

The architecture: **the draft flow runs once and produces one source canonical
that owns the claims; adaptation is a separate, per-article, owner-gated
derivation that re-decides how the story is told for a named target reader; the
derived canonical is a first-class canonical the existing variant machinery
consumes with zero changes.**

```
source material ──draft flow──▶ EN canonical ──emit──▶ devto variant   (pure packaging)
                                    │
                                    │ adapt (this spec: owner-gated, per-article)
                                    ▼
                               JA canonical ──emit──▶ zenn variant     (pure packaging)
```

## Capabilities

- **CAP-1 (standalone post-review derivation, owner-gated per article)**
  - **intent:** Adaptation is a separate invocation in the same family as
    `emit variants` — never a stage of the draft flow, never fired implicitly by
    emission. Input is the **persisted, reviewed** source canonical at
    `<output.drafts>/<slug>.md` (zero `[VERIFY]` markers, resolved
    `audience`/`audience_id`); a run-workspace copy is refused with the
    `complete` remedy, exactly as the variant stage refuses one. Whether an
    article gets a JA canonical at all is a per-article owner decision at this
    invocation's gate — there is no standing "always adapt" rule.
  - **The same-reader precondition needs a test that exercises a REAL canonical**
    (added 2026-07-25, #713). Its text above was correct throughout; the
    implementation was not: the equality test reads `audience_id` through a
    frontmatter reader that kept the value's trailing comment, so it compared
    `'en-practitioner'` against
    `'en-practitioner   # pipeline-internal compatibility id …'` and was always
    False. Verified dead 2026-07-25 — `plan --target devto` over a real canonical
    returned a skeleton where this precondition requires a refusal. The reader
    split is fixed engine-wide (SPEC-writing-assistant, "One frontmatter-value
    reading"); what belongs here is that **the suites never tried a same-reader
    target against a comment-bearing canonical**, so a precondition could ship
    dead and stay dead. A test does.
  - **success:** No draft-flow stage and no emission path invokes adaptation;
    an article the owner never chose to adapt has no derived canonical anywhere;
    the invocation over an unreviewed or marker-carrying draft aborts naming the
    remedy.

- **CAP-2 (claims invariant — adaptation re-decides telling, never truth)**
  - **intent:** The derived canonical introduces **no claim absent from the
    source canonical** and drops no load-bearing claim silently; the evidence
    set is fixed. Everything else is free: structure, section order, payoff
    position, framing, register, title. This is the same invariant the
    lede-retarget proposal already carries, widened to the whole artifact.
  - **success:** A claims-conformance check (source canonical vs derived
    canonical) reports additions as defects; a deliberate omission is declared
    in the adaptation record (CAP-3), never implicit.

- **CAP-3 (the adaptation proposal — one gate, per-article depth)**
  - **intent:** The invocation composes an **adaptation plan** and presents it
    under the owner-facing proposal contract — one screen, machine-proposed
    plan plus free-form response, never raw-artifact homework. The plan states,
    per the target profile's named reader: the re-founded opening (what context
    this reader lacks or already has), the structural mapping (which sections
    move, merge, or reorder — e.g. payoff-first for JA tech-article norms vs
    the EN incident-led narrative), register (です/ます for `ja`), terminology
    treatment (technical terms kept in English/established katakana, never
    force-translated), the re-composed title, the **re-composed `summary`**
    (amended 2026-07-25, #700 — a summary is a telling of the article, so it is
    authored for the target reader rather than inherited in the source
    language), and any declared omission.
    Adaptation depth varies per article — a how-to may map nearly 1:1, an
    incident narrative may restructure — so the plan is proposed fresh each
    time; only the invariants (register, terminology convention, CAP-2) are
    standing rules.
  - **success:** The gate's options are approve / modify / stop, each stating
    its concrete effect on the artifact; the owner's answer is recorded in the
    run workspace; no derived canonical is written before the answer.
    **When a derived canonical already exists at the target slug the gate says
    so** (amended 2026-07-25, #705): the presented effect names that file and
    states that it is **replaced**, and when its recorded `adapted_from` pin no
    longer matches the source's current content hash the gate reports the
    **hash pair** — a re-derivation is never presented as a first creation.

- **CAP-4 (the derived canonical is a first-class canonical with recorded
  ancestry)**
  - **intent:** The output is persisted at the resolved `output.drafts` as
    `{slug}.ja.md` with full canonical frontmatter: its own `slug`
    (`{slug}.ja`), `mode: canonical`, `language: ja`, the target
    `audience`/`audience_id`, the **target-language `summary`** authored at the
    CAP-3 gate (amended 2026-07-25, #700; every field outside this re-declared
    set — `date`, `topics`, `related`, `generated_by` — stays inherited from the
    source verbatim, by design, **with one stated exception: `syndication` is
    DROPPED, not inherited** — it is packaging routing belonging to the canonical
    whose profile it names, and the derivation's own platforms resolve from
    `syndication.policy.<language>` in config, never from its frontmatter;
    amended 2026-07-25, #710), and an **ancestry pin**
    `adapted_from: <source slug>@<source hash>` recording the source
    canonical's content hash — the same hash convention the variant trailer
    uses (sha256 over content without trailer), spelled to reuse the
    articles-repo plans' existing `pin: <repo>@<sha>` idiom rather than
    inventing a second ancestry convention (ratified 2026-07-23; `consulted:
    product-lab@e9d11071 topics/articles.md:22, GLOSSARY.md:14`). It carries
    its own `canonical-sha256` trailer like any canonical. It is eligible for
    review as a canonical; claim *verification* does not re-run (claims are
    inherited under CAP-2), review scope is language/framing quality plus
    claims-conformance against the source. **A review round that applies edits
    to it re-enters on ANCESTRY evidence, not a provenance map** (amended
    2026-07-25, #704): the pin **well-formed** (checked by the gate itself),
    `lint-ancestry` **reported as a required check** the way the authored
    class's `verify-provenance` already is — the gate emits that worklist and
    runs neither — the reviewed content persisted through the one canonical
    write path so the trailer re-stamps, and the checkpoint recording which
    evidence class it was written on. Requiring a
    map here would re-attest claims this artifact does not own — the reason
    verification does not re-run in the first place.
  - **success:** `emit variants` accepts the derived canonical by slug with
    zero special-casing; review-article runs over it; the ancestry pin
    resolves to an existing source canonical and hash or a lint names the
    defect. **A re-derivation of a slug that already has a derived canonical
    persists** — the write carries the recorded gate answer as its ownership
    token (amended 2026-07-25, #693) — **while a write over a foreign
    canonical that happens to mint the same slug, with no gate and no
    recorded answer, still refuses by name.**

- **CAP-5 (staleness chains through the derivation)**
  - **intent:** Editing the source canonical marks the derived canonical
    **stale** (recorded hash ≠ current source hash) — a publish blocker for the
    derived canonical *and everything downstream of it*. Re-adaptation is a
    fresh owner decision through this invocation, never an implicit re-run and
    never an in-place edit; the derived canonical's own variants use the
    existing `variant-staleness` mechanism against the derived canonical
    unchanged. The chain is: EN canonical edit → JA canonical stale → its Zenn
    variant stale-by-inheritance.
  - **success:** A staleness check over a derivation whose source moved reports
    the derived canonical and its variants in the blocker bucket with the
    hash pair; a fresh adaptation records the new source hash and clears it.
    **That clearing path is reachable, not merely named** (amended 2026-07-25,
    #693): the fresh adaptation's write is authorized by its own recorded gate
    answer, so a stale derived canonical never sits in `publish_blockers` with
    its only sanctioned exit ending in a collision refusal.

- **CAP-6 (no per-language code path)**
  - **intent:** `ja` is the first target, not a special case: the target
    reader, language, and register come from the same platform-profile /
    declared-target data the variant stage already consumes — adding a second
    adaptation target is declaration, not stage code. The invocation's
    signature is (source canonical, target declaration) → derived canonical.
  - **success:** Grepping the adaptation implementation for a hardcoded
    language branch finds none beyond register defaults already declared in
    profile data.

## Open questions

- **OQ1 — target declaration source.** Whether the adaptation target is named
  by pointing at a platform profile (zenn.yaml already declares
  audience/language) or by a dedicated adaptation-target declaration. Leaning
  profile-pointer (no new declaration type) but the profile is packaging-scoped
  by ratified decision (intent vs packaging, 2026-07-16) — resolve at
  implementation with that boundary in view.
- **OQ2 — review depth for derived canonicals.** Whether the full 9-axis rubric
  or a reduced language/framing + claims-conformance pass applies. CAP-4 sets
  the floor; the ceiling is an owner decision at first real use.
- **OQ3 — what `date` MEANS on a canonical (routed OUT of this spec, not open
  here).** Added 2026-07-25 (#700). Observed on the first derived canonical:
  `tanuki-honest-automation.ja.md` was derived on 2026-07-25 and carries
  `date: 2026-07-24`, the source's. Whether that is correct depends on a
  semantics **no surface declares** — the articles repo's `## Schemas` block
  carries no `date` field for drafts, and this tool's config declares
  `date  # YYYY-MM-DD`, a format (`config/user-config.example.yaml:82`). The two
  readings ("this canonical came into being" vs "the underlying work's date")
  diverge on **every** derived canonical, so the field needs a stated meaning.
  **This spec does not supply it**: the field set a canonical carries is the
  articles-repo schema's contract and this tool is its implementation
  (`consulted: product-lab@34a6119666896f232e1aa00789c3f916bc2b6dad
  topics/articles.md:32`), so declaring it here would be the fait-accompli shape
  that line forbids. The action is an edit to the articles repo's schema block;
  until it lands, `date` is **inherited** (CAP-4) and that inheritance is
  behavior, not a claim about what the field means.
