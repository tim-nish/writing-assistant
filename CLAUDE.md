# writing-assistant — agent instructions

## Policy consultation (consult-first)

Policy questions go to the tsurezure-gateway tool before AskUserQuestion.

Before raising a human gate on a policy, architecture, or prior-decision
question, call the `tsurezure` MCP server's `policy_lookup` tool. Only a miss
escalates to the human, and surface the miss with the question ("Tsurezure has
no position on X") — every escalation doubles as a distill-bug signal. Record
the returned `consulted:` line, and which served lines you applied, in your
run output.

## Claims about the served surface (#642)

The rule above governs *gates*. This one governs *authored text*, because a
claim can be wrong without any gate being raised.

**Any spec, story, or issue text asserting what the recall surface does or does
not record binds only after consulting it.** Carry the pin —
`consulted: product-lab@<sha> <files:lines>` — at the point of use. Grounding
in this repository's own code is **not** grounding for such a claim: the
declared authority for what the hub records is the seam read, and the shipped
implementation is the authority for code facts only (that scope limit is stated
in the rule itself, `topics/knowledge-architecture.md:32`). Authority is
per artifact class (`LESSONS.md:18`); pick the class's own authority.

**Absence claims are three-valued.** "Not observed" without consulting the
source is **cannot-determine**, not "absent". Write it as an open question
marked cannot-determine — never as a blocking premise, and never as a reason to
decline scope.

Why this exists: `SPEC-topic-map` OQ4 asserted that nothing readable here
records a reversal, a decision with its why, or thinking-at-the-time. It was
written from this repo's family list without a consultation. One `policy_lookup`
disproved all three — they were inside the existing whitelist — after a
story-half had been declined on the premise and an umbrella nearly closed on it.

The matching **check** for the `/triage-gh` and `/spec-sitting` commands is not
this repo's to state: it lives in `claude-toolkit/specs/spec-triage-gh/SPEC.md`
("Implementation grounding"), per the pointer-not-copy rule recorded in
`specs/spec-spec-sitting/SPEC.md`. This section is the duty owed by agents
working in *this* repository, which is where the incident happened.
