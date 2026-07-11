# Framework conventions (shared by F1–F4)

Every framework in this directory follows these conventions, so a draft's
structure and its editorial gate are unambiguous by inspection. The four
frameworks (`F1`–`F4`) supply only their body slots; the frontmatter and the
pointer block below are shared and rendered from user config — never hand-copied
or hardcoded.

## Slot syntax

- `{slot}` — a fill-in the pipeline replaces with real content.
- `*(prompt)*` — what the slot must answer; guidance, not output.
- **Lengths are targets, not limits.** Word counts like `(~120 words)` are
  annotations only; do not treat them as hard caps. The one genuine limit is the
  schema's own (e.g. `summary` ≤ 240 chars).
- **Title rule:** the title states the article's one specific claim, not its
  topic.
- A slot is **unfilled** while it still shows its `{…}` / `*(prompt)*` text.

## GATE slots (the editorial gate)

A heading marked **GATE** — e.g. `## GATE {Evidence}` or `## GATE {Pointer
block}` — is a mandatory editorial-gate slot (CAP-5). A framework with an
**unfilled GATE slot is not publishable**, and this is identifiable purely by
inspection: an unfilled GATE still shows its `{…}` prompt (or, for the pointer
block, a `NOT PUBLISHABLE` marker — see below). The fill preserves the `GATE`
marking verbatim, so a partially-filled draft with any GATE still showing its
prompt reads as not-publishable.

## Skipped interview inputs — per-slot effect (Story 10.5)

A slot **fed by an interview input** declares what happens when the owner
**skips** that question, as a `[SKIP: <effect>]` tag on the slot heading. The
interview engine records only the skip disposition (Story 10.3); **stage 3
applies the slot's declared effect** — the engine never decides it. The skip
choice's label in the interview states that slot's declared effect, so the owner
sees the consequence before choosing.

`<effect>` is exactly one of:

- **omit** — drop the slot from the article (structurally optional; no residue);
- **defer** — leave the slot for a later pass, unfilled but not blocking;
- **accept-later** — adopt the recommended answer at stage 3 without owner
  confirmation (used when a source-grounded default is safe to take silently);
- **verify** — fill the slot from inference and mark it `[VERIFY]` for the
  stage-4 owner pass;
- **blocker** — raise a publish blocker: the slot cannot be skipped away.

**Every GATE slot's skip effect is `blocker`** — a GATE is mandatory by
definition, so skipping its feeding question cannot silently drop it.

## Config-bound frontmatter

Every framework opens with an `article` frontmatter block. Its **field set,
`mode`/`language` enums, and per-language canonical vs. `mode: external`
syndication policy all come from user config** (`frontmatter.*` and
`syndication.*`; Story 1.2) — no site schema is baked into any framework.

Render it with:

```sh
scripts/render-frontmatter.py --language en   # canonical + syndication (dev.to)
scripts/render-frontmatter.py --language ja   # mode: external (JA on Zenn)
```

- A `canonical`-mode language emits `mode: canonical` plus a `syndication:`
  block whose `canonical_url` is derived from config.
- An `external`-mode language emits `mode: external` and the note that the site
  record is body-forbidden (Zenn is canonical via repo-sync).

Value slots (`{slug}`, `{title}`, …) are filled later by the pipeline (Story
4.4); `mode`/`language` and the syndication shape are resolved from config here.

## Shared pointer block (spec §3 invariant)

**Every framework ends with `## GATE {Pointer block}`.** Its content — focus
areas, site URL/name, and the related / newsletter / counterpart lines — is
drawn entirely from user config (`pointer_block.*`, `owner.*`). It is rendered by
one shared template so the block is **byte-identical across all four
frameworks**:

```sh
scripts/render-pointer-block.py --language en \
  [--related-title T --related-url U] [--counterpart-url U] \
  [--newsletter-status coming-soon|live]
```

The block is **state-dependent and conditional**, not a single static line:

- **Newsletter line** follows `pointer_block.newsletter.status`: `coming-soon` →
  RSS + follow links; `live` → capture link.
- **Related line** appears only when a related title *and* url are supplied.
- **Counterpart line** is language-conditional: an EN draft with a JA counterpart
  links Zenn; a JA draft with an EN counterpart links the English version;
  otherwise the line is omitted.

If a required identity value is missing from config, the renderer emits a
`NOT PUBLISHABLE` GATE marker instead of a silently blank block — so the pointer
GATE, too, is unambiguous by inspection.

## Visual slots (SPEC-article-visuals CAP-1)

Each framework declares its **expected visual(s)** as a slot, so a structurally
important visual has a defined place:

| Framework | Visual slot |
|---|---|
| F1 | one **overview diagram** |
| F2 | **optional** before/after or timeline |
| F3 | one **comparison table** (**required**) |
| F4 | one **landscape table or concept map** |

A visual slot is **proposed, not auto-filled** (Story 8.2): the pipeline offers it
under the owner-facing proposal contract, and the owner approves, modifies, or
declines. A **declined slot is omitted entirely** — the draft contains **no
`[Figure: …]` or placeholder residue** where a declined visual would have gone. A
slot is not a mandatory GATE: declining it leaves a structurally complete draft.
