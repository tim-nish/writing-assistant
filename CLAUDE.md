# writing-assistant — agent instructions

## Policy consultation (consult-first)

Policy questions go to the tsurezure-gateway tool before AskUserQuestion.

Before raising a human gate on a policy, architecture, or prior-decision
question, call the `tsurezure` MCP server's `policy_lookup` tool. Only a miss
escalates to the human, and surface the miss with the question ("Tsurezure has
no position on X") — every escalation doubles as a distill-bug signal. Record
the returned `consulted:` line, and which served lines you applied, in your
run output.
