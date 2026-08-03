# Review article — re-entry & report

Companion of [`SKILL.md`](../SKILL.md) (the dispatcher). Read after an
arbitration round: post-arbitration re-entry (by artifact class), the
before/after comparison, and the completion summary.

## Post-arbitration re-entry (rounds that applied edits)

An arbitration round that applied **≥1 accepted finding** does not end at the
edit — the edited draft **re-enters the provenance/quality regime** before
anything is reported done (SPEC-article-review, "Post-arbitration re-entry"
constraint, 2026-07-18; origin #362: a run shipped 5 anchors dangling on blank
lines under a done/reviewed checkpoint, unclassified review-authored sentences,
and an auto re-emitted variant). Run these steps **in order** after applying
the accepted findings:

**Which steps apply is decided by ARTIFACT CLASS (#704).** A **derived
canonical** — one carrying `adapted_from` — owns no claims of its own (they are
inherited, SPEC-canonical-adaptation CAP-2), so it has **no provenance map** and
steps 1–2 below do not apply to it: its re-entry evidence is its **ancestry**,
and `review-reentry` takes **no `--map`** for it. Do not synthesise a map for a
derivation — that would re-attest claims it does not own.

**You run the ancestry lint; the gate only names it (#704).** `review-reentry`
verifies the pin's **shape** and then reports `lint-ancestry` in its
required-checks worklist — the same status `verify-provenance` has for an
authored draft, and for the same reason: this command emits worklists and runs no
checks. So run it yourself over the edited derivation:

```
python3 /home/tomoya/work/writing-assistant/scripts/adapt-canonical.py lint-ancestry \
  --derived <edited-draft> --root <host-repo>
```

A defect it names — malformed pin, unresolvable slug, a hash matching no source
content — is a **publish blocker**, and note the ordering honestly: the
`done/reviewed` checkpoint is written *before* this runs, so a failure here means
a reviewed record exists over an ancestry that does not resolve. Report it as a
blocker rather than treating the checkpoint as absolution. The evidence rule is
defined once in CAP-4 and not restated here; the steps below are the **authored
canonical's** path. Step 4 binds both classes, and the checkpoint it writes
records which evidence class the run used.

1. **Rebuild the provenance map for the edited draft** (authored canonicals).
   Every sentence of the
   edited draft is classified — **review-authored sentences (wording an
   applied fix introduced) are classified like any other sentence** (sourced /
   derived / narration / verify), so the zero-unmarked-claims guarantee
   survives review. Every position carries a line anchor (`P1.S1[L7]`) into
   the edited draft.
2. **Re-run verify-provenance with a FRESH isolated judge** on the rebuilt map
   and the edited draft. The fail-closed attestation (Story 13.67) binds a
   verdicts file to the draft's content hash — the pre-edit judge's
   attestation no longer matches the edited draft, so **a fresh judge run is
   the only way back to PASS**; re-presenting the old verdicts fails closed.
3. **Re-run the quality gate's mechanical dimensions AND persist the versioned
   verdict record** when a **rubric-mapped** finding was applied. The re-run
   gate writes its **full four-dimension verdict record** (dim1/dim2, dim3 with
   its inventory stamp, dim4 with measured values — the same completeness
   contract as the draft-flow gate's `rubric-verdicts.txt`, Story 18.18/#492)
   to the **versioned** `rubric-verdicts-v2.txt` in the run workspace, so the
   re-run gate's outcome is verifiable from an artifact and never asserted in
   the completion summary's prose alone (#496):

   ```
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py quality-gate \
     --draft <edited> --map <rebuilt> \
     --verdicts-out "$WS/rubric-verdicts-v2.txt"
   ```

   When the framework declares evidence types, pass `--framework-file` and a
   **fact-sheet-carrying** `--state` — the consume output or a pre-completion
   checkpoint, **never the terminal `done` checkpoint**, which drops
   `fact_sheet`: the gate refuses an emptied substrate with a named error
   rather than reporting a false evidence gap (Story 19.14, #751).

   ```
   ```

   The mechanical dims (3-4) are re-scanned; the dim1-2 judge verdicts are not
   re-bought. Any failure from step 2 or 3 surfaces as a **publish blocker**,
   never silently.
4. **Invoke the re-entry gate**, which persists the reviewed canonical (the
   same write path and emission-trailer convention as the draft flow's
   `complete` gate), structurally validates the rebuilt map against the edited
   draft, reports the required scoped checks, marks existing variants stale,
   **re-projects the article plan** (Story 19.17, #757 — an authored
   canonical's `plans/<slug>.md` is re-emitted as a deterministic projection
   of the reviewed canonical: `audience` mirrored, `sections` re-derived from
   the edited draft's headings, everything plan-owned carried unchanged; a
   projection failing the plan writer's validation refuses the checkpoint, and
   the JSON's `plan_reprojection` is relayed in the completion summary; a
   derived canonical or a plan-less slug skips with a note),
   and writes the `done/reviewed` checkpoint — **refusing (non-zero, no
   checkpoint) when the map is invalid, when `--rubric-applied` but the
   versioned `rubric-verdicts-v2.txt` from step 3 is missing or partial** (a
   re-entry may not claim PASS over an unpersisted/partial verdict record,
   #496), **or when the arbitration record and the workspace write record do
   not reconcile by finding id** (#1396, Story 20.210 — it reads
   `$WS/arbitration-events.jsonl` against the carrier's `review-apply`
   commits *before* persisting anything, so an accepted finding whose edit
   silently did not happen, or a write claiming an acceptance nobody
   recorded, stops the one host write from landing; the edited draft you pass
   is the workspace copy, `$WS/draft.md`):

   ```
   # authored canonical — evidence is the rebuilt provenance map
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py review-reentry \
     --draft <edited-draft> --map <rebuilt-map> --slug <slug> \
     --root <host-repo> --ws "$WS" --applied <n> [--rubric-applied]

   # derived canonical (carries `adapted_from`) — evidence is its ancestry; NO --map
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py review-reentry \
     --draft <edited-draft> --slug <slug>.<language> \
     --root <host-repo> --ws "$WS" --applied <n> [--rubric-applied]
   ```

   Pass `--rubric-applied` when a rubric-mapped finding was applied — the gate
   then requires the complete `rubric-verdicts-v2.txt` written in step 3. With
   `--applied 0` the command is a strict no-op — but a zero-edit round should
   use the hand-written checkpoint above and skip this section entirely.
5. **STOP. Review never emits or re-emits a variant** (SPEC-platform-variants
   CAP-3). Existing variant files stay untouched on disk; the staleness check
   inside `review-reentry` reports them stale, and the completion summary
   lists them under **publish blockers** with the re-emission path. Re-emission
   is a **fresh, explicit owner publish decision** through the standalone
   variants flow (`skills/draft-article/variants.md`):

   ```
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py variants --slug <slug>
   ```

A run that skips any of these steps may not report the draft "publishable".

## Before/after comparison (report time — CAP-6)

A round that applied edits owes the owner a concrete answer to *what did review
do?* — not the change-list prose (which reports **intent**, not the actual
edits, #495). Compute the **before/after diff** from the pre-arbitration
workspace snapshot taken at review start against the applied draft, and present
it **in-conversation** with the applied change list:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py review-diff \
  --before "$WS/pre-arbitration-<slug>.md" --after <edited-draft> --slug <slug>
```

The command **reads only its two inputs and writes nothing** — it **never writes
the destination repo** and creates no `reviews/` artifact (footprint invariant).
Show the returned `diff` and `change_list` **in the conversation** — this is the
owner's comparison surface (interaction contract, CAP-6/#226); the snapshot and
draft **paths are printed informationally only**, never a file the owner must
open to proceed. The diff underlies the completion summary's change list below;
an `identical` result means arbitration applied no edit this run.

## Completion summary

End every review run with the shared
[**completion summary**](../completion-summary.md)
(`${CLAUDE_PLUGIN_ROOT}/skills/completion-summary.md`): the three labelled buckets
— **informational notes**, **publish blockers**, **optional cleanup** — then an
explicit **next step presented as an in-conversation choice** (e.g. "apply the
accepted findings, then re-run review" or "the draft is publishable" —
interaction contract, CAP-6/#226: no step may require the owner to open a
machine-state artifact to proceed).

**The informational bucket leads with the editor's assessment (SPEC-review-ux
CAP-4, Story 13.33)** — a concise editorial verdict, **~3–5 sentences**, on
what the review did to the article's **argument and reader experience**: which
defect class most threatened the **stated audience's trust**, what the
**highest-leverage change bought**, and what the article **now does that it
did not before**. It **cites finding numbers** (from the consolidated
arbitration list), never rewritten prose; **no praise padding** — it is a
verdict, not a compliment. The assessment is composed from the run's own
arbitration record — **no new pass and no new model spend** beyond the summary
the run already writes. The **change list** (what was edited, per accepted
finding) is **demoted to reference below it**, complete but secondary. A surviving blocker-severity finding — including a
**rubric-mapped structure/prose blocker** (Story 12.2) — an unresolved
`[VERIFY]` marker, an unrendered figure, or a **configuration defect**
(placeholder, malformed URL, config-caused frontmatter invalidity) goes under
**publish blockers** and nowhere else — a config defect is never routed into the
capped prose/structure findings lists. Because review works on an **article body**, the informational
bucket includes a **reading-time estimate**:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/reading-time.py --language <en|ja> <draft>
```

**Stale variants (rounds that applied edits).** When the re-entry gate ran,
list its `stale_variants` under **publish blockers**, each with the re-emission
path: `variants --slug <slug>` (the standalone flow,
`skills/draft-article/variants.md`) — re-emission is the **owner's fresh
explicit publish decision**, never something review performs. The review run
emitted no variant; it never does.

**Quality-gate dimension count (Story 18.21, #496).** When the summary reports
the re-entry quality-gate outcome, the dimension count is **the rubric's own**
— quote `review-reentry`'s `rubric_dimensions` field (derived from
`skills/draft-article/quality-rubric.md`, currently **four**), **never a
hardcoded literal** like "all six dimensions". The re-run gate's verdicts live
in the versioned `rubric-verdicts-v2.txt` it persisted; a PASS claim over a
missing or partial v2 record is impossible because the re-entry gate refused
before writing the checkpoint. See
[`completion-summary.md`](../completion-summary.md).
