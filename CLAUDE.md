# writing-assistant — agent instructions

## Policy consultation (consult-first)

Policy questions go to the tsurezure-gateway tool before AskUserQuestion.

Before raising a human gate on a policy, architecture, or prior-decision
question, call the `tsurezure` MCP server's `policy_lookup` tool. Only a miss
escalates to the human, and surface the miss with the question ("Tsurezure has
no position on X") — every escalation doubles as a distill-bug signal. Record
the returned `consulted:` line, and which served lines you applied, in your
run output.

## Fork gates owe a ranked recommendation (#808)

**Any gate that presents options — a fork panel, a classification batch, an
alternatives selection — carries the machine's own comparison.** Ordered,
individually grounded options are not enough: the hardest input at a fork is
the *comparison*, and per-option advocacy leaves every option plausible alone
while nothing weighs them together.

Each option carries **the evidence bearing on it**, attached to that option and
not left in prose above the gate. The panel carries a **ranked recommendation
with its reasoning**, and states **what would overturn it**. Where options
share a machine-computed premise, render the premise and carry an option that
negates it — otherwise every available answer records something false.

**This is not a default.** The discriminator is falsifiability: a
recommendation carrying its own overturning evidence is agent-fed input the
owner can check cheaply; one without it is a default wearing a suggestion's
clothes. Nothing is pre-selected, and rank is not pre-selection.

Why this is here and not only in the fork-gate skill: **a skill binds only the
sittings that invoke it.** The incident that produced this rule
(`specs/spec-policy-fork-consultation/SPEC.md` CAP-3, amended 2026-07-27)
happened in a sitting that rendered fork panels without invoking that skill —
and a grep confirms nothing in this repo invokes it today. The rule is broken
at the moment an agent draws a panel, in any sitting, so it is ambient here;
the skill carries the procedure, and a check carries the visible-absence
signal.

## Claims about the served surface (#642)

The rule above governs *gates*. This one governs *authored text*, because a
claim can be wrong without any gate being raised.

**Any spec, story, or issue text asserting what the recall surface does or does
not record binds only after consulting it.** Carry the pin — but **the pin is
two-tier, and only its public half goes in the artifact** (#731,
`specs/spec-writing-assistant/SPEC.md` §Publication boundary). This repository
is public, so writing the hub's name or a real commit sha into tracked text is
a boundary violation; the instruction that used to appear here mandated exactly
the string the boundary check rejects, which made grounding a claim the act
that leaked it.

At the point of use, write the **public half** — a generic decision line:

```
owner decision record — YYYY-MM-DD (short title)
```

Record the **private half** — the full pin and the `files:lines` set — with
`python3 scripts/provenance-pin.py record --decision "<that line>" --pin
"<hub>@<sha>" --cites "<files:lines>"`. It lands machine-locally, outside every
repository. `provenance-pin.py resolve` reads it back; `provenance-pin.py check`
reports any public line with no private counterpart.

**Precedence:** the private record wins on mismatch. A public decision line
with **no** store entry is *unverified*, not grounded — mark it `unverified —`
inline at the point of use, per the gate-item content-grounding rule.

Grounding
in this repository's own code is **not** grounding for such a claim: the
declared authority for what the hub records is the seam read, and the shipped
implementation is the authority for code facts only (that scope limit is stated
in the rule itself, `topics/knowledge-architecture.md:32`). Authority is
per artifact class (`LESSONS.md:18`); pick the class's own authority.

**Absence claims are three-valued.** "Not observed" without consulting the
source is **cannot-determine**, not "absent". Write it as an open question
marked cannot-determine — never as a blocking premise, and never as a reason to
decline scope.

Why this exists: `SPEC-terrain` OQ4 (then `SPEC-topic-map`) asserted that nothing readable here
records a reversal, a decision with its why, or thinking-at-the-time. It was
written from this repo's family list without a consultation. One `policy_lookup`
disproved all three — they were inside the existing whitelist — after a
story-half had been declined on the premise and an umbrella nearly closed on it.

The matching **check** for the `/triage-gh` and `/spec-sitting` commands is not
this repo's to state: it lives in `claude-toolkit/specs/spec-triage-gh/SPEC.md`
("Implementation grounding"), per the pointer-not-copy rule recorded in
`specs/spec-spec-sitting/SPEC.md`. This section is the duty owed by agents
working in *this* repository, which is where the incident happened.

## Validation tiers (#913)

Checks run through `scripts/run-checks.sh`, never as an ad-hoc full-suite
sweep. Two tiers, declared per check (`# tier: full` header; headerless =
inner): **`--tier inner`** is the per-edit loop — every check must clear the
runtime ceiling the runner declares (`INNER_MS`), and a violation fails with
the remedy named; **`--tier full -P 8`** runs everything once before `gh pr
create`. End-to-end pipeline reruns belong in the full tier only. This is
ambient here, not only in a skill, for the reason the fork-gate section
states: the rule is broken at the moment an agent runs a 30s check inside an
edit loop, in any sitting.

**The per-edit run is SCOPED to the blast-radius family (#944):** pass the
GLOB — `scripts/run-checks.sh 'scripts/check-terrain*'` — for the files you
are editing; families are the check-name prefixes. The family SUM is budgeted
too (`INNER_TOTAL_MS`): an *unscoped* inner run over the whole suite fails
its ceiling by design, because 91 individually-fast checks summed to 51s per
edit iteration and per-member ceilings caught none of it. Unscoped stays
correct for the full tier's single pre-PR run.

**`-P N` is the FULL tier's remedy only (#957).** It runs the checks that
*declare* `# parallel-safe` concurrently, at most N at once, then the
undeclared remainder serially — `scripts/run-checks.sh --tier full -P 8`,
measured 2026-07-30 at 288s serial → ~104s at N=8 with 138 of 147 checks
declared. **It does not apply to the inner loop:** the per-edit remedy is
scoping, above, and nothing here licenses `-P` inside an edit iteration.
The declaration's default polarity is inverted against `# tier:` on purpose
— an undeclared check is NOT parallel-safe and runs serially, because the
failure mode being defended against is nondeterministic wrongness, not
slowness. Declare a check only after verifying *that file's* isolation.

**The per-edit run also selects by DECLARED COVERAGE (#998).** A check
declares `# covers: <globs>` — the paths it asserts over — beside its
`# tier:` and `# parallel-safe` headers, and the per-edit invocation runs the
UNION of the name-prefix family and every check whose declaration matches a
changed path — pass them: `scripts/run-checks.sh --changed "$(git diff
--name-only HEAD)" 'scripts/check-terrain*'` (`--list` shows the selection
without running it). The prefix alone finds only checks *named after* what you
edited, never one asserting a repo-wide property *about* it, which is why a
green scoped run kept being followed by a failing full tier. An undeclared
check covers nothing and is selected only by prefix — incomplete-but-honest
while the declarations are populated; the full tier still runs everything
once, so nothing goes unrun. **The union's added cost REPORTS against the
family ceiling rather than failing it (#1326)** — scoping cannot remove that
cost, since the union ignores the GLOB by design, so the ceiling's semantics
follow the remedy's availability: the GLOB-selected family portion (promoted
members included) keeps failing, the coverage-selected portion is a finding.

**The FULL tier REPORTS against two ceilings of its own (#961), and neither
fails the run.** Every full run discloses its *summed per-check work* against
`FULL_TOTAL_MS` — concurrency-independent, so it is the growth instrument —
and its *real elapsed wall clock* against `FULL_WALL_MS`, the cost actually
paid once per PR. Both are declared in `scripts/run-checks.sh`, which is the
single enforcement copy: do not restate the values here or in any spec or
check. **`FULL_TOTAL_MS` is declared AT a concurrency (#1001)** — it is
summed *elapsed* work, which inflates under contention (452s at `-P 8` vs
570s at `-P 14`, same suite), so every report carries the `-P` it was
measured at and a run at a different `-P` reads NOT COMPARABLE rather than
being checked. Summing CPU instead was tested and rejected: it inflates
+45% under load. Nothing time-based is concurrency-independent here. A breach is a finding to act on (re-tier, fixture-ise, or raise the
concurrency), never a red suite — the inner tier's ceilings fail, these do
not, and that asymmetry is deliberate.

**Adding a check is an ADMISSION DECISION, not a reflex (#1355/#1356).** The
ceilings above bound what the family costs; the five governance rules in
`scripts/run-checks.sh`'s header bound what may join it, and they bind **you**,
at triage and spec time, because most recent members were added by a sitting
resolving "add a check" from an issue. The binding quantity is **total cost per
ship-cycle** — Σ(runtime × invocations) — never per-invocation runtime and never
count. The header is the single copy; what is ambient here is the duty. A
proposal to add a check states the **defect class it ends** (a generation-side
constraint that makes the class unproducible is the preferred answer, and "no
checker" is a valid outcome), its tier and **measured** runtime, and its
**removal signal** — and "better than none" is inadmissible, because it prices
only the benefit while cost multiplies by loop position.

**The scoped per-edit run is genuinely small, and the number matters because a
wrong one has already driven a proposal.** Measured 2026-08-03 on a clean tree:
174 checks (55 full, 36 explicit inner, 83 headerless), and a *scoped* inner run
selects **5** when `scripts/run-checks.sh` is edited and **31** when a skill file
is. The 119 figure is the **unscoped** run — the one #944 fails by design. An
inversion of the `tier:` default polarity was proposed on that figure and
**declined**: with `# covers:` at 174 of 174, #1321's promotion means demoting a
check does not remove it from the per-edit loop when its subject changes, only
its ceiling. Scope your run; do not re-tier to make it quiet.
