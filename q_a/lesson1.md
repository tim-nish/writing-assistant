# Lessons from Q&A 1 (2026-07-10)

Distilled, generalizable principles from q1.md / a1.md — the reusable *why*
behind the specific recommendations, for future product decisions.

## 1. Diagrams are claims

A diagram asserts facts (A calls B, X precedes Y) with *more* reader authority
than prose. Whatever sourcing discipline governs sentences must govern visuals
identically: source-pointed, `[VERIFY]`-marked, or routed to NEEDS-OWNER. Any
new content type added to the pipeline later (tables, code snippets, benchmark
charts) inherits the same rule by default.

## 2. Propose, never insert — the plugin's one interaction contract

Harvest doesn't assert (NEEDS-OWNER), review doesn't rewrite (findings),
visuals don't self-insert (proposals). Every future capability should default
to this shape: assistant proposes with rationale + preview + concrete-effect
choices; author arbitrates. The dogfood UX findings (show outline context,
state each choice's consequence) are properties of *this contract*, not of the
gap interview specifically — fix them once, inherit them everywhere.

## 3. Platform divergence belongs in the variants stage, nowhere else

Zenn renders Mermaid; dev.to needs images. The pipeline authors *one*
canonical draft and lets stage 5 diverge. Resisting platform-awareness
upstream keeps every earlier stage platform-agnostic — the same reason
identity lives in config, not skills.

## 4. Length is an output, not an input

Structure (framework slots) bounds length better than any word count. Targets
corrupt in both directions (padding / amputation). Surface reading time as
information; enforce length only where a platform makes it a hard limit — and
then it's a publish blocker (validation), never an optimization target.

## 5. Intent-preserving and intent-changing operations must not share a workflow

Review improves how well the article achieves a fixed story; restructure
changes the story. Merging them would cost review its bounded-findings
property. General form: when a proposed feature answers a *different question*
than the workflow it would extend, it's a new workflow — or nothing yet.

## 6. Defer with a tripwire, not a vibe

"Keep V1 simple and add it if dogfooding shows need" only works if "need" is
measurable. Pattern: write the spec now while the design intuition is fresh,
mark it `status: deferred`, put a concrete trigger in the frontmatter
(e.g. "≥3 logged whole-section post-review edits", "5 published articles"),
and let the dogfood findings log be the tripwire. The decision is pre-made;
the future is mechanical.

## 7. Pointers over copies, at every scale

Fact sheet entries point at sources; the article index stores pointers and
one-line claims, never bodies; articles stay in the repos their evidence lives
in. Centralizing content orphans it from its sources — centralize *metadata*
instead. This principle has now held at three scales (fact, article, corpus);
treat violations as design smells.

## 8. Optionality by construction protects the generic engine

The article index is configured via user-config and, when absent, changes
nothing. Every machine-global or owner-specific capability should be built
this way: absence of config → silent no-op, zero skill edits either way. This
is the identity/engine split (CAP-6) restated as a growth rule.

## 9. Absorb mechanical work; never absorb judgment

Image-gen prompts, reading-time metrics, re-outline mapping tables: generate
them automatically — reviewing one costs seconds, writing one costs minutes.
But the *decision* (is a diagram worth it, does the story change) stays with
the author. The dividing line for any future automation proposal: does it
produce something the author reviews, or does it decide something on the
author's behalf? Build the former freely; the latter needs a spec debate.
