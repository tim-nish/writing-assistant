# Fork-gate consult-first

Before raising a human gate that presents **policy, architecture, or
prior-decision forks**, consult the served policy surface — so covered forks
become visible, overrideable **FYIs** and only genuinely new positions reach the
owner as **gates**. Applies the standing consult-first contract to every
fork-presenting stop point. Contract: `specs/spec-policy-fork-consultation/SPEC.md`
(#480, ratified `a7184b8`). Sibling of the divergence detector — same §3.1
intake, opposite trigger family (that skill triages decisions *already taken*;
this one triages decisions *being asked*).

Driven by `scripts/fork-consult.py`; the *semantic* step (does a served line
discriminate a fork's options?) is LLM-assisted and reaches the script as a
per-fork `consult` result.

## The pass (CAP-1/2/3)

At a fork-presenting stop point, before showing the table:

1. **Per in-scope fork, consult first (CAP-1).** For each fork whose content is
   **policy / architecture / prior-decision**, form the discriminating question
   from the option text and query the served surface through the **existing seam
   client** (`policy_lookup`, owner-realm grant, pinned bounded read) — one hit
   per in-scope fork, preceding the stop. **Purely mechanical/product forks are
   out of scope** and skip consultation. No new consult surface — only new call
   sites here.
2. **Classify (CAP-2/CAP-3):**

   ```
   python3 ${CLAUDE_PLUGIN_ROOT}/scripts/fork-consult.py present \
     --input "$WS/forks.json" --pin "<policy-source>@<commit>" \
     [--policy-source-available false]
   ```

   - **Covered + discriminates → FYI** (CAP-2): chosen option + verbatim quote +
     `file:line@commit` at the run pin, in a distinct FYI section. **Coverage is
     strict** — a merely *topical* quote that does not discriminate the options
     stays a **gate**. An FYI is **always shown, never silently applied**; the
     owner may **override inline**, which reopens it as a gate (a natural
     divergence signal for the sibling detector).
   - **Uncovered (or covered-but-topical) → gate** (CAP-3): ≤3 machine-proposed
     candidates with their partial grounding, **ordered by recontextualizing
     power**, **no pre-selected default**; the gate never times out into a
     choice.

3. **Fresh pin per run — no consultation cache.** The `--pin` is supplied per
   run; nothing caches a consult result between runs.

## Miss feedback (CAP-4) — proposal-only

Every uncovered in-scope fork is a **consult miss** (a distill-bug signal in the
run receipts). At the owner's gate answer, an owner "report upstream" choice
produces a **§3.1-conformant staging block** for manual copy into the upstream
intake:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/fork-consult.py emit-miss \
  --question "<the fork question>" --decision "<owner answer>" \
  --slug "<YYYY-MM-DD>-<gist>" --source-repo "<repo>" --created "<date>"
```

The block is a **conformance copy** of the hub §3.1 staging-file schema
(product-lab `specs/knowledge-architecture.md` §3.1 — the authority; hub wins on
any mismatch, a mismatch is a defect of this spec), with **no schema of its
own** — the same emitter the divergence detector (#436/#482) cites. This skill
is the **second emitter** into that intake: shared envelope, distinct payload.
The **upstream hub is never written**; the copy is a manual, approved owner step.

## Carrier — every fork-presenting stop point (no orphan mechanism)

Each site in this repo that presents a policy/architecture/prior-decision fork
table **resolves to an invocation of this skill or a declared exemption**:

- **Invocation — triage spec-lane re-offer** (`/triage-gh` step 6d, the
  alternatives AskUserQuestion): in-scope by definition (it presents
  policy/architecture/prior-decision alternatives) → runs this pass; covered
  alternatives demote to FYI, uncovered stay gates.
- **Invocation — spec-run fork tables** (bmad-spec / bmad-architecture fork
  decisions): in-scope → runs this pass before the fork table is shown.
- **Exemption — the gap interview** (`draft-article` Stage 2): already applies
  consult-first natively (Story 14.4 policy-seeded tension items + the
  editorial anchor) — its own consult path stands; not re-wrapped here.
- **Exemption — /commit-groups, /repo-cleanup, /publish-issues gates**: present
  **mechanical** choices (commit grouping, deletion approval, board mapping),
  never policy/architecture/prior-decision forks → out of scope, skip.

Adding a new fork-presenting stop point without an invocation or an exemption
row here is the orphan-mechanism defect the carrier check catches.

## Invariants

- **Never blocks a run.** `policy_source` absent/unavailable ⇒ all in-scope
  forks present as **gates**, **one logged line**, the run proceeds.
- **Never machine-final.** A covered fork is an *application of an existing
  ratified line*, always overrideable; an uncovered fork never auto-resolves.
- **No new consult surface, no cross-repo forwarding, no cache.**
- **Publication boundary:** FYIs, gates, and staging payloads carry only the
  served `file:line@commit` pointer grammar already public in this repo.
