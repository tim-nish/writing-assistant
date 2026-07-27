# Review article — the five passes

Companion of [`SKILL.md`](../SKILL.md) (the dispatcher). Read on entry to the
**pass phase**: the fixed order, halt semantics, the findings contract, intent
anchors, the shared preamble, model routing, and passes 1–5.

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
  unfilled GATE slots, or un-stripped framework-template residue, the draft is
  not a well-formed review unit: **stop and report the precondition failure** —
  there is nothing complete to review yet. These are *body-incompleteness*
  signals; a missing frontmatter block is not one of them (see below).
- **Frontmatter defects on an otherwise-complete draft — these do NOT halt.**
  Missing/extra schema fields, title length, platform-native frontmatter, **and
  a missing frontmatter block entirely** are **publish blockers**, not a stop:
  `lint-article` reports the absent block as `schema` findings (naming the full
  required field set, #143) and still runs every body check, so the body is
  reviewable. The **structure, prose, and cold-read passes still run** so the
  owner gets content feedback *and* the blocker list in one review round. These
  blockers route to the completion summary's publish-blockers bucket, exactly
  like a configuration defect (they never enter the capped structure/prose
  findings).

Blocking all content review on a frontmatter defect alone — including a wholly
absent frontmatter block — wastes the review of a content-complete body; the
split above is deliberate. A missing frontmatter block is a `schema`-category
finding (the most extreme one), not a body-incompleteness signal, so it is a
publish blocker the content passes run alongside, never a halt.

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
7. **Declared-convention conformance — derived canonicals only** (Story 20.4,
   #800). When the draft carries an `adapted_from` pin, also grade its prose
   against the `register` and `terminology` its `language` declares in
   `config/language-conventions.yaml`, and **state which language block you
   graded against**. A language with no declaration is **skipped, and the skip
   is disclosed** — never reported as a defect. Findings are blocker-eligible
   and name the declared convention as their criterion. Authored canonicals are
   untouched by this item. Full contract:
   [`review-prompts.md`](review-prompts.md) §"Declared-convention conformance"
   — read it there; it is not restated here.

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
path into the policy repo. **The reader is the sole `policy_source` detector**:
do not pre-probe for config with `ls`/`ugrep`/globbing `config/*.yaml` to decide
whether a policy source exists — that surfaces `Exit code 2` shell noise on a
host with no policy source (F75). Run the reader directly and branch on its
exit code (below); an unset source is exit 10, not an error to discover first:

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
- **10** is also what an `enabled: false` toggle produces — same silent skip.
- **11** (toggle present, gateway unavailable — unreachable, transport error,
  or timeout; the retired exit 12 collapses here) — the reader printed exactly
  one `policy_source unavailable: <reason>` line; **relay that one line once**,
  skip the pass, continue. Keep the reason for the `consulted:` line.
- **13** (named gateway tool-surface gap — Story 13.72) — same as 11: the
  reader printed one `policy tool-surface gap: <reason>` line; relay it once,
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
