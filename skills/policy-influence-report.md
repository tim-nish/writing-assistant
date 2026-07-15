# Policy-influence report (Story 13.40, SPEC-policy-editorial-direction CAP-4)

The Tsurezure demo deliverable: same repo, same facts — what the policy
changed, line by line. Emitted **on request only** (resolved question 1):
after a run, when the owner asks for it ("show the policy influence report").
It is never emitted unasked — an unread per-run report trains ignoring.

## What it is

A **view over recorded influence** in the run workspace — never a
second draft, never an A/B run, never new model analysis of the article. Its
only inputs are run state that already exists:

- the **interview journal** (`$WS/interview-journal.json`): seeds
  (`seed<-` pointers), the `consulted:` line, the `editorial_anchor`,
  suppressed/capped entries;
- the **presented payloads** (`$WS/presented-payloads.jsonl`): every
  recommendation as shown, and the owner's selection against it;
- **staging candidates** (when emitted): owner positions the run surfaced.

## Report shape (short — a page, not a dossier)

1. **Policy-directed decisions** — one line each: the decision (article type,
   claim/angle, a review emphasis), the seed that drove it (**verbatim quote +
   `file:line@commit`** at the run pin), and the owner's ratification or
   override (from the payload log; an override is itself a finding — declines
   are data).
2. **The generic-mode counterfactual** — what the run would have done unseeded,
   **read from the record, never invented**: the repo-grounded default the
   payload log shows was offered alongside the seed, the suppressed/unseeded
   defaults the journal records, the questions that would have run generic.
   If the record does not state the counterfactual for a decision, say
   "counterfactual not recorded" — do not compose what generic mode "would
   have said".
3. **The consulted trail** — the run's `consulted:` line(s), verbatim.

## Where it goes

The report is a **human-facing deliverable**: present it in the conversation.
If the owner wants a file, write it next to the article at the configured
`output.drafts` location (a declared product location) — never into the run
workspace or any machine-state directory, and never into the host repo
anywhere else (footprint invariant).

## Invariants (hard lines)

Propose-ratify, no-facts, audited (SPEC-policy-editorial-direction): the
report *documents* influence; it must not introduce any. It quotes policy
lines only with their pins, adds no new claims about the article, and reads
`policy_source` content only through what the run already captured — the
report generation itself reads **no policy files** (the pin may have moved
since the run; the record is the truth about what was consulted).
