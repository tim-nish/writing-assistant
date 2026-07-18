# SPEC — repository onboarding (`setup`)

**Status: RATIFIED (2026-07-15, owner) — implementation started same day.**
Origin: owner UX proposal during the 2026-07-15 QSB dogfood run, after the
first-run gap surfaced twice (a host repo with no machine-global config fails
closed with no guided path; a config without `policy_source` silently loses the
policy narrative). Policy-guard reviewed against the owner's pinned recall
surface — conforms; advisory tensions recorded in the run
transcript and folded into Constraints below.

> **Amended 2026-07-15 (triage, #230)** per SPEC-policy-topic-at-draft: the
> policy-source offer (CAP-1 step 2; skill Stage B item 3) proposes and writes
> **`policy_source.path` only** — setup no longer asks for or writes
> `track`/`topics` (a per-article decision made at draft time). CAP-2's
> `set-policy-source` drops its `--track`/`--topics` flags on the same
> schedule as the config keys (SPEC-policy-topic-at-draft CAP-3). The
> declining-consequence statement is unchanged.

## Problem

Preparing a repository for the article pipeline today requires manual YAML
authoring at a machine-global path the user cannot guess
(`resolve-paths.py sources-file` prints it), using
`config/writing-sources.example.yaml` as a template. Only one key
(`output.drafts`) has an assisted, comment-preserving write-back path
(`set-draft-location`, invoked by Stage 0 on consent). The keys that decide
what the pipeline can read (`sources`) and whether the interview carries the
owner's policy narrative (`policy_source`) are hand-edit-only. The result: no
reproducible first-run procedure the README can document, and a silently
degraded interview when `policy_source` was never considered.

## Capabilities

- **CAP-1 — `setup` skill (repository onboarding).** A user-facing skill,
  invoked from the Claude Code UI against a host repo, that produces a
  complete, validated machine-global `writing-sources.yaml`:
  1. Resolve the destination through the path resolver only (no storage-path
     literals anywhere in the skill).
  2. **Propose, don't demand** (agent-fed): inspect the host repo and *draft*
     each value for approval — a `sources` list with an `include:` allowlist
     proposal (article material in, tool/editor/build dirs out), an
     `output.drafts` recommendation (external private articles repo), and an
     explicit `policy_source` offer (**a presence toggle — amended 2026-07-18,
     #366: setup proposes `enabled: true`, never a filesystem path; the
     gateway MCP registration is the integration**) with a one-line
     statement of the consequence of declining: "interview runs generic; no
     policy-seeded questions." The user approves/edits choices in the UI;
     the user never opens the file.
  3. Write the approved config via the config-writer subcommands (CAP-2) —
     the skill never free-hands YAML.
  4. Verify before finishing: `validate-config` exit 0; `files` resolves a
     non-empty scope (or the user explicitly accepted an empty one);
     when `policy_source` was declared, the reader's `pin` and `whitelist`
     succeed **through the gateway** (amended 2026-07-18, #366 — a
     setup-time gateway health check, never a hub filesystem read; an
     unusable gateway is a setup-time finding even though at run time it
     only degrades). Report a completion summary naming the config path
     and the resolved read scope. After a clean finish, `draft-article` runs
     with no manual file edit.
- **CAP-2 — config writers.** Extend `resolve-writing-sources.py` with
  `set-policy-source PATH [--track T | --topics ...]` and
  `set-sources` (declarative replace of the `sources:` block), both with the
  same contract as the existing `set-draft-location`: comment-preserving line
  surgery, machine-global destination via the resolver, legacy-file migration
  semantics unchanged. These are the only write paths CAP-1 may use.
- **CAP-3 — user-config first run.** `setup` also checks the user-level
  config (`resolve-user-config.py`): unresolved example placeholders are
  reported with the same ask-and-write-back pattern, so both configuration
  categories complete inside the UI.
- **CAP-4 — README.** After ratification+implementation, the README's
  first-run section documents `setup` as the supported procedure; manual YAML
  editing remains documented only as the escape hatch (the file format stays
  public contract, per the example file).

## Constraints (policy folded in — implementation orders need no attachments)

- **C1 (footprint invariant, #211):** the generated file lands only in the
  machine-global per-repo config dir, never in the host repo; all paths
  resolve through the path resolver.
- **C2 (seam semantics untouched):** `policy_source` remains OPTIONAL and the
  ratified run-time degradation stays exactly as specced — absent = generic
  interview, silently (SPEC-policy-source-seam CAP-6; "the policy source is
  an enhancer, never a dependency"). This spec improves *setup-time*
  discoverability only; it adds no run-time prompt, warning, or requirement.
- **C3 (agent-fed gate):** every value is proposed by the tool and approved
  by the human — the human is never asked to author the hardest input
  (evidence-gate-must-be-agent-fed — owner lesson, recorded 2026-07-15).
- **C4 (config not code):** the skill adds zero repo-specific assumptions to
  code; everything repo-specific lands in the declaration file
  (portable-plugin-config-not-code — owner lesson, recorded 2026-07-15).
- **C5 (one-time, not ceremony):** `setup` is a once-per-repo bootstrap; it
  is never required on subsequent runs and never becomes a recurring
  invocation step (respects the pull-ceremony decline,
  topics/claude-code-ops.md Declined 2026-07-06 — recurring operations stay
  push-based/automatic).
- **C6 (no server):** configuration remains local files; no gateway, daemon,
  or served config API (interim contract, no server before the Tsurezure
  substrate decision).
- **C7 (read-only toward the policy repo):** `setup` may run
  `read-policy-source.py pin/whitelist` to *verify* a declared pointer; it
  never writes under `policy_source.path` and never widens the seam's code
  allowlist.
- **C8 (publication boundary):** the skill and its docs describe the
  mechanism generically ("your policy repo"); owner-specific paths appear
  only in generated private config, never in repo files.

## Non-goals

- Changing interview/run-time behavior in any way (degrade stays silent).
- Remote/URL policy sources, sync, or multi-machine config distribution.
- Editing the policy hub or any policy repo (proposal-only contribute-back
  stands).
- A second config store or a migration away from `writing-sources.yaml` —
  the file format is unchanged; this spec only adds sanctioned writers and a
  guided flow that uses them.
- Auto-running `setup` from `draft-article`. Stage 0 keeps its current
  behavior (fail closed on missing sources; ask-once for `output.drafts`).
  At most, its error text may point to `setup` once ratified.

## Acceptance sketch

Onboard a fresh repo with no config: run `setup`, approve the proposed
values including a `policy_source`, and finish with (a) a valid machine-global
file the user never opened, (b) `read-policy-source.py whitelist` resolving,
and (c) `draft-article` reaching Stage 2 with policy-seeded questions and a
non-`none` `consulted:` line — with zero manual YAML edits. Decline the
`policy_source` offer instead, and the run completes identically to today's
generic path, with the decline recorded in the setup summary.
