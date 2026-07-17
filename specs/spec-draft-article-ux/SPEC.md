# SPEC — draft-article owner-facing UX (intents, interview capture, visual dialogue)

**Status: RATIFIED (2026-07-15, owner, via /triage-gh on #228) — decomposed into stories 13.27–13.30.**
Origin: owner feedback after the 2026-07-15 QSB F1 run. Three defects share
one root cause: internal contract vocabulary and agent presentation
discretion leaking into the owner-facing surface.

## Problem

1. **Framework IDs are user-facing.** The invocation contract and the visual
   proposal say "F1" to the owner. F1–F4 are slot-contract names — internal
   implementation details the owner should never need to decode.
2. **The interview's presented form is not captured.** The journal records
   triage outcomes, seeds, and dispositions, but NOT the questions as
   actually presented — option labels, repo-grounded recommended answers,
   previews, batch ordering. The owner wants to meta-analyze interview
   quality (question quality, choice quality, elicitation effectiveness)
   with a strong model; the artifact that analysis needs does not survive
   the run.
3. **The visual slot jumps to approval.** The declared-visual proposal opens
   with a finished Mermaid source ("approve/modify/decline") without first
   asking what the visual should communicate — the intent decision that the
   fallback ladder (table vs. diagram) itself depends on.
4. **Interview presentation order is agent discretion.** Question selection
   is code-fixed (bank, triage, GATE-slot priority, ≤5 cap in
   `draft-pipeline.py`); how questions are grouped, ordered, and labeled in
   the ask is not.

## Capabilities

- **CAP-1 — intent-shaped article-type selection.** The owner chooses an
  article type by intent label — "introduce the project", "share
  engineering lessons", "explain the evaluation methodology", "survey a
  research area" — with a repo-grounded recommendation (e.g. tagged release
  present → intro viable; none → the intro GATE's own rule already
  redirects to lessons). Framework IDs remain in specs, filenames, and run
  state; they never appear in an owner-facing question, proposal, or
  summary. Invocation accepts the intent label; the ID form keeps working
  as the internal/expert alias.
- **CAP-2 — presented-payload capture.** Every owner-facing ask (interview
  questions, visual proposals, verification items) persists its payload
  verbatim to the run workspace at ask time
  (`$WS/presented-payloads.jsonl`, one record per ask: the full question
  set, option labels, descriptions, previews, recommended answers, and the
  owner's selection + free text). This is the meta-analysis substrate: a
  later "review the interview itself" pass reads payloads + journal +
  answers and needs nothing from the drafting context. No new tooling is
  built for the analysis itself — the capture is the deliverable; the
  analysis is a prompt over run state.
- **CAP-3 — visual intent before visual source.** The declared visual slot
  is proposed in two steps under the proposal contract: (1) *intent* —
  "what should a visual in {section} communicate?" with draft-grounded
  options (e.g. pipeline flow / comparison / timeline / none needed), the
  fallback-ladder table-vs-diagram choice made here; (2) *source* — the
  concrete Mermaid/table/figure-spec for the chosen intent,
  approve/modify/decline as today; the payload's preview is a plain-text
  structural sketch, with the concrete source written to the run workspace
  and referenced by path (amended 2026-07-17, #307 — proposal-contract
  section (g); raw fenced source never appears in the payload). Declining
  at step 1 skips step 2 and
  omits the slot (no residue, unchanged). Opportunistic extras (≤2) follow
  the same two-step. Element-level sourcing rules (CAP-3 of
  SPEC-article-visuals) are unchanged.
- **CAP-4 — pinned interview presentation order.** Presentation order is
  contract, not discretion: claim/angle first (the policy-seeded tension
  question when one exists — it reframes every later answer), audience
  second, then headline/significance, then color (surprise, tradeoff).
  Within that order, batching is free; ordering is not. The order is
  documented in the skill and echoed in the journal so a mis-ordered run is
  attributable.
- **CAP-5 — evidence fallback question.** The bank gains one conditional
  entry: when harvest yields no `number`/`result` fact-sheet entry, ask
  "what result or worked example would convince a skeptical reader?"
  (topic: significance, feeds the evidence GATE). Asked only on that
  condition — the GATE currently has no interview fallback and fails late
  at Stage 3 instead.

## Constraints

- CAP-2 captures payloads exactly as shown — no normalization, no
  summarization; it is an append-only log in the run workspace, never the
  host tree.
- CAP-1 changes vocabulary only; the closed framework set, GATE slots, and
  slot contracts are untouched.
- CAP-4's order applies to *presentation*; selection priority (NEEDS-OWNER
  first, policy seeds, generic; one slot reserved for the highest-priority
  valid tension item when any exist — amended 2026-07-17, #302; GATE-slot
  tie-break; ≤5 cap) is otherwise unchanged.
