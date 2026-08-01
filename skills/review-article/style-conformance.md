<!-- style-conformance.md — review-article companion (Story 20.140, #1202;
     umbrella #1191). Read on entry to the PROSE pass, alongside
     phases/passes.md: the Reviewer's ONE style dimension. -->

# The one style dimension — conformance to the named contract

The owner keeps **one versioned style contract** in the articles repository, and
generation composes against it (`skills/draft-article/style-contract.md`, Story
20.139). Review is its **measurement layer and never its carrier**: this file is
the whole of what the Reviewer may say about style.

**Exactly one dimension is added, and it is this one** — *conformance to the
named contract, citing the clause*. Not a family of style findings; not a style
pass; not a rubric dimension (`quality-rubric.md` is unchanged, still four).
Anything about voice, register, tone-as-identity or article shape that is not a
measured divergence from an authored clause of that contract is **out of the
Reviewer's mouth entirely**.

## The prohibition on taste, and the reason it is load-bearing

**A preference delivered as a review finding is indistinguishable to the reader
from a contract requirement, and becomes one by repetition.** That sentence is
the reason this dimension is bounded the way it is, and it is carried here —
in the pass's own text — rather than asserted somewhere a reviewing agent never
reads. A reviewer who dislikes a sentence has no standing; a reviewer who can
quote the clause the sentence diverges from is reporting a measurement the owner
can check in one look. **A finding that cannot cite a clause is not emitted,
because it is taste** — it is not downgraded to a nit, not softened into a
suggestion, not filed as informational. It does not exist.

## Read the contract once, at the start of the prose pass

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/style-contract.py read --root <host-repo>
```

That script is the **single reader**; never open the artifact by another path,
and never write it — the plugin's only interaction with it is a read. Branch on
its exit code, and **never abort the review on any of them**:

| Exit | Meaning | What this dimension does |
|---|---|---|
| 0, `status: present` | the contract parsed | measure — see below |
| 0, absence line | no contract at the resolved path | **state that the dimension did not run, and why** |
| 4 | malformed (named defect) | relay the reader's lines **verbatim**, then behave exactly as the absent case — a half-applied contract is worse than a declared absence |
| 2 | the drafts destination cannot be resolved | same as absent, naming the resolution failure as the reason |

## The three states, and their exact output

The dimension **always states which of these it is in**: it must
never silently skip, and never fall back to unanchored taste.

**(a) No contract configured** — emit no findings, and carry this line into the
completion summary's informational notes ([`completion-summary.md`](../completion-summary.md)):

```
style-contract conformance: DID NOT RUN — no style contract at <path> (style-contract.py read, exit 0, absent). The dimension measures conformance to a named contract; with no contract there is no clause to cite, and an uncited style finding is taste. No style findings were emitted for this draft.
```

**(b) Contract present, its judgment sections NOT YET AUTHORED** — this is the
expected state today, and it is **not** state (a). The contract's structure
ships ahead of its content, so an authored-but-empty section is a real contract
with nothing yet to measure against:

```
style-contract conformance: RAN, nothing to measure — the style contract (v<version>) is present; REGISTER and STRUCTURAL VOICE are NOT YET AUTHORED (owner's work). An authored-but-empty section is not an absent contract: the artifact exists, its judgment clauses do not yet, so no clause could be cited and no style findings were emitted.
```

Name the sections individually when only one is authored — measure the authored
one, and state the other as not yet authored in the same line.

**(c) Contract present with an authored clause** — measure, and emit findings in
the format below. When the measurement finds no divergence, state that as the
run line and emit nothing else (no praise, no per-clause report):

```
style-contract conformance: RAN against the style contract v<version> — measured REGISTER, STRUCTURAL VOICE. <n> conformance finding(s); no divergence in the sections not listed.
```

## What it measures — and the two things it must not

**REGISTER** (the assumed reader background) and **STRUCTURAL VOICE**
(claim-first paragraphs so skimming survives; the concrete-failure →
generalized-property → validity-conditions pattern) are the contract's two
**judgment** sections, and they are exactly what this dimension measures. They
are measured **together, once, as one dimension** — the prose pass is the first
point at which structure has settled and both are stable, and measuring them at
two points would turn one dimension into two.

- **LEXICON is NOT measured here.** Its carrier is *mechanical*: the existing
  coinage lint (the quality gate's dim-3 first-use-gloss pass) already carries
  it. **The Reviewer must not duplicate a mechanical check as a judgment** — a
  second, judged copy of a mechanical rule produces disagreement between two
  instruments with no precedence between them.
- **NO FINDING is emitted against SYNTAX PROFILE.** Sentence length, hedging
  density, person and voice carry **no instrument by ratified decision**, and a
  review finding would be that instrument arriving through the back door. Read
  the clause if it helps you read the draft; measure nothing from it, count
  nothing, and emit nothing citing it. (The prose pass's own hedging and
  sentence-length items are untouched — they are *prose* findings against the
  prose rubric, and they never cite the contract; a finding that cites this
  contract for a sentence-length observation is the back door.)
- **FIGURES** is a pointer to `SPEC-article-visuals` and is not restated,
  re-derived, or measured here.
- **An empty exemplar slot is nothing to imitate.** Never substitute an
  article, a rendering, or your own sample for a missing exemplar.

## The finding format, and how the citation is enforced

```
- [conformance] {draft path:line}: {the divergence in one sentence}. Contract: style contract §REGISTER — "{verbatim clause quote}". Fix: {one concrete change in one sentence}.
```

- The severity slot carries **`conformance`** — its own class, never
  `blocker` / `should` / `nit` (below).
- `Contract:` is **mandatory and is the criterion**: the contract named by
  role (never by file path — the reader is the sole authority on where it
  lives), the section (`§REGISTER` or `§STRUCTURAL VOICE` — those two only), and a
  **verbatim quote of the authored clause** the draft diverges from. It replaces
  the `Why {severity}:` field, which has no meaning without a severity.
- **No rewrites** — `Fix:` names the change in one sentence; the owner edits.
- Capped at 10, like every pass, highest-leverage first.

**Enforcement is mechanical, not discipline** —
`scripts/validate-review-findings.py` rejects the set before it reaches
arbitration:

- **C1** — a `[conformance]` finding with no conforming `Contract:` citation.
  *That finding is taste, and taste is not emitted.*
- **C2** — a `[conformance]` finding citing `§SYNTAX PROFILE` (no instrument, by
  ratified decision), `§LEXICON` (already mechanical) or `§FIGURES`.
- **C3** — a `blocker` / `should` / `nit` finding that cites the style contract:
  a conformance miss never enters the blocking vocabulary.

## Tiering — its own class, and it never blocks

**Conformance findings are their own class, outside `blocker` / `should` /
`nit`, and they never block.** The existing three-tier vocabulary is untouched
and stays exactly as it is for correctness, structure and prose findings.

The grounds, recorded so they are not reopened: a conformance miss and a factual
error are **different kinds, not different severities** — one scale forces a
comparison with no answer. And folding style into blocker/should/nit would make
a style finding *look* like a correctness finding, which is the exact
indistinguishability the taste prohibition exists to prevent.

Consequences, all of them:

- a conformance finding is **never** blocker-eligible and never enters the
  severity criteria table in [`review-prompts.md`](review-prompts.md);
- it **never** triggers the second full cycle, and an open one **never**
  withholds the "publishable" verdict;
- it enters the consolidated arbitration list as an ordinary reject-only item,
  ranked **after** the three severities (blockers → should → nit →
  conformance), and its disposition is journaled like any other;
- the arbitration event it emits carries `"severity": "conformance"` and
  `"criterion": "style-contract-<section-id>"`, so a chronically-rejected clause
  is visible to the dogfood recurrence bar as itself.

## What this dimension never does

- It never proposes a style, asks a style question, or opens a gate: the
  contract is an **onboarding-lifetime** fact, and a per-run style decision is
  what the artifact exists to remove.
- It never edits the contract, creates it, or offers to.
- It never carries a corpus-level judgment ("one author across 100 articles").
  That property is invisible to per-article review by construction; its
  instrument is **held**, with its trigger already named at
  `scripts/style-contract.py`.
