# Project state — declarations for Nightwatch (and for humans)

This file is a contract. It records the few things **no tool can infer** about this
repository, so Nightwatch never has to guess and silently corrupt your truth. Everything
outside the single fenced `yaml` block below is prose for humans and is ignored by tooling.
Edit it by hand (or re-run `/nightwatch init`); overnight runs never touch this file.

Fill in only what applies. Anything you omit is treated as *undeclared*: the dependent
check is skipped and surfaced as a one-line setup finding — never inferred.

- **authority** — which artifact is the source of truth per area. `role: authoritative`
  means code and docs must conform to it (a conflict is a human decision). `role: derived`
  means it must follow the code (a conflict is mechanically fixable — patch proposed).
- **phase** — changes ranking: `prototype`/`building` weight overengineering up;
  `hardening`/`released` weight drift and coupling up.
- **release** — the target and the human definition of "done".

```yaml
authority:
  architecture: {artifact: "specs/spec-writing-assistant/plugin-layout.md", role: authoritative}
  behavior:     {artifact: "specs/*/SPEC.md", role: authoritative, rule: newest-accepted-wins}
  usage:        {artifact: "README.md", role: derived}   # follows the specs/code, never leads
phase: hardening            # prototype | building | hardening | released
# First dogfooding cycle completed: harvest -> draft-article -> review-article works
# end-to-end and the install/usage documentation has been validated. Polishing toward
# the first release while completing the remaining planned epics.
release:
  target: "First release — all planned epics complete"
  definition_of_done:
    - "all planned epics complete"
    - "harvest -> draft-article -> review-article works end-to-end (first dogfooding cycle passed)"
    - "install and usage documentation validated"
```
