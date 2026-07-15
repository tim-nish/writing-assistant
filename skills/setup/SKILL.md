---
name: setup
description: >
  Onboard a repository for article authoring, entirely inside the Claude Code
  UI. Use when the owner asks to "set up" a repo for the writing assistant,
  when draft-article/harvest fails for a repo with no writing-sources.yaml, or
  before the first run against a new host repo. Proposes sources, draft
  location, and the optional policy_source; writes the machine-global config
  through the sanctioned writer subcommands; verifies before finishing
  (SPEC-repo-onboarding).
---

# Setup — repository onboarding

Prepare a host repository for `draft-article` in one guided pass. The owner
approves values; **the owner never opens or edits a config file** — you draft
every value from repo inspection, and every write goes through a
`resolve-writing-sources.py` writer subcommand. **Never free-hand YAML into
the config path, and never write any config into the host repo working tree**
(footprint invariant, #211 — the machine-global per-repo file is the only
destination, and the writers already resolve it).

This is a **once-per-repo bootstrap**: after a clean finish, `draft-article`
runs with no manual file edit. It is never a recurring step, and
`draft-article` never runs it implicitly — Stage 0 keeps its own fail-closed
behavior.

## Stage A — resolve and inspect

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py sources-file --root <host-repo>
```

(In a checkout run via `claude --plugin-dir`, `${CLAUDE_PLUGIN_ROOT}` is that
checkout.) This prints the machine-global destination — exit 3 with the
target path when the file does not exist yet (the normal first-run case).
Report which case you found:

- **No file** — full onboarding; continue with Stage B.
- **File exists** — this becomes a **review pass**: show the resolved current
  state (`sources`, `draft-location`, `policy-source` subcommands — never a
  raw file dump), then offer to fill only what is missing or change what the
  owner asks. Do not re-ask settled values.
- **Legacy in-repo file** — the resolver already prints the deprecation
  notice; explain that the first write migrates the whole file
  machine-global, then proceed as a review pass.

Then inspect the host repo top level (directory names, README title, obvious
doc/spec/source layout) — enough to *propose* values in Stage B. This read is
for configuration only; it is not a harvest.

## Stage B — propose, owner approves (agent-fed, never owner-authored)

Ask with concrete recommended defaults — one question set, batched (the
AskUserQuestion tool where available). Every value arrives as a proposal the
owner can approve or override; the owner is never asked to author a value
from nothing (evidence-gate-must-be-agent-fed).

1. **Sources.** Propose `path: .` plus an `include:` allowlist drafted from
   the actual tree: article material in (README, docs/, specs/, top-level
   *.md — whatever exists), tool/editor/build noise out (`.claude/`,
   `_bmad*/`, `node_modules/`, templates, caches). Offer sibling checkouts
   only if the owner names them — never guess a sibling into scope. A
   whole-tree scope without `include:` is allowed but flag the noise warning
   it will draw.
2. **Draft location.** Recommend a directory in a **private articles repo
   outside the host repo** (#213 — a host repo may be public; drafts are
   private assets). `~/work/articles/drafts/` is the standing recommendation
   when it exists.
3. **Policy source (optional — explicit offer, stated consequence).** Offer
   the `policy_source` block with a proposed `path` (the owner's policy repo
   checkout, if one is known) — **path only** (SPEC-policy-topic-at-draft
   CAP-1, Story 13.34): which policy topics an article reads is a
   **per-article decision made at draft time** (draft-article Stage 2), so
   setup asks no `track`/`topics` question and writes neither key. State the
   consequence of declining in one line: *"without
   it, the Stage-2 interview runs generic — no policy-seeded tension
   questions, `consulted: none`."* Declining is a valid, recorded choice —
   the run-time degrade stays silent by design (SPEC-policy-source-seam
   CAP-6); this offer is the setup-time surfacing of that decision, not a
   nag. Never present `policy_source` as required.

## Stage C — write through the sanctioned writers only

```
printf '%s' '<approved sources JSON>' | \
  python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-writing-sources.py set-sources --root <host-repo>
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-writing-sources.py set-draft-location <dir> --root <host-repo>
# only when the owner accepted the policy_source offer (path only — Story 13.34):
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-writing-sources.py set-policy-source <path> --root <host-repo>
```

The writers are fail-closed (a malformed result refuses and writes nothing)
and idempotent; they are the ONLY write path this skill may use. If a writer
refuses, relay its per-key error and re-ask that one value — never hand-edit
around it.

## Stage D — user-level config check

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-user-config.py resolved
```

If it errors (no user config anywhere) or reports example placeholders,
surface the missing identity keys and ask for values, then write
`~/.config/writing-assistant/user-config.yaml` from the approved answers
(this file is flat identity config with no repo-specific keys; see
`config/user-config.example.yaml`). If it resolves cleanly, say so and move
on — do not re-open settled identity.

## Stage E — verify before finishing

All read-only; a failure here reopens the corresponding Stage B question,
it never ends the run with a broken config:

1. `validate-config.py --root <host-repo>` — exit 0.
2. `resolve-writing-sources.py files --root <host-repo>` — non-empty scope
   (or the owner explicitly accepted an empty one), and relay any noise
   warning.
3. When `policy_source` was declared:
   `read-policy-source.py pin --root <host-repo>` and `whitelist` — the pin
   resolves and the whitelist names GLOSSARY, LESSONS, and the matched
   topics. An unusable path here is a setup-time finding (fix the path or
   drop the block) even though at run time it would only degrade.

## Completion summary

End with the shared completion summary
(`${CLAUDE_PLUGIN_ROOT}/skills/completion-summary.md`): informational notes
(the config path, the resolved source-file count, the policy whitelist or the
recorded decline), publish blockers (none expected), optional cleanup (e.g. a
legacy in-repo file to delete after migration), and the explicit next step —
"run `harvest` or `draft article <F1-F4>` against this repo." No
reading-time estimate: setup produces configuration, not an article.
