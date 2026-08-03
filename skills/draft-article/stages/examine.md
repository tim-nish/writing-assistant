<!-- stages/examine.md — draft-article stage companion (Story 20.147, #1182/#1097/#1185/#1209).
     Loaded from the fill whenever a claim needs repository grounding; carries
     the examine step's full operating detail. Not a pipeline stage of its own:
     examine is a per-claim sub-step of the fill. -->

## Examine — per-claim repository grounding (during the fill)

Harvest is retired (amended 2026-08-02, #1182 — the amendments companion is
the authority) and **no fact sheet exists anywhere in the pipeline**. The
claim comes first: once the argument plan and the section intents exist, any
claim that needs repository grounding gets **one examine question** — claim
in, pinned material out, the pin born with the claim rather than two stages
before it:

```
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/examine.py --root <host-repo> --ws "$WS" \
  --claim "<the concrete claim, one sentence>" \
  [--scope "$WS/brief.json"] [--member <strand-index>] \
  [--anchor path:<glob> | symbol:<text> | ref:<sha|#123> | since:<date> | until:<date>]
```

**The tool never judges.** `verdict` is always `null` and `verdict_owner`
names the caller — *you*, the model that stated the claim, decide whether the
returned material supports, refutes, or misses it. A run that reads the
tool's output as a verdict has recreated harvest's error one layer down.

**The pin is recorded at the read that produced it.** With `--ws`, every
examination persists whole under `$WS/examinations/<claim-id>.json` — **its
own record and nothing else** — and `$WS/examination-pins.txt`, the run's
**declared pointer set**, is **derived** from those records in claim order
rather than appended to (#1248, story 20.162), so it is byte-identical
whether the examinations ran one after another or at once. The claim id is
`--claim-id` when the fan-out enumerated one, else `<slug>-<digest>` over the
whole claim; it is never a truncated slug, which used to let two long claims
sharing a prefix overwrite each other. Pass `--defer-ledger` when running
examinations concurrently and derive once at the join
(`examine.py --ws "$WS" --derive-ledger [--order <claim-ids>]`); a single
examination derives it itself and needs neither flag.

**Concurrent examinations are scheduled by the fill, not by this step** — the
enumeration, the dispatch, and the join are [`fan-out.md`](fan-out.md)'s (story
20.164, #1248). What binds HERE is unchanged by any of it: **one examination
answers one stated claim**, the claim exists before the read, and a claim that
emerges mid-fill gets its own ordinary examination at that moment. Enumeration
widened to claims that might be needed is a stockpile — harvest under a new
name — and is refused.

A sourced
claim in the provenance map cites the `cite` form verbatim (a bare sha for a
commit, `path:line@sha` for prose at HEAD, the URL for an issue); `derived`
inherits ≥2 of them. Never cite a pin no recorded examination produced.

**The time axis is the type (#1184).** Every item carries `time_axis`:
commits and issue threads carry one (episode-admissible); declared prose at
HEAD is `state_only` — a state claim may ground in it, an episode claim
(`sourced episode` in the map) may not, and `verify-provenance` refuses the
mismatch deny-never-warn. Commits are **anchor-addressed, never
keyword-searched**: without a `path:`/`symbol:`/`ref:`/date anchor the
commits source is skipped and says so — take an address from
`anchors_offered` and ask again rather than letting history be searched by
claim keywords.

**Anchor-finding lives HERE, per claim** (moved from probe by story 20.155,
#1224). Probe emits no anchors: it is a configuration and permission check and
has no claim to find them for. `anchors_offered` derives addresses from the
first hop's own hits — a searchable source is where an address comes from, and
history is what you ask once you have one. They are **offered, never
followed**: deciding which anchor is worth a second query is a judgment, and
the tool makes none.

**Reproducibility comes from the enumerator, not from a cache.** Candidate
files arrive in `resolve-writing-sources.py files` order, which is sorted at
the source (`resolve-writing-sources.py:1357`), so examining the same claim
against the same pin resolves to the same pointers in the same order. CAP-10's
per-source budget and blob-keyed cache were harvest-shaped remedies for a
whole-corpus pass and are **not** carried here — corrected in the spec on
2026-08-02 (#1235), with the trigger that would earn each of them stated
there.

### Scope is derived, not chosen (#1097, #1185)

Where the run's brief carries `examine_scope` (a terrain-originated brief —
the union of the selected Strands' served `projects:`), pass it as `--scope`,
and `--member <index>` when the claim belongs to one selected Strand. The
refusal layer is `scripts/terrain_scope.py`'s, consumed not restated: a
repository outside the served attribution is **refused, not searched** (exit
3) — grounding a claim in a repository the experience did not happen in is a
false attribution. Relay a refusal's `line` verbatim; it is the oracle
binding holding, never an error to work around. A union of one repository
means the scope question is never asked; hub-only and `portfolio-wide`
members ground in their served arcs, not in any repository. **No gate asks
the owner to compose or approve a file list** — the owner supplied at most a
region at the brief, and this step does the enumerating, per claim (#1209).
With no brief-carried scope (a cold run), `--scope` is omitted and the
declared-source boundary of `writing-sources.yaml` is the fence, as always.

**The read scope INTERSECTS the declared boundary and never widens it**
(moved here from probe by story 20.154, #1224 — probe no longer reads, so
the invariant now binds where reading happens). Whatever a claim is examined
against must intersect the declaration: a brief-carried region can only
NARROW what is read, never add an undeclared repository, and the enumeration
defers to `resolve-writing-sources.py files` — the one file boundary, never a
second walk that drifts from it.

### Coverage is reported, never implied

Every examination's output separates `searched` (what was actually consulted,
with per-source counts) from `skipped` (what was not, each with its reason).
**An empty result from an unreachable source is a different finding from an
empty result from a read source** — `gh` unavailable, no declared prose, or
an anchorless commits query are *cannot-determine*, never absence. When an
examination grounds nothing, say which of the two findings it is, from the
record; an absence claim is admissible only over sources `searched` lists.

**The prose budget is per declared repository, and what it crowded out is
disclosed** (story 20.186, #1337). A single match budget spent in path order
gave the whole of it to whichever repository sorted first — every prose hit
came back from one declared repository and none from the host's own documents,
with nothing in `searched`/`skipped` to show it, because the source *was* read.
So the budget is split across the declared repositories in the enumerator's
order, an unused share is redistributed to the repositories that still have
matches, and the prose entry in `searched` carries `budget`: per repository,
its `share`, what it `returned`, and `crowded_out` — the matches that were read
and matched and then dropped for want of budget. **`crowded_out` is a third
finding**, neither `skipped` (a source never read) nor `found` (a per-source
count): read it before treating a repository's silence as absence, and ask
again with narrower terms or a larger `--limit` when it is non-zero. A record
carrying no `budget` block predates the disclosure — that is *unknown*, never
zero. The split derives from the declaration and the pin alone, never from what
matched, so the same claim examined twice against the same pin still gives
byte-identical records.

### The article floor, restated over examinations

The floor is unchanged in shape: **every article carries ≥1 sourced or
derived claim resolving at the ship gate** (SPEC-article-review, #896).
"Resolving" now reads over this step's record: the sidecar map's
sourced/derived pointers are verified against the run's declared pointer set —
`$WS/examination-pins.txt` plus the interview answer ids — via
`verify-provenance --fact-sheet "$WS/examination-pins.txt"` (the flag name
predates #1182; the file it takes is the pin ledger). Whether the floor
*changes shape* when every claim is examined individually is the amendment's
own open question, carried, not decided here — until it is ruled on, the
≥1-claim floor binds exactly as before, and per-claim examination neither
relaxes nor replaces it.

### Re-grounding (the missing-input repair hop)

A review/quality-gate finding classified `missing-input` whose remediation is
`examine <the claim to ground>` re-enters **this step**, not a stage: the hop
runs one examination for the named claim and the fill resumes
(`repair-hop`'s `next_stage: fill`). The legacy `re-harvest <target>` spelling
maps to the same route with a disclosure — there is no harvest to re-enter.
The two-cycle bound is unchanged.
