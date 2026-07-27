# Capabilities

**What this is.** One row per capability this repository ships, with the
evidence that says so. It exists to answer exactly one question — *is capability
X implemented, and evidenced by what?* — for a reader who is not going to read
the code: a person, an agent, or a sitting in another repository.

**Why it exists.** On 2026-07-27 an upstream sitting judged
Terrain-consuming-Gloss unimplemented from prose and began a duplicate build.
It was already implemented here. The consumer had no surface capable of
answering the question, so prose answered it, and prose was wrong.

**What makes it different from a status line in a README.** Every row names a
**check script**, and a lint asserts that the script *exists* and *passes*. A
row cannot rot into a stale claim the way a hand-maintained status line does: if
the capability breaks, its evidence fails, and the manifest fails with it.
Mechanical existence evidence is not a standing claim — a passing check says the
capability *runs*, never that it is the right capability. `status` is the
standing half and is owner-maintained.

**Precedence.** This manifest is authoritative for *what is implemented here*.
It is not authoritative for what any upstream surface records, and it never
restates an upstream decision — the `hub carrier` column points, it does not
copy.

**The format is deliberately generic.** Nothing in the column set is specific to
this repository, so another consumer can adopt the shape without editing it.
The lint reads the table below by its column headers, not by any hard-coded
capability name.

## Status vocabulary

| status | meaning |
|---|---|
| `implemented` | shipped and evidenced by a passing check |
| `partial` | shipped with a stated gap; the gap is named in the row |
| `spec-only` | the contract exists; no implementation yet |
| `retired` | was shipped, deliberately removed; kept so its absence is not read as an oversight |

*This enum came from issue #805. Whether it is owned here or upstream is
**undecided** — see the open question at the foot of this file. It is not
silently forked: if upstream claims it, this becomes a conformance copy and
needs declared precedence plus a mismatch check.*

## Manifest

| id | what it does | status | since | evidence | spec | hub carrier |
|---|---|---|---|---|---|---|
| `terrain` | Shows the terrain before choosing what to write: a derived, bounded survey of candidate article directions. | implemented | 2026-07-23 | `scripts/check-topic-map.sh` | `specs/spec-terrain/SPEC.md` | hub#60 |
| `terrain-screen` | Presents the terrain as one screen, or as a View file when it is over budget, and hands the choice to the brief path. | implemented | 2026-07-23 | `scripts/check-topic-map-screen.sh` | `specs/spec-terrain/SPEC.md` | — |
| `gloss-consumption` | Reads the upstream plain-register renderings through the pinned seam, and discloses on the surface when they are not served. | implemented | 2026-07-26 | `scripts/check-topic-map.sh` | `specs/spec-terrain/SPEC.md` | hub#60 |
| `policy-seam` | Reads the upstream policy source read-only through one shipped reader, never a second one. | implemented | 2026-07-19 | `scripts/check-policy-reader.sh` | `specs/spec-policy-source-seam/SPEC.md` | — |
| `harvest` | Gathers source-pointed facts from a repository into a fact sheet, every fact carrying a resolvable pointer. | implemented | 2026-07-11 | `scripts/check-harvest.sh` | `specs/spec-article-draft-pipeline/SPEC.md` | — |
| `review` | Reviews a framework-complete draft in a fixed pass order, emitting capped severity-tagged findings the owner arbitrates. | implemented | 2026-07-14 | `scripts/check-review-arbitration.sh` | `specs/spec-article-review/SPEC.md` | — |
| `revise` | Re-enters the pipeline on a landed draft rather than running a parallel workflow. | implemented | 2026-07-26 | `scripts/check-complete-gate.sh` | `specs/spec-article-revise/SPEC.md` | — |
| `adaptation` | Derives a target-language canonical from a reviewed canonical, as a standalone post-review invocation. | implemented | 2026-07-26 | `scripts/check-canonical-adaptation.sh` | `specs/spec-canonical-adaptation/SPEC.md` | — |
| `variants` | Emits platform-ready variants of a reviewed canonical, with a per-variant platform lint. | implemented | 2026-07-15 | `scripts/check-stage5-variants.sh` | `specs/spec-platform-variants/SPEC.md` | — |
| `repo-onboarding` | Onboards a repository for article authoring and verifies the config before finishing. | implemented | 2026-07-18 | `scripts/check-repo-onboarding.sh` | `specs/spec-repo-onboarding/SPEC.md` | — |

## Open questions

1. **Status-vocabulary authority.** The enum above is this repo's copy of issue
   #805's list. If the upstream seam claims ownership, this section becomes a
   conformance copy under the ratified conformance-copy rule — declared
   precedence plus a mechanical mismatch check — rather than an independent
   second text. Not decided here.
2. **What counts as a row.** The seed list is the one issue #805 named. Whether
   *every* skill is a capability or only owner-facing ones is a scoping call
   that has not been made; the current rule of thumb is "a capability is
   something a reader outside this repo might ask about by name", which is a
   judgment, not a criterion.
3. **The generic seam skill does not exist yet.** #805 anticipates installing it
   once the upstream side ships. This file and its lint are the first-adopter
   half only; wiring is deliberately not invented ahead of that format.
