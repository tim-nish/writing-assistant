#!/usr/bin/env python3
"""terrain_brief.py — the BRIEF ARTIFACT and the edit-set iteration loop over
the member set (Story 20.80, #1029; SPEC-writing-assistant, the 2026-07-31
(#1025) amendment).

WHY THIS MODULE EXISTS. `topic-map-directions.py` is HYPHENATED and therefore
unimportable, which is the constraint the #1025 amendment dissolves by making
that path a thin CLI shim: argparse and dispatch stay there, the composition
moves into importable siblings like this one.

WHAT IT CONTAINS: the artifact half of the brief — its lifecycle block, its
writer and its SANCTIONED READER — together with the edit-set loop that
recomposes over a changed member set (`_parse_edit`, `_edited_indexes`,
`_base_composition_pin`, `_composition_record`, `_iteration_block`). They move
together because they are one closure: the loop reads a written artifact, checks
the pin it was composed at, and writes the next one beside it. What COMPOSES a
brief is not here — `brief_from_answer` and `_brief_from_index` stay with the
dispatch that reaches them.

The two contract blocks below travel with the code they govern, unedited: the
brief is read back BY DESIGN, and the View beside it never is. Read them
together — the point is that the two rules are opposite and must stay apart.

This is a MOVE, not a rewrite: every definition below is the one that stood in
`topic-map-directions.py`, unchanged, and composed output is byte-identical for
the same inputs (Story 20.80 AC4).
"""

import hashlib
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from terrain_text import (  # noqa: E402
    BRIEF_EDIT_OPTION_LABEL,
    BRIEF_LIFECYCLE,
    _brief_edit_option_effect,
    _brief_iteration_line,
    _brief_lifecycle_line,
    _brief_traversal_line,
    _fit,
)
# The refusal helper the whole terrain surface refuses through.
from terrain_members import (  # noqa: E402
    _err,
)
# The pin-half naming the edited composition's mismatch message uses — the same
# one the answer's own pin check uses, so both halves of the loop's pin
# discipline read identically.
from terrain_select import (  # noqa: E402
    _which_half_moved,
)

# --------------------------------------------------------------------------
# THE BRIEF ARTIFACT (Story 20.75, #994; SPEC-terrain CAP-3, the named-artifact
# clause added 2026-07-31)
#
# READ THIS BESIDE `write_view` ABOVE, BECAUSE THE CONTRACTS ARE OPPOSITE.
# Every neighbouring artifact this script emits is write-only by contract: the
# View is a RENDERING regenerated per invocation, never read back, and deleting
# it loses nothing, because it can always be recomposed from the map.
#
# The brief is not a rendering. It is THE OWNER'S DECISION — what they selected
# and what they said about it — and it cannot be recomposed from anything: the
# map does not contain it. So **re-opening it is the requirement, not a cache**
# (CAP-3: "The never-read-back rule does not bind here, and the difference is
# the point"). `read_brief_artifact` below is a sanctioned reader, and its
# existence is the difference, stated here so nobody "fixes" it into agreement
# with its neighbours.
#
# What is NOT licensed by that difference, so the two rules stay apart:
#   * no rendering is cached across invocations — screens, Views and reports
#     are still recomposed every time, and nothing here reads one back;
#   * the artifact never becomes an index or a lookup — it is read by the
#     owner returning to their own brief, addressed by the path they were told.
#
# WHERE IT LIVES: SUPERSEDED IN PART on 2026-08-03 (Story 20.191, #1342) — the
# durable copy now lands in the Brief's HOME, a directory in a repository
# resolved by `resolve-paths.py terrain-briefs-dir` and addressed by the
# Brief's stable id; see "THE DURABLE HOME AND THE STABLE ID" below. The
# workspace copy described here is unchanged and is still written, because the
# within-sitting iteration chain lives beside it (`--from`/`--out`) and this
# story deletes nothing. What follows is that workspace copy's own rule:
#
# the per-run workspace, minted by
# `resolve-paths.py new-run --terrain` (D1 — the resolver owns every storage
# path; this script still just writes where it is told, exactly as `--view`
# does). That is machine state, outside every working tree, which is also what
# keeps the publication boundary intact: the artifact carries `pins.hub`, a
# real hub sha, and #935 relocated Terrain's run workspaces out of this public
# repository for precisely that reason.
# --------------------------------------------------------------------------

# The artifact's default basename. A caller may pass any path under the run
# workspace — Story 20.77's iteration loop holds several briefs in one sitting,
# one per member-set variant — so the NAME is the artifact's identity and this
# is only the default. Declared once, like VIEW_FILENAME.
BRIEF_FILENAME = "brief.json"


def _brief_lifecycle(state, history=None):
    """The lifecycle block carried inside the artifact and printed at the gate.

    Carries the whole ordered sequence and not just the current state: AC5's
    "composed → inspected → adopted" is legible only if the owner can see what
    follows what.
    """
    hist = list(history or [{"state": state}])
    return {"state": state, "states": list(BRIEF_LIFECYCLE),
            "line": _brief_lifecycle_line(state),
            # WHAT ACTUALLY HAPPENED, beside what comes next (Story 20.121,
            # #1118). The line above shows the whole machine with the current
            # state bracketed; bracketing marks where the owner IS, never where
            # they HAVE BEEN, so a state the run skipped rendered as though it
            # had occurred. Both render: they answer different questions, and
            # collapsing them loses whichever is dropped.
            "traversal": _brief_traversal_line(hist),
            "history": hist}


# --- The artifact's key set is an ALLOWLIST, refused at write time -----------
# (Story 20.125, #1145; SPEC-terrain amendments 2026-08-01.)
#
# TWO CLASSES WERE CLOSED BY NAME AND BOTH RETURNED UNDER NEW NAMES. #1048
# closed a 130 KB `substitution_candidates` blob; #1078 closed an artifact of
# 21 keys carrying rendered screen sentences and process self-documentation.
# Measured after both fixes, on run 20260801T131120-663074: `brief.json` 41.9 KB
# with `iteration` at 8.7 KB and `candidate_theses` at 5.3 KB of option labels,
# effect prose, command templates and verify/adopt instructions; `brief-out.json`
# 270 KB of which `consultant` alone was 200 KB. Removing named keys is a denial
# list, and a denial list's non-member fallback is ADMIT — which is the shape,
# not the contents, and it is why the class came back twice.
#
# SO THE WRITER HOLDS THE SET AND REFUSES. Not a filter: a filter that strips an
# unlisted key silently is the same shape one layer down, and would let the next
# payload arrive with nobody deciding it. Refusing makes adding a field an
# amendment — which is the closure the contract asks for.
#
# THE LIST IS WHAT THE RATIFIED CLAUSES ALREADY PUT HERE, not a re-decision of
# them: `presentation.md`'s "what the brief CARRIES" (member set, served
# material, pins, harvest scope, thesis state with its offered candidates and
# recommendation, adopted claim, free text), plus the selection address and the
# named-artifact surface that clause's own neighbours ratified. What #1078 and
# #1093 removed stays removed — `_decision_record` still projects — and this
# adds the floor beneath that projection rather than replacing it.
BRIEF_KEYS = frozenset({
    "brief",            # the composed string that crosses into drafting
    "provenance",       # the closed pair (#1050): owner-authored | terrain-adopted
    "origin",           # how the brief was arrived at (free-form | adopted-*)
    "index", "indexes", "pin",   # the selection, and the pin it was made against
    "note",             # the owner's free text, or null (#1080)
    "adopted_claim",    # the candidate the owner adopted
    "thesis",           # its state: candidates-pending | adopted
    "candidate_theses",  # what it was adopted FROM (#1079)
    "members", "pins",  # the member set with its served material, and both pins
    "examine_scope",    # ratified 2026-07-29 (#896): the union of members' projects
    "gaps",             # every member's writability verdict, not just the first
    "lifecycle",        # composed -> inspected -> adopted, with its history
    "iteration",        # the composition chain — unrecomposable owner history
    "step", "artifact",  # the named-step identity and the artifact's own address
    # FOUND BY THE ALLOWLIST ITSELF, on the run that introduced it — which is
    # the mechanism working rather than a gap in it. Neither key appears in the
    # ratified CARRIES list, and both are decision content:
    "partition_proposal",  # the k-group partition OFFERED at the gate (#988) —
                           # provenance of the owner's approve/modify/decline,
                           # the same role `candidate_theses` plays for a thesis
    "journey_incorporation",  # how the members' journey material enters the
                              # article (Story 20.166, #1045) — a DISCLOSURE
                              # riding the brief, present only where served
                              # arcs exist and a thesis is adopted; carries
                              # the offered options and the adopted choice,
                              # the same provenance role `candidate_theses`
                              # plays for the thesis
    "plain_register",         # the child-level commitment both article ends
                              # realize (Story 20.212, #1411) — a disclosure
                              # riding the brief once a thesis is adopted;
                              # carries the offered candidates and the
                              # adopted commitment, the same provenance role
    "structure_candidates",   # THIS article's composed structure (Story
                              # 20.211, #1410) — a disclosure riding the
                              # brief once a thesis is adopted; carries the
                              # offered candidates, the adopted structure,
                              # and its `framework_matched` provenance
                              # (explicit `bespoke`, the #911 instrument),
                              # the same provenance role as its two siblings.
                              # Decision content per the #1414 amendment's
                              # Brief-disclosure clause.
    "edit",                # the signed set change (`+L12 −L3`) that produced a
                           # recomposition (#997). The owner names what changes,
                           # so this is unrecomposable owner history, not a
                           # rendering: the chain cannot be replayed without it
    "answer_as_given", "note_is", "selection_summary", "thesis_origin",
    "stage",            # the emitting stage, read by the pipeline seam
})


def write_brief_artifact(path, payload):
    """Write the brief artifact. READ BACK BY DESIGN — see the block above.

    REFUSES AN UNLISTED KEY (Story 20.125, #1145). The whole family goes
    through here — `brief.json`, its recompositions, and `brief-open`'s
    write-back — so this is the one place a new payload could enter, and it is
    where the closure belongs.

    Deliberately not `write_view`'s `_ensure_view_dir`: that helper drops a
    self-ignoring `.gitignore` because the View lands inside a working tree.
    This lands in a run workspace under the machine state root, where there is
    no tree to keep clean and an ignore file would be noise.
    """
    unlisted = sorted(set(payload) - BRIEF_KEYS)
    if unlisted:
        raise ValueError(
            "the brief artifact refuses "
            + ", ".join(repr(k) for k in unlisted)
            + ": its key set is an allowlist (`BRIEF_KEYS`), because removing "
              "keys by name is a denial list whose non-member fallback is "
              "admit — the shape that let the same class return twice under "
              "new names (#1048, #1078). If this key is decision content, add "
              "it to the allowlist and amend SPEC-terrain's content clause; if "
              "it is a rendering or a gate input, it belongs on stdout, not in "
              "the record.")
    d = os.path.dirname(path)
    if d:
        os.makedirs(d, exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    return path


def read_brief_artifact(path):
    """Re-open a written brief (AC4). The sanctioned reader — see the block
    above for why one exists here and nowhere else in this script."""
    with open(path, encoding="utf-8") as fh:
        payload = json.load(fh)
    if not isinstance(payload, dict) or "brief" not in payload:
        raise ValueError("not a brief artifact (no `brief` key)")
    return payload


# --------------------------------------------------------------------------
# THE DURABLE HOME AND THE STABLE ID (Story 20.191, #1342; SPEC-terrain
# amendments, the 2026-08-03 block)
#
# The block above says the artifact "is read by the owner returning to their
# own brief, addressed by the path they were told" — and that is exactly what
# broke. The path was a per-run workspace keyed by recency, which the pipeline
# already distrusted in its own words (`brief_source` records PINS FIRST
# "because the path is a state-dir location that goes stale by relocation while
# still looking authoritative", `skills/draft-article/stages/stage0.md`). So
# the Brief gains a home in a repository and an address that is not a path:
#
#   * WHERE — `resolve-paths.py terrain-briefs-dir`. The home is the resolver's
#     to know (D1); nothing here composes it, and the caller passes the
#     directory exactly as it passes `--out` and `--view` today.
#   * WHO — `write_brief_artifact`, unchanged. No second writer exists: the
#     home copy goes through the same allowlist-refusing writer as the
#     workspace copy, with the same payload object, so the two are identical
#     in content by construction rather than by a comparison someone must run.
#   * WHAT IT IS CALLED — `brief_id` below: a digest of what the Brief ALREADY
#     CARRIES. Never a fresh token per write, or saving the same Brief twice
#     would leave two Briefs in a home whose listing is its enumeration.
#
# WHAT THE ID IS COMPUTED FROM, and why each part: the composition PIN (the
# Brief's indexes name Strands only at that pin), the member INDEXES and the
# composed BRIEF STRING. Together these are the composition — two Briefs
# agreeing on all three are the same decision under any reading, and a
# lifecycle transition (`composed → inspected → adopted`) touches none of
# them, which is the property that makes the id survive a re-open. What is
# DELIBERATELY excluded is anything a re-render can change: lifecycle,
# iteration bookkeeping, the artifact block, the gate's own renderings.
# --------------------------------------------------------------------------

BRIEF_ID_PREFIX = "brief-"
# Long enough that a collision is not a practical concern across one host
# repo's Briefs, short enough to be read aloud and typed at a gate. The whole
# digest would be neither, and the id is an owner-visible address.
BRIEF_ID_LEN = 12


def brief_id(payload):
    """The Brief's stable id: deterministic from its pin and its composition.

    DETERMINISTIC, NOT MINTED. The same composition written a second time —
    re-opened, transitioned, written back — resolves to the same id and so to
    the same file in the home. An id minted per write would turn the home's
    listing (which IS its enumeration) into a pile of near-duplicates nobody
    could choose between, which is the failure the home exists to remove.
    """
    pins = payload.get("pins") or {}
    basis = json.dumps(
        {"pin": str(pins.get("terrain") or payload.get("pin") or ""),
         "hub": str(pins.get("hub") or ""),
         "indexes": [str(i) for i in (payload.get("indexes") or [])],
         "brief": str(payload.get("brief") or "")},
        sort_keys=True, ensure_ascii=False)
    digest = hashlib.sha256(basis.encode("utf-8")).hexdigest()
    return BRIEF_ID_PREFIX + digest[:BRIEF_ID_LEN]


def home_brief_path(home_dir, payload):
    """Where this Brief lives in the home: `<home>/<stable id>.json`.

    `home_dir` is the resolver's answer (`resolve-paths.py
    terrain-briefs-dir`), passed in by the caller — this module composes the
    NAME, which is the artifact's identity, and never the location, which is
    storage layout (D1).
    """
    return os.path.join(home_dir, brief_id(payload) + ".json")


def write_brief_home(home_dir, payload):
    """Write the Brief to its durable home, and return the path written.

    A one-line delegation ON PURPOSE: the home is a LOCATION, not a second
    artifact class, so it gets no writer of its own. Everything the write
    refuses, records or formats is `write_brief_artifact`'s, unchanged.
    """
    return write_brief_artifact(home_brief_path(home_dir, payload), payload)


def write_brief_record(record, path=None, home_dir=None):
    """Write ONE decision record to every location it has, and return them.

    The workspace copy and the home copy come from the same object through the
    same writer, so they are identical in content by construction — there is no
    second composer whose output could drift, and no comparison anyone has to
    run. A location that was not named is simply not written.
    """
    written = []
    if path:
        written.append(write_brief_artifact(path, record))
    if home_dir:
        written.append(write_brief_home(home_dir, record))
    return written


def copy_to_home(path, home_dir, record, stderr=None):
    """Copy an opened Brief into the home. Returns `(written_path, notice)`.

    THE WHOLE MIGRATION, IN ONE PLACE, so the CLI holds none of it: the
    allowlist is applied exactly as the transition write applies it (a Brief
    predating `BRIEF_KEYS` still migrates, with what it loses named), the write
    goes through the sanctioned writer, and the notice is composed here beside
    the act it describes rather than at a call site that could forget it.

    `notice` is None when the Brief is already in its home — an open of the
    home copy migrates nothing and must not claim to. With a `stderr` stream
    the notice is written to it and the return is the written paths alone, so
    a caller cannot hold the migration and forget to state it.
    """
    legacy = sorted(set(record) - BRIEF_KEYS)
    if legacy:
        record = {k: v for k, v in record.items() if k in BRIEF_KEYS}
    notice = home_migration_notice(path, home_dir, record)
    written = write_brief_home(home_dir, record)
    if notice and legacy:
        notice += (" Keys predating the artifact allowlist ("
                   + ", ".join(repr(k) for k in legacy)
                   + ") are not carried into the home copy.")
    if stderr is None:
        return written, notice
    if notice:
        stderr.write(notice + "\n")
    return [written]


def _brief_label(payload):
    """An owner-meaningful name for a brief, DERIVED and never stored (AC7).

    Date, member set, and the thesis's first words — every part computed from
    fields the artifact already carries. No naming store, no id field and no
    slug is added: a stored name is a second identity to keep in sync with the
    one the path already provides.

    MOVED HERE UNCHANGED (story 20.192, #1343). It stood in
    `topic-map-directions.py` beside the re-open it named; the stage-0
    selection gate now enumerates the home and needs the same name for each
    Brief it offers. Two composers would be two names for one artifact, which
    is the second identity this docstring already refuses — so the one
    composer moved to the module that owns the artifact, and the CLI shim
    imports it back.
    """
    life = payload.get("lifecycle") or {}
    when = ""
    for h in reversed(list(life.get("history") or [])):
        if h.get("at"):
            when = str(h["at"])[:10]
            break
    ids = list(payload.get("indexes") or [])
    if not ids and payload.get("index"):
        ids = [payload["index"]]
    who = ", ".join(str(i) for i in ids[:3]) + ("…" if len(ids) > 3 else "")
    text = str((payload.get("thesis") or {}).get("text")
               or payload.get("adopted_claim")
               or payload.get("brief") or "").strip()
    words = " ".join(text.split()[:8])
    parts = [p for p in (when, who and f"[{who}]", words) if p]
    return " — ".join(parts) or "an unnamed brief"


def home_migration_notice(path, home_dir, payload):
    """The migration statement owed by a Brief found OUTSIDE the home, or None.

    STATED, NEVER SILENT (Story 20.191 AC3), and never a deletion: an old
    workspace Brief still opens exactly as it did, keeps its file, and is
    copied — not moved — into the home under its stable id. What the owner is
    told is where the durable copy now is and that the old one was left alone,
    because a relocation a person cannot see is the same defect as the stale
    path this story is fixing, one directory along.
    """
    target = home_brief_path(home_dir, payload)
    if os.path.abspath(path) == os.path.abspath(target):
        return None
    return (f"note: this brief was opened from {path}, which is a per-run "
            f"workspace — the location the pipeline already treats as going "
            f"stale by relocation. Its durable home copy is "
            f"{target}, written under the brief's stable id "
            f"({brief_id(payload)}). Nothing was deleted or moved: the "
            f"workspace copy is still there and still opens.")


# --------------------------------------------------------------------------
# THE ITERATION LOOP OVER THE MEMBER SET (Story 20.77, #997; SPEC-terrain
# CAP-3, the iteration-loop clause added 2026-07-31)
#
# THE SEMANTICS WERE ALREADY RATIFIED AND SHIPPED, AND NOTHING HERE
# RE-IMPLEMENTS THEM: a claim is pinned to the member set it was composed over
# and RECOMPOSES when that set changes — a set change being a gate EVENT
# rather than a refresh — which `_brief_from_index` has done since Story
# 20.54. What was missing was the MOVE. The gate offered adopt, narrow, or "go
# back to Screen 2 and pick differently", so an owner developing a thesis by
# trying members had to leave the gate and lose the composition. What is added
# is therefore ONE option class — `+Lxx −Lyy → recompose` — that RESOLVES TO A
# MEMBER SET AND THEN TAKES THE EXISTING PATH.
#
# That routing is the whole design, and it is what preserves the properties
# the path already carries: the pin discipline (a missing or mismatched pin
# refused, with `_which_half_moved` naming which half of the composite pin
# moved), and the `recomposition` block whose inputs are the selected members'
# served claims AND NOTHING ELSE, so a composer at the gate cannot widen the
# scope past what the owner pointed at. An edit changes WHAT the owner pointed
# at; it does not loosen the rule that only that reaches the composer.
#
# AN EDIT NEVER RE-RANKS OR FILTERS. The owner names what changes: an addition
# nobody asked for is the second proposer, and a silent drop breaks the
# completeness invariant that follows the member set into drafting. So a drop
# of a non-member and an add of an existing member are both REFUSED with the
# current set stated, rather than absorbed as no-ops — a no-op edit means the
# owner believes something false about the set, and proceeding would compose
# over that belief.
#
# RETENTION IS WITHIN-SITTING, AND THAT IS WHAT KEEPS IT CLEAR OF THE
# NEVER-READ-BACK RULE (AC4). The chain of prior compositions is carried in
# the brief artifacts THEMSELVES, inside ONE run workspace: `--from` names the
# composition being edited and must sit beside the `--out` this one writes.
# There is no index, no store and no key a later invocation could look up —
# and a new invocation mints a new workspace at Step 0, so it begins with an
# empty chain and can carry nothing forward. That is the difference between
# comparison held for a sitting and a cache, and it is enforced by the
# same-workspace refusal below rather than left to convention.
# --------------------------------------------------------------------------

_EDIT_TOKEN = re.compile(r"^([+\-−])(\S+)$")


def _parse_edit(answer):
    """The owner's edit to the member set: `+L12 −L3`, or `add`/`drop` lists.

    An UNSIGNED token is REFUSED rather than guessed at: `L12` on its own
    could mean add it or select only it, and choosing between those for the
    owner is the move this option class exists to remove.
    """
    adds = [str(x).strip() for x in (answer.get("add") or []) if str(x).strip()]
    drops = [str(x).strip() for x in (answer.get("drop") or []) if str(x).strip()]
    raw = str(answer.get("edit") or "").strip()
    if raw:
        # The option's own label ends `→ recompose`, so an answer that echoes
        # the label is naming the option, not a Strand called "recompose".
        raw = re.sub(r"([+\-−])\s+", r"\1", raw.split("→")[0])
        for tok in re.split(r"[,\s]+", raw):
            if not tok:
                continue
            m = _EDIT_TOKEN.match(tok)
            if not m:
                raise SystemExit(_err(
                    f"{tok!r} in the edit {answer.get('edit')!r} carries no "
                    "+ or −. An edit names what CHANGES about the set — "
                    "`+L12 −L3` — and an unsigned index cannot be told from a "
                    "fresh selection, so it is refused rather than guessed at."))
            (adds if m.group(1) == "+" else drops).append(m.group(2))
    if not adds and not drops:
        return None
    return {"add": adds, "drop": drops}


def _edited_indexes(base_indexes, edit):
    """The edited member set: the base set, minus the drops, plus the adds.

    Order is the owner's throughout — the surviving members keep the order
    they were selected in and the additions land after them, because
    re-ordering would quietly restate a set they did not restate.
    """
    adds, drops = edit["add"], edit["drop"]
    both = [i for i in adds if i in drops]
    if both:
        raise SystemExit(_err(
            f"{', '.join(both)} is both added and dropped in one edit. An "
            "edit states what changes, and an index that changes in both "
            "directions states nothing — name it once."))
    absent = [i for i in drops if i not in base_indexes]
    if absent:
        raise SystemExit(_err(
            f"{', '.join(absent)} is not in the set being edited "
            f"({', '.join(base_indexes)}), so dropping it would change "
            "nothing. An edit names what changes — a drop of a member that is "
            "not there is a mistake about the set, not a no-op, so it is "
            "refused with the set stated."))
    already = [i for i in adds if i in base_indexes]
    if already:
        raise SystemExit(_err(
            f"{', '.join(already)} is already in the set being edited "
            f"({', '.join(base_indexes)}). Adding it would change nothing, "
            "and an edit that changes nothing recomposes the same claim over "
            "the same set — the set is stated here so you can see it."))
    out = [i for i in base_indexes if i not in drops]
    for i in adds:
        if i not in out:
            out.append(i)
    if not out:
        raise SystemExit(_err(
            "this edit empties the member set, and there is no claim to "
            "recompose over nothing. Drop fewer members, or stop here — "
            "stopping is a first-class outcome."))
    return out


def _base_composition_pin(base, map_pin, map_data):
    """The pin discipline, applied to the composition being EDITED (AC6).

    The answer's own pin is checked by `_brief_from_index` exactly as before.
    This is the second half the loop makes possible: the base composition was
    itself pinned, and editing a set composed at a pin the map has since moved
    past would attach the recomposition to indexes that no longer mean what
    they meant. Refused, with which half moved named where the artifact
    recorded the halves.
    """
    pins = base.get("pins") or {}
    base_pin = str(pins.get("terrain") or base.get("pin") or "").strip()
    if not base_pin:
        raise SystemExit(_err(
            "the brief being edited records no pin, so its member set cannot "
            "be proven to name the same Strands as this map. It is refused "
            "rather than re-resolved — select afresh from the screens."))
    if map_pin and base_pin != map_pin:
        moved = _which_half_moved(
            {"destination_pin": pins.get("destination"),
             "hub_pin": pins.get("hub")}, map_data or {})
        raise SystemExit(_err(
            f"pin mismatch: the brief being edited was composed at "
            f"{base_pin}, but this map is at {map_pin}. {moved} Its indexes "
            "may now name different Strands, so the edit is refused rather "
            "than re-resolved. Re-run the map and choose from the fresh "
            "screens."))
    return base_pin


def _composition_record(payload, n, edit=None, artifact=None):
    """One composition, as the loop retains it (AC3).

    Enough to COMPARE theses across set variants — the claim, the set it was
    composed over, its pins, the edit that produced it, where it lives — and
    no more. Never the whole payload: each artifact would then carry every
    earlier one whole, and a comparison the owner cannot read is not one.
    """
    return {"n": n,
            "brief": payload.get("brief"),
            "origin": payload.get("origin"),
            "indexes": list(payload.get("indexes") or []),
            "members": list(payload.get("members") or []),
            "pins": payload.get("pins"),
            "edit": edit,
            "artifact": artifact}


def _iteration_block(out, prior, edit, artifact_path):
    """The loop's state at the gate: the option (AC1), the chain (AC3), and
    the scope of the retention (AC4), stated rather than implied."""
    n = len(prior) + 1
    record = _composition_record(out, n, edit, artifact_path)
    return {
        "n": n,
        "line": _brief_iteration_line(n, len(prior)),
        # AC1 — the option class as DATA, so the gate offers it without
        # inventing either its wording or the form the answer takes. It sits
        # beside the existing options; nothing it replaces is removed, and
        # "go back to Screen 2" simply stops being the only way to change the
        # set.
        "option": {
            "label": BRIEF_EDIT_OPTION_LABEL,
            "effect": _fit(_brief_edit_option_effect()),
            "editable": list(out.get("indexes") or []),
            "answer": {"edit": "+<index> −<index>", "pin": out.get("pin")},
            "command": ("topic-map-directions.py brief --answer <answer> "
                        "--map <map> --from "
                        f"{artifact_path or '<this brief, written with --out>'}"
                        " --out <the next brief in this same workspace>"),
        },
        # AC3 — every composition of this sitting, this one last.
        "compositions": prior + [record],
        # AC4 — said on the surface, because retention that does not state its
        # scope reads as a cache.
        "retention": ("within this sitting only — the chain lives in this run "
                      "workspace's own brief artifacts, and a new invocation "
                      "mints a new workspace, so nothing is carried across "
                      "invocations. Comparison held for the sitting, never a "
                      "cache"),
    }


# --- WHICH brief a bare `open the brief` reaches (Story 20.92, #1042) --------
#
# MOVED HERE FROM `topic-map-directions.py` on 2026-08-03 (Story 20.191),
# unchanged line for line — the same MOVE the #1025 amendment prescribes:
# argparse and dispatch stay in the hyphenated CLI, composition moves into
# importable siblings. It belongs beside the artifact's writer, its reader and
# its addressing, because "which brief" is an ADDRESSING question, and the
# durable home now answers a second form of it. The duplicate
# `BRIEF_ARTIFACT_NAME` constant it carried is gone: `BRIEF_FILENAME` above is
# the one declaration of the artifact's default basename, and two spellings of
# one name is exactly the drift the constant existed to prevent.

def _resolve_newest_brief(root=None):
    """The brief a bare `open the brief` reaches (Story 20.92, #1042).

    THE RULE IS STATED AND DETERMINISTIC, never a heuristic the owner cannot
    predict: the NEWEST terrain run workspace — run ids are timestamps, so the
    newest is the last one in sorted order, and the `latest` symlink is skipped
    because it is a shorthand rather than a distinct run — and inside it the
    artifact named `brief.json`.

    A workspace may hold several brief artifacts: the edit-set iteration loop
    writes each recomposition to its own name in the same workspace. Those are
    NOT guessed between. `brief.json` is the composed brief; when it is absent
    the other brief-shaped artifacts present are NAMED so the owner picks one,
    which is a stated ambiguity rather than a silent pick.

    Returns `(path, why)`. `path` is None when nothing resolves, and `why` then
    says so plainly — this never falls through to starting Step 0 and never
    composes anything.
    """
    # THE RESOLVER OWNS THE LAYOUT (D1). No storage path is composed here: the
    # run root is ASKED FOR, exactly as every other caller asks for it, and
    # only the run-id ordering and the artifact name are this function's.
    import subprocess
    cmd = [sys.executable,
           os.path.join(os.path.dirname(os.path.realpath(__file__)),
                        "resolve-paths.py"),
           "terrain-runs-root"] + (["--root", root] if root else [])
    try:
        base = subprocess.run(cmd, capture_output=True, text=True,
                              check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        return None, f"the terrain run root could not be resolved ({exc})"
    if not os.path.isdir(base):
        return None, ("no terrain run workspace exists yet, so there is no "
                      "brief to open. A brief comes from a terrain sitting: "
                      "say `show the terrain` to start one.")
    runs = sorted(r for r in os.listdir(base)
                  if not os.path.islink(os.path.join(base, r))
                  and os.path.isdir(os.path.join(base, r)))
    if not runs:
        return None, ("no terrain run workspace exists yet, so there is no "
                      "brief to open. Say `show the terrain` to start one.")
    ws = os.path.join(base, runs[-1])
    path = os.path.join(ws, BRIEF_FILENAME)
    if os.path.isfile(path):
        return path, (f"the newest terrain run workspace ({runs[-1]}) and its "
                      f"{BRIEF_FILENAME}")
    others = sorted(f for f in os.listdir(ws)
                    if f.startswith("brief") and f.endswith(".json"))
    if others:
        return None, (
            f"the newest terrain run workspace ({runs[-1]}) holds no "
            f"{BRIEF_FILENAME}, but it does hold "
            f"{', '.join(others)}. Those are recompositions from the "
            "edit-set loop and are not guessed between — name the one you "
            "want.")
    return None, (f"the newest terrain run workspace ({runs[-1]}) holds no "
                  "brief artifact, so there is nothing to open. A brief is "
                  "written when a selection is composed with `--out`.")


def post_adoption_blocks(members, pin, claim, answer, incorporation_block,
                         structures_block, register_block, fit):
    """The three post-adoption brief gates, in sequence, as one emission:
    journey incorporation (#1045), structure (#1410), plain register (#1411).

    ONE LOOP RATHER THAN THREE COPIES, because the third copy is where they
    start to drift — the shape is identical by design (each module builds its
    own block and returns None where its gate is not raised) and the
    recorded block is the #1079 provenance in every case: an adoption with no
    record of what it was adopted from keeps the answer while losing the
    question. `fit` is the caller's line-fitter, passed rather than imported
    so this module keeps no opinion about rendering width.
    """
    from terrain_journey import journey_incorporation_block
    from terrain_register import (REGISTER_OPTION_LABEL, _register_line,
                                  plain_register_block)
    from terrain_structure import (STRUCTURE_OPTION_LABEL, _structure_line,
                                   structure_candidates_block)
    from terrain_text import (JOURNEY_INCORPORATION_OPTION_LABEL,
                              _journey_incorporation_line)
    out = {}
    for key, block, label, line, recorded in (
        ("journey_incorporation",
         journey_incorporation_block(
             members, pin, claim,
             adopted=answer.get("journey_incorporation")),
         JOURNEY_INCORPORATION_OPTION_LABEL,
         lambda b: _journey_incorporation_line(len(b["with_journey"]),
                                               len(members)),
         incorporation_block),
        ("structure_candidates",
         structure_candidates_block(
             members, pin, claim, adopted=answer.get("structure"),
             adopted_register=answer.get("journey_incorporation")),
         STRUCTURE_OPTION_LABEL,
         lambda b: _structure_line(len(members), len(b["with_journey"])),
         structures_block),
        ("plain_register",
         plain_register_block(members, pin, claim,
                              adopted=answer.get("plain_register")),
         REGISTER_OPTION_LABEL,
         lambda b: _register_line(len(members)),
         register_block),
    ):
        if block:
            out[key] = {"label": label, "line": fit(line(block)),
                        **block, **(recorded or {})}
    return out
