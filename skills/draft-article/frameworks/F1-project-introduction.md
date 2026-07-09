# F1 — Project introduction

**Use when:** introducing a project you built (OSS, benchmark, tool).

**GATE (entry) — a framework-selection precondition, not a fill-in slot:** the
project has a tagged release or an equivalent shipped artifact. **No release →
write F2 (Engineering lessons) instead**, and save the introduction for launch.

Slot syntax, the config-bound frontmatter, and the shared pointer block are
defined once in [`CONVENTIONS.md`](CONVENTIONS.md) — F1 reuses them and does not
re-implement them. Section order below is load-bearing: fill every slot and the
result is structurally complete with nothing to reorganize.

## Frontmatter

Config-bound `article` frontmatter (rendered per language from user config —
canonical for EN/dev.to, `mode: external` for JA-on-Zenn; see
[`CONVENTIONS.md`](CONVENTIONS.md)). F1 fills its value slots:

- `title` — *(claim-shaped: what the project makes possible, not its name alone)*
- `summary` — *(≤240 chars: the problem + what the project does about it)*
- `topics` — *({kebab-case} tags)*
- `related.projects` — *(the introduced project's slug; F1 is about a project, so this is populated — not a features list)*

## {The problem}                                    (~120 words)
{(Describe the pain as the READER experiences it. Your project is not
mentioned yet. A reader with this problem must think "yes, that's me".)}

## {Why existing options fall short}                (~100 words)
{(Name 1–2 real alternatives and be fair to them — the gap you fill,
not a strawman. Fairness here is a credibility signal.)}

## {What I built}                                   (~150 words + 1 demo)
{(One-paragraph definition in plain language, then ONE concrete demo:
code block, screenshot, or command + output. Show, don't enumerate features.)}

## {The design decision that matters}               (~150 words)
{(The one non-obvious decision — e.g. "why JAX-native" — and what it COST.
A decision with no tradeoff stated reads as marketing.)}

## GATE {Evidence}                                  (~100 words + 1 figure/table)
{(A result, benchmark number, or worked example produced by the real system.
This slot empty = article not publishable (AP-10).)}

## {Limits and roadmap}                             (~80 words)
{(What it does NOT do, honestly. Highest-trust section for a technical reader.)}

## {Try it}                                         (3 steps max)
{(Install → minimal run → where to go next. Link repo/leaderboard/datasets.)}

## GATE {Pointer block}
*(The shared pointer block — see [`CONVENTIONS.md`](CONVENTIONS.md). Rendered
from user config; unfilled = not publishable.)*
