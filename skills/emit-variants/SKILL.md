---
name: emit-variants
description: >
  Emit platform-ready variants of a reviewed canonical draft. Invoke as
  "emit variants <slug>" to run the standalone post-review variant invocation
  (never a stage of the draft flow): config preflight, then ONE selection
  screen offering the configured platforms, then emission of exactly the
  owner's chosen subset plus the per-variant platform lint. The contract it
  fronts lives in draft-article/variants.md; this skill re-implements nothing.
---

# Emit variants

The front door for the **standalone post-review variant invocation**
(SPEC-platform-variants CAP-1/CAP-3, SPEC-article-draft-pipeline CAP-4). The
flow, the preconditions, and the packaging rules are defined once in
[`../draft-article/variants.md`](../draft-article/variants.md) — this skill
**orchestrates** that contract and restates nothing beyond what the owner must
see at the gate.

```
emit variants <slug> [<host-repo>]
```

Variant emission is **not** a stage of the draft flow, which ends at the
`complete` gate with next step review-article. Run this **after** review, over
the persisted canonical that `complete` wrote.

**Name the target repository first (#309).** Before reading config or offering
anything, print the resolved target as the flow's first owner-visible line:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-paths.py target --root <host-repo>
```

Relay it as `Operating on host repo: <path>`. When an explicit `--root`
disagrees with the session's cwd the resolver notes both on stderr — relay that
line too; `--root` still wins.

## Preconditions — re-stated, never re-implemented

The invocation itself enforces all of these and fails pointedly when one is
unmet (`cmd_variants`). State them; do not re-check them here:

- the **persisted canonical** exists at `<output.drafts>/<slug>.md` — a
  run-workspace copy is refused, with `complete` named as the remedy;
- the draft carries **zero `[VERIFY]` markers** (Stage 4 finished);
- the draft declares a resolved **`audience`** and **`audience_id`**.

If one of these aborts the invocation, relay the error verbatim — it already
names the remedy. Adding a second copy of any of these checks here is a defect.

## Step 1 — config preflight, before any options are shown

Both gaps below make emission fail later, so they are surfaced **before** the
owner is asked to choose. Report the exact missing piece and stop; do not show
platform options.

**Read the choices.** This is also the syndication-policy preflight: the
invocation validates `syndication.policy` for the draft's language *before* it
reports options, so a missing policy stops here with the language named.

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py variants --slug <slug> --root <host-repo> --list-platforms
```

- **Exit non-zero, `no syndication.policy for language '<lang>'`** — stop.
  Tell the owner: config declares no syndication policy for this draft's
  language, so there is nothing to emit; the fix is a
  `syndication.policy.<lang>` entry naming that language's `variants`. Offer no
  options.
- **Exit 0** — the JSON carries `language`, `mode`, and `available` (the
  configured platform ids). `emitted` is empty and `written` is false: reading
  the choices emits nothing.

**Check every `available` platform actually resolves to a profile.** A platform
declared in config whose profile exists only as a shipped `.example` file has no
resolvable profile, and emission WILL fail at that platform (#494/#530). Use the
resolver's own answer — never a second profile check:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-platform-profiles.py list --root <host-repo>
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-platform-profiles.py dir  --root <host-repo>
```

Any id in `available` that is absent from `list` is a **missing piece**. Report
it before offering options, naming the exact path
`<dir>/<platform>.yaml` and the fix — copy
`config/platform-profiles/<platform>.example.yaml` there, or drop the declared
variant from `syndication.policy`. When *every* `available` platform is
unresolvable there is nothing emittable: stop. When only some are, report the
unresolvable ones as missing pieces and carry only the resolvable ones into the
selection screen.

## Step 2 — one selection screen, then emit

**Emission is the owner's explicit publish decision (CAP-6/#226): the pipeline
never auto-emits every configured platform.** Present the choice
**in-conversation** under the
[owner-facing proposal contract](../owner-facing-proposal-contract.md) — one
screen, machine-proposed selectable options **plus** a free-form response
(approve / modify / skip), never a path or artifact for the owner to open, and
never a second confirmation after they answer.

Per that contract each option states its **concrete effect on the artifact**,
so name the file each choice leaves behind — `<slug>.<platform>.md` at the
resolved `output.drafts` — and carry the **Where** (the destination directory),
the **Why** (this platform is configured for the draft's language, and what its
`mode` implies), and the **Effect** on every option. The payload is **plain
text**: no `**bold**`, no backticks, no headings, no Markdown links (contract
(g)). Validate and capture it in the same invocation before showing it:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-proposal-payload.py --ws "$WS" --surface variant-emission <payload.json>
```

A non-zero exit means the payload is not presentable — fix the named field and
re-validate; a blocked payload is never shown. Record the owner's answer against
the returned `ask_id`:

```
printf '%s' '<answer JSON>' | python3 ${CLAUDE_PLUGIN_ROOT}/scripts/validate-proposal-payload.py --ws "$WS" --answer <ask_id>
```

Offer: **each resolvable platform individually**, **all of them**, and **stop
here** (emit nothing). "Stop here" is a first-class outcome, not a failure.

**Emit exactly the chosen subset** — a comma-separated list, or `all` only when
the owner chose every platform:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py variants --slug <slug> --root <host-repo> --platforms <chosen> --ws "$WS"
```

An unchosen configured platform leaves **no file, anywhere**. Never widen the
subset — not to "complete the set", not because a platform is configured, not
because the previous emission included it.

If a variant carries `lede_retarget: true`, perform the **single** judgment step
`variants.md` defines for it and present it under the same proposal contract.
That is the variant flow's only other owner touchpoint; when the trigger does
not fire, emission is pure packaging and asks nothing.

## Step 3 — lint every emitted variant

Immediately after emission, run the profile-parameterized mechanical lint on
**each** emitted variant (zero LLM tokens; defects reported `path:line`):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/lint-platform-variant <variant-file> \
  --root <host-repo> --ws "$WS" [--dest-repo <output.drafts repo root>]
```

Pass `--dest-repo` when the profile declares a target directory layout. Report
each variant's result — pass or the findings. A lint defect is a **publish
blocker** for that variant (CAP-6 bucket): relay each finding; never re-run a
structure/prose/cold-read pass over a variant.

## Boundaries

- **No new projection code and no per-platform code path.** Which platforms come
  from config, how each is packaged comes from its profile — adding a platform is
  one profile file, never a change here.
- **`variant-staleness` and `site-record` stay separate invocations**, on their
  own triggers, documented in `variants.md`. This skill does not fold them in.
- **Never edit a variant in place.** A change routes to the canonical draft and
  the variant is re-emitted through this flow as a fresh publish decision.
