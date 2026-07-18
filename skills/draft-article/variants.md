# Platform-ready variants — a standalone post-review invocation

Referenced from [`SKILL.md`](SKILL.md). Variant emission is a **separate
post-review invocation** (Story 13.69; SPEC-platform-variants CAP-1/CAP-3,
2026-07-18 amendments; SPEC-article-draft-pipeline CAP-4) — it is **not a
stage of the draft flow**, which ends at the `complete` gate with next step
review-article. This invocation consumes the **persisted canonical** at
`<output.drafts>/<slug>.md` — the product the `complete` gate wrote — never a
run-workspace copy. A canonical that exists only in a run workspace is
**refused with a pointed error** naming the missing persisted path: run the
draft flow's `complete` step first; the invocation never silently falls back
to `$WS/draft.md`.

Emit platform-ready copies of the **verified** canonical draft as **projections**
of the canonical draft. Which platforms, and each one's canonical policy, come
from user config (`syndication.policy` / `syndication.variants`) keyed by the
draft's `language` — **never a hardcoded mapping**; **how** each variant is
packaged (frontmatter fields, tag cap, `canonical_url` format,
diagram-`visuals` treatment) comes entirely from that platform's **profile** (a
machine-global declaration, SPEC-platform-variants CAP-2), so there is no
per-platform code path and adding a platform is one profile file.

**Emission is the owner's explicit publish decision (CAP-6/#226) — the pipeline
never auto-emits every configured platform.** First read the choices, then
present them **in-conversation** as a selection (never a path to open):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py variants --slug <slug> --root <host-repo> --list-platforms
```

Offer the owner: *emit each `available` platform / both / stop here.* Then emit
exactly their choice (a comma-separated subset, or `all`):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py variants --slug <slug> --root <host-repo> --platforms <chosen>
```

The **completion summary records the choice and its outcome** — which platforms
were offered, which the owner emitted, and where each file landed (an owner who
picks only one platform leaves no file for the others, anywhere).

- **Input:** the persisted canonical, loaded by `--slug` from the resolved
  `output.drafts` (the sanctioned form). A positional draft path is accepted
  only when it already **is** the persisted canonical (inside the resolved
  `output.drafts`); anything else is a hard error naming the expected
  persisted path and the `complete` remedy (`--allow-external-draft` is a
  test-only escape for check harnesses, never a production path).
- **Precondition:** the draft carries **zero `[VERIFY]` markers** — Stage 4 must
  be complete. Any unresolved marker aborts the invocation. The draft must also
  declare a resolved `audience` (the named reader) and `audience_id` (the
  compatibility identifier, Story 13.71) — an unfilled one is a hard stop.
- **Lede re-targeting proposal (Story 16.5; trigger amended by Story 13.71),
  the variant's only owner touchpoint.** For each emitted variant the pipeline
  fires a **deterministic trigger** — it compares the draft's declared
  **`audience_id`, `language`, and `register`** against the profile's (register
  defaults from language on both sides: `ja` implies です/ます; the free-text
  `audience` named reader is never compared — Story 13.71). When any of the
  three **differ** (e.g. a Zenn/JA profile for an EN draft) the
  variant carries `lede_retarget: true` and a `lede_proposals` entry. Perform
  **exactly one** judgment step for it: re-target the lede and framing to the
  profile's named reader (です/ます register for `ja`) **without introducing any
  claim absent from the canonical draft**, and present it under the
  [owner-facing proposal contract](../owner-facing-proposal-contract.md)
  (approve / modify / replace). When all three **match**, emission is
  pure packaging — **no proposal, no touchpoint** (a same-reader EN→dev.to
  emission fires nothing). The trigger is never your
  judgment over content; there is no `lede_retarget` profile field.
- **Emission metadata:** each emitted variant carries the canonical draft's
  content hash (a trailing `canonical-sha256` comment) so a later run can flag a
  variant whose source draft has since changed (Story 16.7). The hash is the
  **same** one the persisted canonical's own trailer records (sha256 over the
  content without the trailer — one convention, Story 13.68).
- **Projection, not rewrite:** the body carries over unchanged (claims, evidence,
  provenance, section structure); only frontmatter/packaging and the profile's
  declared visual treatment differ from the canonical draft.
- **EN / `mode: canonical`** (dev.to-style profile) → the full article text with
  the profile's frontmatter, whose `canonical_url` is composed from the owner's
  base value and the profile's format, pointing back at the site page.
- **JA / `mode: external`** (Zenn-style profile) → a repo-sync copy with the
  profile's frontmatter and the full body — the platform is canonical via
  repo-sync, so its profile declares `canonical_url: {policy: none}`. A profile
  whose `packaging.visuals` cannot render Mermaid HTML-comments each diagram and
  raises a render publish blocker (reported as `render_blockers`).
- Each variant is written to the **resolved `output.drafts`** location (Story
  1.3; `--out <dir>` overrides). Files are named `{slug}.{platform}.md`.
- **`output.drafts` may live outside the host repo — and should (#213):** the
  recommended destination is a directory in the owner's **private articles
  repository** (`~`/absolute paths supported; a relative value keeps resolving
  against the host root). When `output.drafts` is **undeclared**, ask the owner
  once, recommending that external default and saying why — articles are private
  assets and a host repo may be public — then record the answer with
  `resolve-writing-sources.py set-draft-location <path>` (it writes to the
  machine-global config, never into the host repo). When the resolved external
  directory **does not exist**, the invocation stops and names it: confirm the
  location with the owner, then re-run with `--create-out` (or create it by
  hand) — the pipeline never silently creates directory trees outside the host.

## Visual rendering per platform (SPEC-article-visuals CAP-5)

The two platforms render diagrams differently, so each variant handles a
Mermaid/figure-spec visual its own way:

- **Zenn variant** — **embeds the Mermaid source directly** (a ` ```mermaid ` code
  block). Zenn renders it natively, so the diagram appears with **zero manual
  work**.
- **dev.to variant** — dev.to does **not** render Mermaid, so the variant carries
  the **Mermaid/figure-spec inside an HTML comment** (`<!-- … -->`, invisible until
  rendered) and lists **each unrendered figure as a publish blocker** ("render to
  image before publishing") in the **completion summary's publish-blocker bucket**
  (Story 7.5 / CAP-6). The owner renders it to an image before publishing.

A **figure-spec** visual (no Mermaid) is handled the same way per platform: shown
where the platform can render it, otherwise carried in a comment and blocker-listed.

Each variant is publishable on its platform with **no manual reformatting beyond
filling the canonical URL**. The subcommand reports `next_stage: review` —
publication-readiness belongs to SPEC-article-review.

## Platform lint — every emitted variant gets it (Story 13.41, CAP-5)

Immediately after emitting each variant, run the **profile-parameterized
mechanical lint** on it (zero LLM tokens; each defect reported `path:line`):

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/lint-platform-variant <variant-file> \
  --root <host-repo> --ws "$WS" [--dest-repo <output.drafts repo root>]
```

Pass `--dest-repo` when the profile declares a target directory layout so the
existence check runs against the **`output.drafts` destination repo**. A lint
defect is a **publish blocker** for that variant (CAP-6 bucket) — relay each
finding; never re-run a structure/prose/cold-read pass on a variant.

## Stale-variant check — before any publish handoff (Story 13.41, FR60)

On a later invocation over already-emitted variants, and always **before handing
variants to the owner for publishing**, verify no variant's canonical draft has
moved since emission:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py variant-staleness <draft> --root <host-repo>
```

Any `publish_blockers` entry (`stale-variant` / `unrecorded-canonical-hash`)
goes to the completion summary's blocker bucket. The remedy is structural: route
the change to the canonical draft, then **re-emit** the variant through this
flow as the owner's explicit publish decision (which records the new hash) —
never edit the variant in place, and never let another stage (review included)
re-emit it implicitly.

## Post-publish next step — the site's external record (Story 13.41, FR62)

For a variant whose language maps to `mode: external` in `syndication.policy`
(the site holds a record, not the body), the completion summary's next-step
choice includes — **after the owner publishes** — "confirm the published URL →
generate the site record". This runs **outside** the per-article attention
budget (post-publish), and the offer is **re-presentable on any later
invocation** until the owner confirms; it is never silently dropped:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py site-record <draft> \
  --url <final published URL> [--date <real publication date>] --ws "$WS"
```

The output is a **ready-to-paste proposal** (≤ line budget, body forbidden)
written to `$WS` only — applying it to the site tree is the owner's act; the
pipeline never writes the site tree. Without `--url` it reports the offer as
pending — re-offer it next invocation.

## Command reference (variant subcommands of `draft-pipeline.py`)

The variant-emission subcommands of
`${CLAUDE_PLUGIN_ROOT}/scripts/draft-pipeline.py` — the authoritative flag
list, split out of the draft flow's reference table (Story 13.69). Positional
args are shown in `<angle brackets>`; `-` means "read from stdin".

| Subcommand | Purpose | Args / flags |
|---|---|---|
| `variants` | Emit platform-ready variants of the persisted canonical as profile-driven projections; emission is the owner's explicit choice — no `--platforms` reports options and emits nothing | `--slug <slug>` (the sanctioned form) `--platforms <ids\|all>` `--list-platforms` `--config-json` `--root` `--global-config` `--repo-config` `--out` `--create-out` `--ws` `--dry-run`; `<draft>` positional accepted only inside the resolved `output.drafts` (`--allow-external-draft` is test-only) |
| `variant-staleness` | Compare each variant's recorded canonical hash against the current draft; mismatches are publish blockers (Story 16.7) | `<draft\|->` `--variants <files…>` `--out` `--root` |
| `site-record` | Propose the site's `mode: external` record after the owner confirms the published URL (Story 16.9); proposal lands in `$WS` only | `<draft\|->` `--url` `--date` `--config-json` `--root` `--global-config` `--repo-config` `--ws` |
