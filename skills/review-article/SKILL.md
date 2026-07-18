---
name: review-article
description: >
  Review a framework-complete draft article for publication. Invoke as
  "review article" (a draft picker enumerates the repo's candidate drafts;
  a direct draft path is the expert bypass) to run the fixed pass order: lint → structure →
  prose → policy consistency → cold read, each LLM pass once per draft version, emitting capped
  severity-tagged findings (blocker/should/nit) with no rewrites. The owner is
  the sole arbiter of every finding.
---

# Review article

**Name the target repository first (#309).** Before reading any scope, print the
resolved target as the flow's first owner-visible line:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py target --root <host-repo>
```

Relay it as `Operating on host repo: <path>`. A wrong-target run is otherwise
only discoverable after the work is paid for. When an explicit `--root`
disagrees with the session's cwd the resolver notes both on stderr — relay that
line too; `--root` still wins.


Take a framework-complete draft from "review requested" to "publishable" with a
fixed, small number of passes:

```
review article [<host-repo> | <draft>]
```

- **no argument, or a host repo** — the normal form (SPEC-review-ux CAP-1,
  Story 13.31): the owner never types a resolver-internal workspace path.
  Enumerate the candidates through the resolver and present a **picker**:

  ```
  python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py list-drafts --root <host-repo>
  ```

  plus any emitted variants at the resolved `output.drafts` location
  (`resolve-writing-sources.py draft-location`). Show each candidate with its
  metadata — title, article type (**the intent label, never the internal
  id**), created/updated time, and pipeline status (in-progress / complete /
  reviewed). The listing is read-only: it never mutates run state or advances
  a checkpoint. **Exactly one candidate → confirm it and proceed** (confirm,
  never auto-pick). **Zero candidates → report where the pipeline would have
  put one** (the resolver's runs location and the resolved `output.drafts`)
  **and point at draft-article** — never present an empty picker.
- **draft** — a direct path to a framework-complete draft: the expert bypass,
  unchanged (the unit of review is a filled draft, never an outline or idea).

After arbitration completes, how the run closes depends on whether the round
applied any accepted finding:

- **Zero applied edits** (every finding rejected): no re-entry work runs — the
  draft, its provenance map, and any emitted variants are unchanged and no
  stale marking occurs. Checkpoint the review by hand so the picker's status
  column can say "reviewed" on later runs:

  ```
  printf '%s' '{"next_stage": "done", "reviewed": true, "stage": "review"}' | \
    python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py checkpoint --ws "$WS" -
  ```

- **≥1 applied edit**: the edited draft re-enters the gate regime — follow
  *Post-arbitration re-entry* below. The `review-reentry` subcommand writes
  the done/reviewed checkpoint itself; **never hand-write the checkpoint after
  edits** — the subcommand refuses to checkpoint over an invalid provenance
  map, and hand-writing would bypass exactly that refusal (#362).

(Only when the draft came from a run workspace; a direct-path review of an
external draft has no workspace to mark.)

## Starting from a blank repo — the starter template

Reviewing needs a draft, and on a fresh repo there is none. Rather than
hand-writing a schema-valid draft from scratch just to exercise review, copy the
shipped **starter template** — it carries valid `article` frontmatter (`slug`,
`title`, `date`, `mode`, `language`, `summary`, `topics`, `related`) plus the
mandatory pointer block, and it passes `lint-article` **unchanged**, so the shape
is authoritative rather than aspirational:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-writing-sources.py draft-location --root <host-repo>
mkdir -p <resolved output.drafts>
cp ${CLAUDE_PLUGIN_ROOT}/skills/review-article/starter-article.md \
   <resolved output.drafts>/my-first-article.md
```

On a fresh repo the resolved `output.drafts` directory does not exist yet —
resolve it first (there is no default; the command above prints the absolute
location, which may be an external private articles repo, #213), then create it
as shown. It is the one place review-article writes into the
host tree; everything else stays in the run workspace.

Then fill in the frontmatter and replace each section with your own content. The
pointer block in the template uses the example-config site; regenerate it for
your own identity with:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/render-pointer-block.py --language en
```

Run `lint-article` (pass 1 below) on the result before spending a model pass.

## Owner-facing proposals

**Finding class — writing-problem vs missing-input (Story 13.62).** Orthogonal
to severity, each structure/prose/cold-read finding is classified by what can
repair it. A **writing-problem** finding is fixable in the draft and carries a
`Fix:`; a **missing-input** finding diagnoses a source-material gap prose
cannot fill, is marked `[missing-input]`, and names an **upstream remediation**
(`Upstream: re-harvest <target>` or `Upstream: ask <question>`) instead of a
prose fix — it is blocker-eligible and routes to the bounded missing-input
repair hop (SPEC-article-draft-pipeline), never a prose edit. The exact formats
and criteria live in
[`review-prompts.md`](review-prompts.md). Validate an assembled findings block
against the class contract before arbitration — the two shapes are mutually
exclusive:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-review-findings.py <findings-block>
```

A non-zero exit means a finding mixed the shapes (a `[missing-input]` with only
a prose `Fix:`, or a writing-problem carrying an `Upstream:`) — the review pass
that raised it owns the classification; re-author and re-validate.

Arbitration hands each finding to the owner to accept or reject; that
presentation follows the shared
[**owner-facing proposal contract**](../owner-facing-proposal-contract.md)
(`${CLAUDE_PLUGIN_ROOT}/skills/owner-facing-proposal-contract.md`): **where** the
finding sits in the article, **why** it is raised, and accept/reject **choices
whose labels state their concrete effect** on the article — never a shorthand
label the owner must decode. This skill references that one convention rather than
defining its own wording.

The design goal is **maximum defect yield per pass** at a fixed, small cost: the
mechanical checks cost zero tokens, each LLM pass runs **once per draft version**
on a cheap-tier model, and the owner arbitrates all findings in a single round.

## Host-repo footprint (leave nothing behind)

Review **writes no files into the host working tree** — findings are reported to
the owner, never saved as artifacts in the repo. If a pass needs to persist
anything (scratch, a findings log), it goes to the run's **workspace outside the
host repo**, resolved by the path resolver
(`docs/storage-architecture.md` D1–D2), never a path you compose yourself:

```
WS=$(python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py new-run)
```

After a review run the host repo's `git status` shows **nothing new** — no
`scratch/`, no stray intermediate. The plugin's only host-tree footprint across
the whole pipeline is the declared draft products at `output.drafts`.

## Stage 0 — configuration validation

Before any review pass, validate the resolved configuration (CAP-5):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-config.py
```

It **halts** on any unresolved placeholder, malformed URL (e.g. a double-slash
`canonical_url`), or missing required key with a **per-key report naming the file**
(`user-config.yaml` / `writing-sources.yaml`) and the fix — so a configuration
defect is caught up front, before any review work, never surfaced as a late
article-quality finding. A clean config passes **silently**.

## Fixed pass order

Run the passes in this exact order — **lint → structure → prose → policy
consistency → cold read** — and never reorder them:

1. **Lint** (script, zero tokens)
2. **Structure** (LLM, once per draft version)
3. **Prose** (LLM, once per draft version)
4. **Policy consistency** (LLM, once per draft version; runs only when the host
   repo declares a `policy_source` — Story 15.1, SPEC-policy-consistency-pass)
5. **Cold read** (LLM, once per draft version)

**Structure precedes prose** because structural changes (cuts, reordering,
missing sections) invalidate prose feedback — polishing a sentence that a
structural finding later deletes wastes the pass. **Policy consistency runs
after prose** — by then the draft's claims are stable — and **before the cold
read**, which stays last so its context-free isolation is never contaminated
by the policy surface. Each LLM pass runs **exactly once per draft version**;
a pass is not re-run within a cycle. A second full cycle happens only when a
blocker survives arbitration (see *Arbitration*).

## Pass execution — who runs each pass, and what gates what

The skill orchestrates all four passes in the fixed order automatically once
review is invoked; **no pass is skipped at the agent's discretion**. The only
manual step is the owner's single arbitration round at the end.

**Runner per pass** (who actually performs it):

| Pass | Runner | Grounding |
|---|---|---|
| Lint | a **script** the invoking agent runs (`lint-article`) — zero tokens | — |
| Structure | the **invoking agent itself**, acting as the reviewer | repo access |
| Prose | the **invoking agent itself** | repo access |
| Policy consistency | the **invoking agent itself** | repo access + the seam's **bounded policy surface** (`read-policy-source.py`) |
| Cold read | a **separate, context-free model invocation** — a subagent or fresh session given **only the draft** | **none, by design** |

**Cold-read isolation is a mechanism, not a wish.** The cold read must run in a
context that has never seen the sources, the interview journal, or the prior
passes' findings — spawn it as a **separate invocation** (its own subagent /
fresh session) whose entire input is the draft text and the reader rubric. If
the agent that just ran structure and prose "also answers the cold-read
questions" in the same context, the isolation is gone and the pass is void.

**What gates what (halt semantics).** A lint failure does **not** uniformly halt
the review — its findings split into two kinds:

- **Review-precondition failures — these halt.** The unit of review is a
  *framework-complete* draft, so if lint reports residual `[VERIFY]` markers,
  unfilled GATE slots, un-stripped framework-template residue, or no frontmatter
  block at all, the draft is not a well-formed review unit: **stop and report the
  precondition failure** — there is nothing complete to review yet.
- **Frontmatter schema defects on an otherwise-complete draft — these do NOT
  halt.** Missing/extra schema fields, title length, or platform-native
  frontmatter on a content-complete draft are **publish blockers**, not a stop:
  the **structure, prose, and cold-read passes still run** so the owner gets
  content feedback *and* the blocker list in one review round. These blockers
  route to the completion summary's publish-blockers bucket, exactly like a
  configuration defect (they never enter the capped structure/prose findings).

Blocking all content review on a frontmatter defect alone wastes the review of a
content-complete draft; the split above is deliberate.

## Findings contract

Every LLM pass emits **findings only**, in this exact format, one per line:

```
- [blocker|should|nit] {location}: {issue in one sentence}. Why {severity}: {criterion}. Fix: {concrete suggestion in one sentence}.
```

- **Severity** is one of `blocker` (publication-stopping), `should`
  (fix before publishing), or `nit` (optional polish).
- **The `Why {severity}:` rationale field is mandatory** (Story 12.1): it names
  the **criterion** that sets the severity, from the severity criteria table in
  [`review-prompts.md`](review-prompts.md). A finding that asserts a severity
  **without naming its criterion is a contract violation**, not reviewer
  judgment — severity is auditable for consistency, never assigned by unstated
  taste.
- **Capped at 10** findings per pass. If more exist, keep the 10 highest-leverage.
- **Ordered by severity**, and the **single highest-leverage change comes FIRST** —
  each pass leads with the one change that most improves the draft.
- **No rewrites** (never reproduce a rewritten passage), **no praise**, **no
  summary** of the article back to the owner. Output spent on anything but
  findings is wasted.
- **Policy-consistency findings carry no `Fix:` field** (Story 15.1): that pass
  is contradiction detection, never conformity — it pairs the article quote
  with the conflicting policy quote (both with pointers) and **proposes no
  diffs**; resolution is the owner's arbitration call alone.

## Intent anchors (claim & audience)

Two facts about the author's intent anchor this review: the article's **claim**
(the one point it exists to communicate) and its **intended audience**. Resolve
each, in this order:

1. **Interview journal** — when the draft came out of the draft-article
   pipeline, its run workspace holds an interview journal keyed by question id
   (Story 10.4). **The journal's `editorial_anchor` (Story 13.38) is the claim
   anchor when present** — the run's claim/angle answer, possibly
   policy-seeded (`policy_seeded: true`); fall back to the answer to **q2
   (significance — the result that matters most and why)** when the journal
   predates it or records no anchor. The audience anchor is the answer to
   **q5 (audience)**. Every framework's interview asks both. A question the
   journal records as *suppressed* was covered by the fact sheet — use the
   covering entries it names as the anchor. A question recorded as **capped**
   (Story 15.4: displaced by policy-seeded questions under the interview's ≤5
   budget) was **never asked** and has no covering entries — that anchor is
   **absent**: report it as an informational note naming which anchor is
   missing and why (`q5 capped by policy seeds`), run the comparison on the
   anchors that do exist, and never fail or block on the absence.
2. **Owner, once** — for a hand-written draft (no journal), ask the owner the
   two anchor questions at review start — "what is this article's one claim?"
   and "who exactly is it for?" — and use those answers.
3. **Degraded mode** — if the owner is unavailable or declines, run all passes
   anyway, but the cold-read comparison below cannot produce a mismatch
   **blocker**: report its Q1/Q2 answers as **informational** ("the cold reader
   took the claim to be … / the audience to be …") and let the owner judge.
   Never invent an anchor from the draft itself — comparing the draft to
   intent derived from the draft is circular.

## Shared reviewer preamble (structure & prose passes)

Both repo-grounded LLM passes open with this framing, filled from the draft:

> You are a senior engineer skimming {dev.to | Zenn}. You give an article 60
> seconds to earn a full read; your time is scarce and your standards are high.
> The intended reader: {the audience intent anchor}.
> The article's claim: {the claim intent anchor}. Weigh findings against how
> well the article lands THAT claim for THAT reader — the author's recorded
> standards, not generic taste.
> You have repo access — when the draft states a fact about the project, check it
> against the sources before flagging or passing it.
>
> Output findings only. Never rewrite passages. Never praise. Never summarize the
> article back. Cap at 10 findings, ordered by severity, and state the single
> highest-leverage change FIRST.

**Policy-calibrated emphasis (SPEC-policy-editorial-direction CAP-3, Story
13.39).** The anchors above are the run's **policy-derived editorial anchors**
when the journal says so (a `policy_seeded` claim anchor) — passing them into
the structure and prose prompts changes only **what those reviewers weight**,
never the rules: the severity criteria table (`review-prompts.md`) and the
findings format are fixed, and the policy consistency pass is untouched. The
anchors flow to **these two passes only — NEVER to the cold read** (resolved
question 2: the cold read is the control arm; its value is context-free
isolation, and informing it destroys it — the existing isolation contract
already forbids it). When the run's anchors were policy-derived, record the
influence in the review's `consulted:` line (`review-consulted --file` names
the anchor's seed file; the pointer → what-it-shaped grammar is unchanged).

## Model routing

Each pass uses the cheapest tier that can do its job, with the grounding it needs:

| Pass | Model tier | Grounding |
|---|---|---|
| Lint | none (script) | — |
| Structure | Sonnet class | repo access |
| Prose | Sonnet class (Haiku acceptable) | repo access |
| Policy consistency | Sonnet class | repo access + bounded policy surface |
| Cold read | any cheap model | **none — context-free by design** |

Drafting (SPEC-article-draft-pipeline) uses the strongest available model; review
uses cheap bounded passes — one good draft plus cheap reviews beats a cheap draft
plus expensive rescue cycles.

## Pass 1 — Lint (zero tokens)

Run the mechanical lint before any model:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/lint-article <draft>
```

It checks frontmatter conformance to the config `article` schema, title length +
claim verb, pointer-block presence, heading density, dead links, residual
`[VERIFY]` markers, and **un-stripped framework-template residue** — `{slot}`
placeholders, `*(prompt)*` guidance, `[SKIP: …]` / `(~N words)` annotations, and
the renderer's `NOT PUBLISHABLE` marker (an unfilled GATE slot is mechanically
detected here, never left to reviewer discipline) — reporting each with
`path:line` and consuming **no LLM tokens**. Route its output per the halt
semantics in *Pass execution* above: a **review-precondition failure** (residual
`[VERIFY]` markers, unfilled GATE slots, template residue, or an absent
frontmatter block) means the draft is not framework-complete — **stop and report
it**, do not spend a model pass. A **frontmatter schema defect on an otherwise
content-complete draft** is a publish blocker that does **not** halt: fix it
before publishing, but run the content passes now so the owner gets their
feedback in the same round.

**Required frontmatter (know it before you lint).** The required fields come from
the config `frontmatter.schema` — by default `slug`, `title`, `date`, `mode`,
`language`, `summary`, `topics`, `related` (see `config/user-config.example.yaml`),
plus the pointer block. A draft reviewed on a fresh repo must carry these; when
the frontmatter block is absent, the lint names the full required set in one
finding rather than one field at a time. When a repo customizes the schema,
consult its config `frontmatter.schema` — that list, not this default, is
authoritative.

**Configuration backstop (CAP-5, Story 7.4).** The lint pass also re-runs the
stage-0 configuration validation as a zero-token backstop:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-config.py
```

Any configuration defect it reports — an unresolved placeholder, a malformed URL,
or config-caused frontmatter invalidity — is a **publish blocker**: it routes to
the completion summary's publish-blocker bucket (Story 7.5), **never** into the
capped prose or structure findings lists. Configuration is not an article-quality
finding.

## Pass 2 — Structure

Structural review (cuts, reordering, missing/redundant sections) on a
**Sonnet-class model with repo access**, run **once per draft version**. Open with
the shared reviewer preamble, then apply this rubric **in order** — the structural
defects it catches (a deleted section, a reordered argument) would invalidate any
prose feedback, which is why this pass runs before prose.

Check, in order:

1. **Hook** — do the first 3 sentences state the problem or the result, with
   zero credentials or throat-clearing? If they warm up instead, flag it.
2. **One idea** — is there exactly one idea? Two ideas → recommend the split
   point (and that the second becomes its own article).
3. **Section relevance** — does every section advance that one idea? Name the
   sections to cut or merge; a section that does not earn its place is a finding.
4. **Missing load-bearing content** — is anything the stated audience needs
   absent (evidence, limits, quickstart — per the framework used)?
5. **Reader-order** — is the order the reader's (problem → solution → evidence),
   not the author's chronology? A **misplaced section** (e.g. evidence before the
   claim it supports) gets a corresponding finding naming where it should move.
6. **GATE-slot conformance** — do the framework's mandatory GATE slots (the
   **evidence** slot and the **pointer block**) hold real content, not `{slot}`
   placeholders or *(prompt)* text?

Emit findings in the standard contract format (severity, location, issue, fix),
capped at 10, highest-leverage change first. **No rewrites** — name the structural
change; the owner applies it.

## Pass 3 — Prose

Prose review (clarity, tone, hedging, jargon) on a **Sonnet/Haiku-class model with
repo access**, run **once per draft version** — and **only after the structural
pass is settled**, because a structural change would invalidate prose feedback.
Open with the shared reviewer preamble, then apply this rubric:

1. **Unwarranted hedging** — claims softened into mush ("might", "could
   potentially") where the evidence actually supports the stronger statement;
   tighten them.
2. **Unexplained jargon** — terms the stated audience will not know, used without
   a gloss.
3. **Overlong sentences** — sentences over ~30 words doing two jobs; name the
   split point.
4. **Agent-less decision statements** — passive constructions that hide who acted
   ("it was decided", "the approach was changed"); restore the actor.
5. **Buried load-bearing sentences** — paragraphs whose key sentence is buried in
   the middle; name it so the owner can lead with or emphasize it.
6. **Non-native phrasing** — for EN drafts by a non-native author, flag
   unidiomatic phrasing, **but do not sand off voice** — opinions stay
   opinionated; flatten the phrasing, not the stance.

Emit findings in the standard contract format (severity, location, issue, fix),
capped at 10, highest-leverage change first. **No rewrites** — name the prose
issue and a one-line fix; the owner edits.

## Pass 4 — Policy consistency

Contradiction detection against the owner's recorded positions
(SPEC-policy-consistency-pass; the second consumer of the A1 seam). Run **once
per draft version** on a **Sonnet-class model with repo access**, only when the
host repo declares a `policy_source`; if the source is absent or unusable the
pass is **skipped** — one line, never an abort (wiring in Story 15.3).

Read the bounded policy surface through the seam's reader — never any other
path into the policy repo:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/read-policy-source.py --root "$HOST" read
```

The output leads with the run's pin (`pin: <policy-source>@<commit>`) and each
whitelisted file's content line-numbered (GLOSSARY.md, LESSONS.md, ≤2
track-matched topics — the whitelist is code-enforced). Then compare the
draft's checkable claims against the surface and flag **conflicts only**:

- a draft claim that **asserts the opposite** of a recorded position;
- a draft claim a recorded position **declines or supersedes**.

Each finding is **quote-vs-quote** — the article quote with its `path:line`,
the recall-surface quote with its `file:line@commit` at the run's pin — with
severity, criterion `policy-contradiction` (default **should**, never blocker
alone: a flagged reversal may be *correct*), and the issue in one sentence.
**No `Fix:` field, no suggested rewrite** — alignment is never proposed;
whether the article or the recall surface should move is the owner's call in
arbitration. Format (rendering illustrative, fields contractual):

```
- [should] {draft path:line}: {issue in one sentence}. Why should: policy-contradiction.
  article: "{verbatim draft quote}" ({draft path:line})
  policy:  "{verbatim policy quote}" ({file:line@commit})
```

Cap at 10, highest-leverage conflict first. **A draft with no conflicting
claims emits nothing** — no praise, no "policy check passed" summary, no
placeholder. Never show this pass's surface or findings to the cold read.

**Degradation branches on the reader's exit code (Story 15.3)** — the policy
source is an enhancer, never a dependency; no exit code here may abort the
review:

- **0** — run the pass as above.
- **10** (`policy_source` unset) — skip the pass **silently**; every other
  pass runs unchanged.
- **11 / 12** (path missing / not a git repo) — the reader printed exactly one
  `policy_source unavailable: <reason>` line; **relay that one line once**,
  skip the pass, continue. Keep the reason for the `consulted:` line.
- **4** (malformed block) — a stage-0 configuration error slipped through;
  halt and report it like any CAP-5 finding.

**The review run artifact ends with the `consulted:` line (Story 15.3)** —
the same /ask-style audit grammar as the interview seam's, mapping checked
policy lines to the findings they produced:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py review-consulted \
  --pin <policy-source@sha from the reader> --findings <policy-findings.json> \
  --file GLOSSARY.md --file LESSONS.md [--file topics/<matched>.md]
# skipped pass:  … review-consulted --policy-note ["policy_source unavailable: <reason>"]
```

Checked files with no finding close as `(no conflict)`; a skipped pass records
`consulted: none (policy_source unset | unavailable: <reason>)` — every review
run states its policy provenance. Surface the line in the completion summary's
**informational notes**.

## Pass 5 — Cold read

A read by **any cheap model given ONLY the draft** — **no repo access, no project
context, no interview answers** — so it simulates the actual reader and surfaces
missing-context defects the repo-grounded passes cannot see. Do **not** paste the
sources or the prior findings into this pass; that would defeat it. Ask the model
the reader rubric:

1. In one sentence, what is this article's **claim**?
2. **Who is it for**?
3. At which paragraph did you **first get confused**, and why?
4. What did the author **assume you already knew**?
5. Would you **read past the first screen**? Why / why not?
6. What would you **do after** reading it?

**Then compare the cold-read answers to the author's intent** — the two
**intent anchors** resolved above (journal **q2** for the claim, journal **q5**
for the audience; owner-stated for a journal-less draft):

- A **mismatch on Q1 (claim) or Q2 (audience)** against the anchors is a
  **blocker** — the draft does not communicate its own claim or reader, which
  unexplained repo-internal context typically causes. In **degraded mode** (no
  journal and no owner-stated anchors) this comparison has nothing to compare
  against: report the cold reader's Q1/Q2 answers as informational instead —
  never fabricate anchors, and never skip the cold read itself. When exactly
  **one** anchor is absent (a **capped** journal entry — Story 15.4), compare
  the one that exists and report the other side as informational; a partial
  anchor set is a note, never a pass failure.
- **Q3 (confusion) and Q4 (assumed knowledge)** hits are **should-fixes**.
- Q5/Q6 answers inform severity but are not themselves findings.

Emit findings in the standard contract format, capped at 10, highest-leverage
first, no rewrites. This is the final pass; its findings feed arbitration.

## Arbitration

After lint, structure, prose, policy consistency, and cold read have run,
collect their findings into one list and hand it to the owner. The **owner is the sole arbiter**.

**Pinned presentation (SPEC-review-ux CAP-2, Story 13.32) — the round opens
with the consolidated findings list.** This presentation is contract, not
discretion: findings **de-duplicated across passes** (two passes raising the
same defect become one finding **with cross-pass agreement noted as votes**),
each finding **numbered**, **severity-tagged**, **location-anchored**, and
carrying its **one-sentence issue and its fix** — ranked **blockers → should →
nit, highest-leverage first**. The findings **format** itself (capped ≤10 per
pass, severity-tagged, no rewrites — *Findings contract*) is unchanged; this
pins how the consolidated list is shown.

**Reject-only arbitration (SPEC-review-ux CAP-3, Story 13.32).** Acceptance is
the overwhelming default, so the interaction costs attention only for
exceptions. **Ordinary findings** — lint, structure, prose, cold-read, every
severity — **default to ACCEPTED**: ask the owner **once**, "these N findings
will be applied — deselect any to reject" (a multi-select; an empty selection
= apply all). Presentation still follows the
[owner-facing proposal contract](../owner-facing-proposal-contract.md) —
**where** it sits in the article (the finding's `{location}`), **why** it is
raised, and choices whose labels state their **concrete effect on the article**:
keeping a finding selected means "apply the fix to the article", deselecting
means "leave the article unchanged" — never a bare accept/reject the owner
must decode. This is a presentation wrapper only: it **does not change** the
capped (≤10), severity-tagged findings **format** from *Findings contract*.
Two exceptions stay explicit, never defaulted:

- **policy-contradiction findings** keep their three-way choice (below) — no
  safe default exists: defaulting to "fix article" would auto-align the
  article to policy (SPEC-policy-consistency-pass forbids it), defaulting to
  "dismiss" would bury the tension the seam exists to surface;
- **a finding whose fix would alter owner-approved content** (an approved
  interview answer used as a sourced claim, an approved visual — NFR12) is
  asked explicitly.

Every finding still receives an **explicit recorded disposition** —
accepted-by-default is journaled as *accepted*; the journal and summary stay
complete.

**The single arbitration round.** One pass over the consolidated list:

- **No finding is skipped and none is auto-applied.** Apply an accepted fix
  yourself, or via **one targeted edit instruction per finding**; never
  open-ended rewriting.
- **A rejected finding is rejected.** Do **not** re-litigate it in a later pass or
  a second cycle — the decision stands.
- The round is **top-down and single-pass** over the ranked list: the
  highest-leverage findings are resolved before the nits.

**Arbitration events — one emit per disposition (SPEC-article-review CAP-5,
Story 13.42).** When the round completes, persist every finding's disposition
as a **raw dogfood event** — this is how the reviewer gets calibrated against
its own acceptance history (a chronically-rejected criterion surfaces through
the dogfood tool's recurrence bar as a "tune or demote this pass" proposal;
that analysis never runs here). Build one JSON line per arbitrated finding —
`{"pass", "criterion", "severity", "disposition", "reason"?}`, `reason`
required on `rejected` — and emit:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/emit-arbitration-events.py <dispositions.jsonl> \
  --ws "$WS" --scenario <draft-slug>
```

Exactly N events for N findings, **nothing judged or classified at emit time,
no new report**. The events always land in `$WS/arbitration-events.jsonl`;
when the owner's user config declares an optional `dogfood.ingest_cmd`, the
emitter also feeds them to the dogfood ledger — absent or failing, it logs
one line and the run continues (enhancer, never a dependency; the workspace
file remains for offline mining).

**Policy-consistency findings arbitrate with three choices (Story 15.2).** A
`policy-contradiction` finding is contradiction detection, not a fix proposal,
so its choices differ from accept/reject — each label stating its concrete
effect:

- **Fix article** → "edit the article to resolve the conflict" — the owner
  edits (or gives one targeted edit instruction); never auto-applied;
- **Position moved** → "the article stands; record the reversal for the recall
  surface" — the run emits a **staging-candidate block** (the Story-14.5
  emitter, `--findings` form) into the run workspace for the owner to
  hand-copy into the hub's staging area; the draft text and its "publishable"
  eligibility are unchanged;
- **Dismiss** → "no effect" — recorded as dismissed.

After the round, emit the position-moved blocks in one call:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py staging-candidates \
  --findings <arbitrated-findings.json> --source-repo <host repo name> \
  --created <run date> [--tag <track>] > "$WS/staging-candidates.md"
```

An **unarbitrated or open policy finding never blocks "publishable"** —
criterion `policy-contradiction` is never blocker alone (a flagged reversal
may be correct); escalation is a per-finding owner call inside the round, and
nothing under `policy_source.path` is ever created or modified.

**Rubric-mapped findings are blocker-eligible (Story 12.2).** A structure or
prose finding that **maps to a quality-rubric dimension** (Epic 11: narrative
arc, paragraph flow, explanation calibration, readability mechanics — the same
dimensions a blocker's `Why blocker:` rationale names, per Story 12.1) is
**blocker-eligible**: it may be assigned `blocker`, exactly as a cold-read Q1/Q2
mismatch or a configuration defect. Review is a real **second net** for the
Stage 3→4 quality gate, not merely advisory — a rubric violation that slipped the
gate is a publication-stopping finding here.

**Second-cycle gate.** After the round:

- If a **blocker-severity finding survived** the fixes (the canonical cases: a
  cold-read **claim/audience mismatch**, or a **rubric-mapped structure/prose
  blocker**, still present after edits), trigger
  **exactly one additional full cycle** — lint → structure → prose → cold read
  again on the new draft version. **One** — the workflow never loops unbounded.
- **Otherwise the draft is publishable.** No surviving blocker ⇒ done — **unless
  an open rubric-mapped blocker or a configuration blocker remains**, in which
  case review does **not** report the draft "publishable" until it is fixed (the
  zero-token lint pass re-checks configuration as the backstop to Story 7.4).

**Per-pass model routing (recap).** Each pass runs on the tier and grounding in
the *Model routing* table above: **lint** is the zero-token script; **structure**
and **prose** run on a **Sonnet-class model with repo access** so claims are
checked against the sources; **cold read** runs on **any cheap model, context-free
by design**. The second cycle, if triggered, uses the same routing.

## Post-arbitration re-entry (rounds that applied edits)

An arbitration round that applied **≥1 accepted finding** does not end at the
edit — the edited draft **re-enters the provenance/quality regime** before
anything is reported done (SPEC-article-review, "Post-arbitration re-entry"
constraint, 2026-07-18; origin #362: a run shipped 5 anchors dangling on blank
lines under a done/reviewed checkpoint, unclassified review-authored sentences,
and an auto re-emitted variant). Run these steps **in order** after applying
the accepted findings:

1. **Rebuild the provenance map for the edited draft.** Every sentence of the
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
3. **Re-run the quality gate's mechanical dimensions** when a
   **rubric-mapped** finding was applied (`draft-pipeline.py quality-gate
   --draft <edited> --map <rebuilt>` — mechanical dims only; the dim1-2 judge
   verdicts are not re-bought). Any failure from step 2 or 3 surfaces as a
   **publish blocker**, never silently.
4. **Invoke the re-entry gate**, which persists the reviewed canonical (the
   same write path and emission-trailer convention as the draft flow's
   `complete` gate), structurally validates the rebuilt map against the edited
   draft, reports the required scoped checks, marks existing variants stale,
   and writes the `done/reviewed` checkpoint — **refusing (non-zero, no
   checkpoint) when the map is invalid**:

   ```
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py review-reentry \
     --draft <edited-draft> --map <rebuilt-map> --slug <slug> \
     --root <host-repo> --ws "$WS" --applied <n> [--rubric-applied]
   ```

   Pass `--rubric-applied` when a rubric-mapped finding was applied. With
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
