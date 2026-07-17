---
id: SPEC-policy-realignment
companions: []
sources:
  # Policy-alignment review of this repo's specs/docs against the owner's
  # pinned recall surface (owner decision record — 2026-07-16). Ratifying owner
  # decision records are held in the owner's private knowledge hub,
  # retrievable by date + title. Mechanism public, provenance private.
---

> **Findings contract, not a build contract.** This spec records where this
> repository's specs and docs have drifted from the owner's ratified policy,
> found by a policy-guarded alignment review on 2026-07-16. Each finding is
> quote-vs-quote (repo line ↔ recorded position), severity-tagged
> (blocker / should / nit), and carries the amendment that would close it.
> **Nothing here is auto-applied** — the owner arbitrates each finding
> (fix / position moved / dismiss), the same three-way contract as the
> policy-consistency pass. A "position moved" verdict routes back to the
> recall surface as a staging candidate, and the finding closes without a
> repo change.

# Policy realignment — 2026-07-16 review findings

## Why

The repo's specs check policy at ratification time (each RATIFIED spec folds
its constraints in), but three same-day owner decisions (2026-07-16) landed
after the specs they touch were last amended, one executed migration left a
companion file describing removed config keys, and two files predate the
publication-boundary discipline the repo itself later ratified. Per the
owner's recorded position that a spec must carry its own policy so
implementation runs clean ("check policy where the decision is made";
owner lesson, recorded 2026-07-16), these gaps are spec defects, not implementation
bugs.

## Findings (ranked)

### F1 — [should] Review-arbitration event emission is ratified, but the spec still carries it as an open proposal

- **repo:** `specs/spec-article-review/SPEC.md:67` — "**Owner proposal
  (2026-07-16 …) — persist arbitration outcomes as dogfood events.** …
  Proposal-only: adopting it means one emit call in the arbitration step;
  declining leaves reviewer calibration to memory."
- **policy:** owner decision record 2026-07-16 (review pipeline complete):
  review-article was declared COMPLETE **after one addition** — arbitration
  outcomes persisted as dogfood events (source: `review-arbitration`; fields:
  pass, criterion, severity, disposition, reject reason), with demotion
  analysis riding the dogfood tool's existing chronic bar.
- **issue:** the decision is ratified, not pending; leaving it as an Open
  Question re-opens a closed gate and means the implementation order for the
  emit call has no spec constraint to cite.
- **amendment:** move the emission contract out of Open Questions into a
  capability (or constraint) of SPEC-article-review — one emit per finding
  disposition, raw events only, no classification at emit time, no new report
  — and annotate the same decision's disposition of the other open question:
  multi-provider cold read, outcome binding, and pass tuning are **deferred
  behind demand triggers / the captured arbitration data**, not undecided.

### F2 — [should] The working-note (newsletter) direction is ratified, but the frameworks spec still carries it as an undecided proposal — and its constraints are nowhere in this repo

- **repo:** `specs/spec-article-frameworks/SPEC.md:59-72` — "**Owner proposal
  (2026-07-16 …) — a fifth, lightweight 'working-note' framework.** …
  Proposal-only: adopting it means adding the framework here …; declining
  leaves newsletter assembly manual." Also `SPEC.md:37`: "Category set is
  fixed to the four above" stands unamended.
- **policy:** owner decision record 2026-07-16 (content architecture):
  working notes **are** writing-assistant products — own small canonical
  draft, email + web-archive renderings via the variant machinery, a
  lightweight framework paired with a slim pipeline profile; sources are the
  active repos plus the owner's recall surface via the existing policy-seam
  mechanics, lessons first; the hub's Q&A history is **never a harvest
  source** (promotion is the only path); published text carries public links
  only.
- **issue:** the direction is ratified while the spec says "proposal-only",
  and three ratified constraints (recall surface read via seam mechanics
  lessons-first; history-archive never a harvest source; public-links-only in
  published text) are recorded nowhere in this repo — the later
  implementation order would run without them, exactly the drift the
  spec-carries-its-policy rule exists to prevent.
- **amendment:** amend SPEC-article-frameworks (fifth framework, category-set
  constraint updated) and add the slim-profile contract to
  SPEC-platform-variants, folding all three constraints in verbatim.
  Implementation timing stays free; decision status must not be understated.

### F3 — [should; blocker at the OSS-release gate] Owner-specific hub name and hub-layout details sit in repo files, against the repo's own publication-boundary constraint

- **repo:** `config/writing-sources.example.yaml:40` and `:52` — the owner
  hub's real name appears literally, once as a parenthetical after "your
  policy repo" and once as the example `path:` value (quotes withheld here so
  this findings spec passes the boundary lint it invokes);
  `skills/draft-article/SKILL.md:273,460,488,492` and
  `skills/review-article/SKILL.md:411,456,562` (the pin format hardcodes the
  owner's hub name; the staging-candidate instructions name the hub's
  internal staging directory).
- **policy:** this repo's own C8 (`specs/spec-repo-onboarding/SPEC.md:98-100`):
  "the skill and its docs describe the mechanism generically ('your policy
  repo'); owner-specific paths appear only in generated private config, never
  in repo files." Backed by the owner's publication-boundary position
  (repo boundaries follow publication boundaries;
  owner lesson, recorded 2026-07-16) and the ratified precedent that the sibling
  dogfood tool genericized the identical seam for publication (neutral
  defaults in repo files, the owner's real pointer in private machine-local
  config).
- **issue:** the seam's own companion already models the correct form
  (`seam-formats.md` uses the neutral `../policy-hub`); the example config
  and both SKILL files leak the owner's hub name and internal layout. Today
  the repo is private, so this is `should`; the dogfooding-gate release path
  makes it a mechanical blocker on the release checklist — and scrubbing
  later costs history rewriting, which is the failure the boundary rule
  exists to prevent.
- **amendment:** genericize to the seam-formats form (`your policy repo`,
  `../policy-hub`, `pin: <policy-source>@<commit>`, "the hub's staging area /
  intake directory"); the owner's real path stays where it already lives —
  generated machine-global config. Add the grep to
  `check-generic-engine.sh`'s static list so the boundary is enforced, not
  remembered.

### F4 — [should] Companion `seam-formats.md` still documents the removed `track`/`topics` config keys as valid

- **repo:** `specs/spec-policy-source-seam/seam-formats.md:10-20` — the
  `policy_source` block shows `track:` and `topics:` keys with "`topics`
  length ≤ 2" validation; `:71` seeds staging-block tags from `<track>`.
  The seam SPEC's own body (`SPEC.md:27-28,67-69`) still describes the keys
  and the superseded one-repo-one-track assumption without a local
  annotation.
- **policy:** SPEC-policy-topic-at-draft CAP-3 (RATIFIED 2026-07-15) — keys
  demoted then **removed**; executed per Story 13.36:
  `config/writing-sources.example.yaml:48-50` now states "The former track /
  topics keys were removed …; a leftover key is reported as a named
  configuration error."
- **issue:** a reader authoring config from the seam companion produces a
  named configuration error; the companion contradicts both the ratified
  spec and shipped behavior. The owner's recorded position is that a copy
  drifting in content is exactly why pointers beat copies
  (owner lesson, recorded 2026-07-16) — where the format must be restated, it must
  be restated current.
- **amendment:** update seam-formats §1 to the path-only block plus the
  per-run topic-selection pointer (SPEC-policy-topic-at-draft CAP-2), fix
  §3's `tags:` derivation, and annotate the seam SPEC's CAP-1/CAP-2 wording
  and Assumption 1 in place (the top-of-file amendment note exists but the
  contradicted lines carry no local mark).

### F5 — [nit] The profile intent-key rejection is documented in config/README but absent from the spec it cites

- **repo:** `config/README.md:33-34` — "a profile that declares
  `mode`/`canonical`/`syndication` is rejected (SPEC-platform-variants
  CAP-2)"; `specs/spec-platform-variants/SPEC.md` CAP-2 declares the
  exhaustive packaging enumeration but never states the stage-0 rejection of
  intent keys.
- **policy:** owner decision record 2026-07-16 (Epic 16 story review):
  stage-0 validation rejects intent keys in profiles.
- **issue:** the README cites the spec for a contract the spec does not
  carry — inverted authority; the ratified rejection should live in the
  contract, with the README as its view.
- **amendment:** add the intent-key rejection to SPEC-platform-variants
  CAP-2's success criteria (stage-0 configuration error naming the key and
  its user-config home).

### F6 — [nit] Owner-facing docs lead with framework IDs that ratified UX demoted to an expert alias

- **repo:** `README.md:147` — "`draft article <F1-F4> from <sources>`" as
  the primary documented invocation (and the skill's advertised invocation
  string).
- **policy:** SPEC-draft-article-ux CAP-1 (RATIFIED 2026-07-15): article
  type is chosen by intent label; framework IDs "never appear in an
  owner-facing question, proposal, or summary"; the ID form is the
  internal/expert alias. Internal vocabulary reaching the user surface is a
  lintable defect class (owner lesson, recorded 2026-07-16).
- **issue:** the README is an owner-facing surface; it leads with the
  internal form. (Specs, `pipeline-stages.md`, and
  `docs/article-frameworks/README.md` may keep IDs — they are the internal
  contract surface.)
- **amendment:** when stories 13.27-13.30 land, flip the README's Usage
  section to intent labels first with the `F1-F4` form documented as the
  expert alias.

## Non-goals

- No retro-editing of ratified decision records or closed decision history —
  amendments above are forward spec/doc edits under each spec's own
  amendment convention.
- No behavior changes beyond what the cited ratified decisions already
  ordered; this spec adds zero new design.
- No writes toward the owner's policy hub (seam invariant): where a finding's
  arbitration outcome is "position moved", the route is a staging-candidate
  block, owner-copied.

## Success signal

Each finding carries an owner disposition; every "fix" disposition lands as
an amendment note in the named spec/doc; F3's grep is enforced by
`check-generic-engine.sh`; a re-run of the same alignment review against the
then-current recall surface returns zero findings.
