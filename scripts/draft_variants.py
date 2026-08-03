#!/usr/bin/env python3
"""draft_variants — the variants and quality-gate command family (Story 20.47,
#921).

Extracted from `draft-pipeline.py` per the packaging invariant's scripts-family
clause (`specs/spec-writing-assistant/SPEC.md`, amended 2026-07-29, #914): the
dominant CLI/commands class takes the dispatcher-plus-per-command-module split,
by COMMAND FAMILY. The review family went first (Story 20.45), the
policy-classification family second (20.46); this is the third.

**The CLI surface is the invariant.** `skills/draft-article/` and
`skills/emit-variants/` invoke these commands by name, so a changed command
name, flag or exit code is a breaking change wearing a refactor's clothes.
Nothing here alters the surface: the same two commands, the same arguments,
the same returns.

**Why the helpers stay in the host.** Several of this family's helpers are
reached from OUTSIDE the family: checks exec `draft-pipeline.py` and call
`_load_internal_vocabulary`, `_undeclared_basename_findings` and
`_delivered_slug_findings` as module attributes, and
`check-emission-review-evidence.sh` asserts `_review_evidence` /
`_REVIEW_RECORD_SEP` exist in the host SOURCE. Moving them would silently
change what those checks verify, so only the two command bodies move and every
borrowed name reads as `_host.<name>` at its use site — the same explicitness
rule as `draft_review.py`, applied for an additional reason.
"""

import argparse
import hashlib
import importlib.util
import json
import os
import re
import sys  # noqa: F401  (kept: extracted code may reach for it)

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import run_record  # noqa: E402  (the gate's record is a side effect of running)
import run_loop  # noqa: E402  (the revision cycle is a bounded improvement loop)

# The host (`draft-pipeline.py`), bound once at import by the dispatcher. Never
# imported here: the host owns these helpers, and a second import path to them
# would be the drift this extraction exists to remove. The binding is over the
# host's GLOBALS, resolved LAZILY — same rationale as draft_review.py.
_host = None


class _Host:
    """Attribute access over the host's globals, resolved at call time."""

    def __init__(self, namespace):
        self._ns = namespace

    def __getattr__(self, name):
        try:
            return self._ns[name]
        except KeyError:
            raise AttributeError(
                f"{name!r} is not defined in the host module — the variants/"
                f"quality-gate family borrows it, so it must stay in "
                f"draft-pipeline.py or move here with the family") from None


def bind(namespace):
    """Bind the host's globals; call as `draft_variants.bind(globals())`."""
    global _host
    _host = _Host(namespace)


def _evidence_cannot_determine_line(entry):
    """The AC-1 disclosure line for one unresolvable evidence-type predicate
    (Story 20.173, #1288). Names the section, the declared type, and WHY the
    predicate could not be resolved — a bare `cannot-determine` would reproduce
    the silence it replaces one level up."""
    sec = (f"section '{entry['section']}'" if entry.get("section")
           else "section not determined (declarations unread)")
    dec = ("declared " + "|".join(entry["declared"]) if entry.get("declared")
           else "declared type not determined")
    return (f"evidence-type check: cannot-determine — {sec}, {dec}: "
            f"{entry['reason']}")


# The evidence types this check has a SHIPPED predicate for, post-harvest
# (Story 20.174, #1288; SPEC-article-draft-pipeline per-section-minimum-
# evidence-type clause (a), amended 2026-08-02).
#
# `episode` maps onto the time-axis admissibility predicate `verify-provenance`
# already enforces per claim (`scripts/verify-provenance.py:405-435`), whose
# pointer-form→source-type table is owned by `resolve-writing-sources.py`.
# `none` never reaches here (`parse_evidence_declarations` drops it).
#
# `example` and `measurement` are DELIBERATELY ABSENT and must stay absent
# until the record gains a kind field. A pin-ledger line is a BARE POINTER with
# no kind (`scripts/examine.py:629-632` writes `evidence[].cite` and nothing
# else), while `EVIDENCE_KINDS` resolves those two out of `quote`/`result`/
# `number`; the examination record's own vocabulary is `source_type`
# (`commit|issue|prose`) plus `time_axis`, an ORTHOGONAL axis rather than a
# renaming of the four KINDs. Inventing a substitute predicate would put a
# fabricated judgment under a publish blocker — a worse failure than the silent
# skip #1288 exists to fix — so they resolve to 20.173's cannot-determine
# state, which is the correct output here and not a stopgap.
EVIDENCE_TYPE_PREDICATES = {"episode"}


def _load_rws():
    """The declared-source TYPE authority (`resolve-writing-sources.py`) — the
    same module `verify-provenance` loads for the same reason: ONE copy of the
    pointer-form→source-type→time-axis table in the repository. Loaded lazily,
    so a gate run over a framework declaring no evidence types pays nothing."""
    here = os.path.dirname(os.path.realpath(__file__))
    spec = importlib.util.spec_from_file_location(
        "rws", os.path.join(here, "resolve-writing-sources.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _read_pin_ledger(path):
    """The run's declared pointer set, read from `$WS/examination-pins.txt` —
    the SAME file stage 3 hands `verify-provenance` as `--fact-sheet`
    (`skills/draft-article/stages/stage3.md`; the flag name predates #1182 and
    was retained on purpose). Same one-pointer-per-line, `#`-comment grammar
    `verify-provenance._load_set` reads, because it is the same file. This
    creates NO store and appends nothing: the ledger stays DERIVED from the
    examination records in claim order (`scripts/examine.py:607-635`)."""
    with open(path, encoding="utf-8") as fh:
        return {ln.strip() for ln in fh
                if ln.strip() and not ln.strip().startswith("#")}


def cmd_quality_gate(args):
    """Stage 3→4 quality gate (Story 11.4). Dimensions 3 and 4 are mechanical
    here; dimensions 1–2 come from the single-pass judge's verdicts (--judge, a
    file of `dim1|dim2: pass|fail [locations]`, one verdict per line). A judge
    file that does not parse under that grammar is a distinct named error (exit
    2) — never a per-dimension fail: a gate that cannot read its judge has not
    judged (#303).

    Dimension 3 is a deterministic vocabulary scan against the rubric's written
    introduction contract (#305), emitting the COMPLETE violation set in one
    verdict; audience-known terms are excluded via --audience-known (the per-run
    allowlist derived once from the owner-ratified audience answer). A `dim3:`
    line from the judge is accepted but ADVISORY — it never gates, because an
    unpinned judgment reported one item per pass cannot converge inside the D5
    bound of 2 cycles.

    Emits a per-dimension verdict; a non-zero exit BLOCKS stage 4 (a
    precondition, not an advisory finding).
    """
    # The shared two-cycle bound is ENFORCED here, not only documented (#738):
    # rewrites, gate revisions, and repair hops all count against TWO_CYCLE_BOUND,
    # and a third revision cycle is mechanically unreachable — past the bound the
    # unresolved dimensions are a CAP-6 publish blocker, never another round.
    if getattr(args, "cycle", 1) > _host.TWO_CYCLE_BOUND:
        print(json.dumps({
            "gate": "quality",
            "pass": False,
            "action": "publish-blocker",
            "publishable": False,
            "reason": (f"two-cycle bound exhausted: cycle {args.cycle} requested, "
                       f"bound is {_host.TWO_CYCLE_BOUND} (rewrites, gate revisions, and "
                       "repair hops share it) — the unresolved dimensions route to "
                       "the completion summary's publish-blocker bucket, never a "
                       "third revision cycle"),
        }, indent=2))
        run_record.note(outcome="blocked", route="two-cycle bound exhausted",
                        detail="cycle %s past the bound: publish-blocker, never a "
                               "third cycle" % args.cycle)
        return 1
    draft = sys.stdin.read() if args.draft == "-" else open(args.draft, encoding="utf-8").read()
    # The revision cycle is a bounded improvement loop — a repeated act that
    # regenerates an artifact against a verdict — so the draft this cycle grades
    # is PRESERVED under its own hash in the run workspace before it is graded,
    # and this iteration's delta against the previous cycle's preserved draft
    # rides the gate block's own close record (story 20.189, #1334;
    # record-formats.md §5). The cycle still OVERWRITES the working draft; what
    # changes is that the superseded version stays addressable. The gate is the
    # FIRST consumer of the contract, never its definition: nothing in
    # `run_loop` knows what a quality gate is.
    run_loop.record_iteration(run_record.workspace_of(args)[0], "quality-gate",
                              getattr(args, "cycle", 1), draft)
    prov_entries = []
    if args.map:
        try:
            prov_entries = _host.parse_provenance_map(_host._read_text(args.map))
        except ValueError as e:
            sys.stderr.write(f"error: provenance map: {e}\n")
            return 2

    results = {}
    # Dimensions 1–2: judge verdicts. When a judge file is supplied it must
    # parse under the stated grammar — `dimN: pass|fail [locations]`, one line
    # per dimension, dim1 and dim2 each present. Anything else (e.g. the
    # natural-language form `dimension 1: pass`) is a format mismatch, which is
    # indistinguishable from a genuine rubric failure if graded — so it exits
    # 2 with a named error before any dimension is judged (#303). A `dim3:`
    # line is accepted and kept as an ADVISORY note (#305): dim3 is scanned
    # mechanically below and the judge's opinion of it never gates.
    judged = {}
    if args.judge:
        # dim1/dim2 are judged; a dim3 line is advisory and a dim4 line is
        # tolerated-and-ignored (both are scanned mechanically) so the gate's own
        # complete verdict record (Story 18.18) is safe if it is fed back here.
        bad, verdict_re = [], re.compile(r"^(dim[1234])\s*:\s*(pass|fail)\b(.*)$", re.IGNORECASE)
        for lineno, ln in enumerate(_host._read_text(args.judge).splitlines(), 1):
            ln = ln.strip()
            if not ln or ln.startswith("#"):
                continue
            m = verdict_re.match(ln)
            if not m:
                bad.append((lineno, ln))
                continue
            judged[m.group(1).lower()] = (m.group(2).lower(), m.group(3).strip(" :-"))
        missing = [d for d in ("dim1", "dim2") if d not in judged]
        if bad or missing:
            sys.stderr.write("error: judge verdicts unparseable — expected "
                             "`dimN: pass|fail [locations]` per line, dim1 and dim2 each "
                             "present (dim3 is scanned mechanically; a dim3 line is advisory)\n")
            for lineno, ln in bad:
                sys.stderr.write(f"  line {lineno}: {ln}\n")
            if missing:
                sys.stderr.write(f"  missing verdicts: {', '.join(missing)}\n")
            return 2
    if getattr(args, "profile", "full") == "slim":
        # Working-note lighter gate (Story 13.89 / #412; SPEC-article-frameworks
        # working-note ratification: "a lighter quality gate"): the interpretive
        # dim1-2 rubric judge is waived by profile — the mechanical dimensions
        # (3-4) and the audience precondition still run in full below.
        if args.judge:
            sys.stderr.write(
                "error: --profile slim waives the dim1-2 rubric judge (the "
                "working-note lighter gate) — do not pass --judge\n")
            return 2
        for dim in ("dim1", "dim2"):
            results[dim] = ("waived",
                            "slim profile (working-note): mechanical dimensions only")
    else:
        for dim in ("dim1", "dim2"):
            verdict, locations = judged.get(dim, ("fail", "no judge verdict"))
            results[dim] = (verdict, "" if verdict == "pass" else locations)

    # Second-cycle DELTA re-check (#349, Story 13.65). On cycle 2, the dim1–2
    # LLM judge is scoped to VERIFY that cycle-1's failing locations were
    # addressed — it may NOT introduce a NEW interpretive dim1–2 finding. A
    # cycle-2 dim1/dim2 `fail` whose locations do not overlap cycle-1's failing
    # locations is interpretive drift (the observed oscillation), suppressed to
    # `pass` so revision converges. Mechanical dims (3/4) and audience re-run in
    # full below and CAN raise new findings. Isolation (NFR13) is preserved by
    # the orchestrator: it hands the judge cycle-1's LOCATIONS as scope, never
    # prior verdicts — this command only enforces the delta arithmetic.
    delta_suppressed = []
    if getattr(args, "cycle", 1) >= 2:  # the second/delta cycle (the two-cycle bound)
        prior = _host._loc_set(getattr(args, "prior_locations", None))
        if prior:
            for dim in ("dim1", "dim2"):
                v, loc = results[dim]
                if v != "fail":
                    continue
                this_locs = _host._loc_set(loc)
                if this_locs and not (this_locs & prior):
                    # a fresh interpretive finding at a location cycle 1 never
                    # flagged — not actionable on the delta re-check
                    results[dim] = ("pass", "")
                    delta_suppressed.append({"dimension": dim, "locations": loc})

    # Dimension 3: mechanical, exhaustive, deterministic (#305).
    known = []
    for a in (getattr(args, "audience_known", None) or []):
        known.extend(t.strip() for t in a.split(",") if t.strip())
    d3 = _host._dimension3(draft, known)
    results["dim3"] = ("pass", "") if not d3 else (
        "fail", "; ".join(f"{t} (line {n})" for t, n in d3))
    # Which inventory produced that verdict is part of the verdict: a dim3 pass
    # means "nothing in the registered inventory was uncalibrated", never
    # "nothing was uncalibrated". Stamping it keeps the scope of the claim
    # visible to whoever reads the gate output (#305).
    try:
        with open(_host.VOCAB_ASSET, encoding="utf-8") as fh:
            _v = json.load(fh)
        vocab_stamp = {"vocabulary_version": _v.get("vocabulary_version"),
                       "registered_terms": len(_v.get("terms", [])),
                       "registered_patterns": len(_v.get("patterns", []))}
    except (OSError, json.JSONDecodeError):
        vocab_stamp = None

    # Dimension 4: mechanical. The measured mechanics behind the verdict are
    # kept beside it (Story 18.18) so the verdict RECORD can stamp dim4 with
    # what was measured, symmetrically with dim3's inventory stamp.
    d4 = _host._dimension4(draft, prov_entries)
    results["dim4"] = ("pass", "") if not d4 else ("fail", "; ".join(d4))
    dim4_measures = _host._dimension4_measures(draft, prov_entries)

    # Audience presence — a stage-progression precondition (Story 13.41,
    # SPEC-platform-variants CAP-4). `audience` is born at stage-3 fill, so this
    # gate is where presence is enforceable on a fresh run; the variant stage's
    # hard stop remains as backstop. Mechanical: frontmatter parse only.
    try:
        fields, _ = _host._read_frontmatter(draft)
    except SystemExit:
        fields = {}
    aud = fields.get("audience")
    aud_id = fields.get("audience_id")
    if not aud or aud == "{audience}":
        results["audience"] = ("fail",
                               "frontmatter `audience` missing or unfilled — set the named "
                               "reader at stage-3 fill (from the interview's audience answer, "
                               "the backlog item, or the draft-start declaration)")
    elif not aud_id or aud_id == "{audience_id}":
        # Story 13.71 (#363): the machine-readable compatibility identifier is
        # declared at draft time alongside the named reader — never inferred
        # downstream, so its absence is a gate failure exactly like audience's.
        results["audience"] = ("fail",
                               "frontmatter `audience_id` missing or unfilled — declare the "
                               "audience compatibility identifier (from the installed "
                               "profiles' audience vocabulary) with the audience answer at "
                               "stage-3 fill")
    else:
        results["audience"] = ("pass", "")

    # Per-section minimum evidence type (Story 13.90, #416) — a stage-
    # progression precondition beside the rubric dimensions. Runs whenever the
    # framework file is supplied and declares types; fails CLOSED when the
    # inputs it needs are missing, because a gate that cannot check has not
    # checked.
    #
    # THREE outcomes, not two (Story 20.173, #1288; SPEC-writing-assistant
    # clause (b) — "a failed corpus precondition reports DISTINCTLY … neither a
    # pass nor a failure. A vacuous pass is the #933 failure mode exactly"). A
    # predicate this check cannot RESOLVE is `cannot-determine`: disclosed by
    # name with its reason, never a pass, never a missing-input finding, and
    # never a publish blocker on its own. The two fail-closed refusals below
    # (exit 2) stay BESIDE this state, not folded into it: a missing FLAG is an
    # invocation defect an agent fixes by re-invoking, while an unresolvable
    # predicate over inputs that WERE supplied is a corpus precondition.
    evidence_missing = []
    evidence_cannot_determine = []
    evidence_checked = False
    if not getattr(args, "framework_file", None):
        # The #1288 defect route itself: the strict path refused, so the gate
        # was invoked WITHOUT --framework-file/--state — which omitted the
        # check entirely and reported nothing about the omission. Dropping the
        # flags can no longer route around the check silently; the omission is
        # now the state (AC-2).
        evidence_cannot_determine.append({
            "section": None,
            "declared": None,
            "reason": ("--framework-file was not passed, so this run never read "
                       "the framework's per-section [EVIDENCE: …] declarations "
                       "— no declared minimum evidence type was resolved for "
                       "any section, and the check did not run. Re-invoke with "
                       "--framework-file and --pin-ledger (the documented gate "
                       "invocation, skills/draft-article/stages/gate.md)"),
        })
    if getattr(args, "framework_file", None):
        try:
            decls = _host.parse_evidence_declarations(_host._read_text(args.framework_file))
        except ValueError as e:
            sys.stderr.write(f"error: evidence-type declarations: {e}\n")
            return 2
        except OSError as e:
            sys.stderr.write(f"error: cannot read --framework-file: {e}\n")
            return 2
        if decls:
            # THE RE-ANCHOR (Story 20.174, #1288). The carrier is the
            # examination pin ledger read beside the provenance map — NOT
            # `state["fact_sheet"]`, whose producer was retired with harvest
            # (#1182/#1224), which is what converted a fail-closed check into a
            # silent skip. `--state` is still accepted (the CLI surface is the
            # invariant) and is no longer consulted by THIS check.
            if not args.map or not getattr(args, "pin_ledger", None):
                sys.stderr.write(
                    "error: the framework declares per-section minimum evidence "
                    "types, so the gate needs --map (anchored provenance map) "
                    "and --pin-ledger (the run's examination pin ledger, "
                    "$WS/examination-pins.txt — the same file stage 3 hands "
                    "verify-provenance as --fact-sheet) — the check fails "
                    "closed rather than silently skipping. NOTE: --state no "
                    "longer carries this check's evidence; passing it instead "
                    "of --pin-ledger will not satisfy this refusal "
                    "(SPEC-article-draft-pipeline, evidence-type constraint as "
                    "amended 2026-08-02, #1288)\n")
                return 2
            # An UNREADABLE ledger is an invocation defect (a wrong path), so it
            # refuses like a missing flag. An EMPTY one is a corpus precondition
            # and falls through to cannot-determine below — the Story 19.14
            # (#751) distinction, re-pointed: "computed over nothing" must stay
            # mechanically distinguishable from "computed and found nothing",
            # and post-#1288 the honest name for the first is the third state,
            # not a refusal that an agent then routes around by dropping flags.
            try:
                ledger = _read_pin_ledger(args.pin_ledger)
            except OSError as e:
                sys.stderr.write(
                    f"error: cannot read --pin-ledger: {e} — the evidence-type "
                    "check refuses rather than reporting a false evidence gap. "
                    "Pass the run's derived ledger ($WS/examination-pins.txt); "
                    "derive it with `examine.py derive-ledger` if the run's "
                    "examinations have not been joined yet (Story 20.174, "
                    "#1288)\n")
                return 2
            rws = _load_rws()
            lines = draft.splitlines()
            heads = [(i + 1, ln) for i, ln in enumerate(lines) if ln.startswith("##")]
            sections = []
            for idx, (lineno, ln) in enumerate(heads):
                end = heads[idx + 1][0] - 1 if idx + 1 < len(heads) else len(lines)
                sections.append((_host._slot_key(ln), lineno, end))
            evidence_checked = True
            for slot, types in decls:
                sec = next((s for s in sections if s[0] == slot), None)
                decidable = sorted(set(types) & EVIDENCE_TYPE_PREDICATES)
                undecidable = sorted(set(types) - EVIDENCE_TYPE_PREDICATES)
                # The section's EVIDENCE-BEARING positions, from the map's
                # per-section sourced/derived distribution (AC-1). `narration`
                # and `verify` are excluded on the shipped predicate's own
                # polarity: `_episode_findings` refuses an episode claim typed
                # either, because neither carries a pin.
                dist = {c: 0 for c in ("sourced", "derived", "narration", "verify")}
                carried, absent, time_axis = [], [], []
                if sec:
                    for _pos, _cls, ptrs, anchor in prov_entries:
                        if not (anchor and sec[1] <= anchor <= sec[2]):
                            continue
                        dist[_cls] = dist.get(_cls, 0) + 1
                        if _cls not in ("sourced", "derived"):
                            continue
                        for ptr in ptrs:
                            if ptr in ledger:
                                carried.append(ptr)
                                if rws.pointer_time_axis(ptr):
                                    time_axis.append(ptr)
                            else:
                                absent.append(ptr)
                common = {"section": slot, "section_present": bool(sec),
                          "declared": sorted(types), "class_distribution": dist,
                          "carrier": "examination-pins"}
                # (1) NO SHIPPED PREDICATE for any declared type (AC-4). A
                # pin-ledger line is a bare pointer; `example` and `measurement`
                # are resolved out of quote/result/number, which nothing
                # post-harvest records. Reporting the section unsatisfied would
                # assert an absence the check never established, and inventing a
                # substitute would put a fabricated judgment under a publish
                # blocker.
                # `sec and` guards it so that a section the join never LOCATED
                # still reports #750's section-not-found: a renamed heading is a
                # draft-shape defect knowable without any evidence predicate,
                # and reporting it as cannot-determine would hide a repair the
                # check CAN name.
                if sec and not decidable:
                    evidence_cannot_determine.append(dict(
                        common,
                        reason=("declared evidence type(s) " + ", ".join(undecidable)
                                + " have no established predicate over the "
                                  "examination pin ledger — a ledger line is a "
                                  "bare pointer with no kind field, and the "
                                  "examination record's `source_type`/`time_axis` "
                                  "vocabulary is orthogonal to the quote/result/"
                                  "number KINDs these types resolve out of. This "
                                  "section's evidence was established neither "
                                  "present nor absent; the mapping is an open "
                                  "question (#1288), never guessed here"),
                    ))
                    continue
                if sec and time_axis:
                    # (2) SATISFIED. `episode` passes iff at least one anchored
                    # pointer resolves to a TIME-AXIS source — the same
                    # predicate `verify-provenance` enforces per claim (#1184
                    # clause (iii)), REUSED from the same table, never
                    # re-implemented. The declaration is a disjunction, so one
                    # decidable type satisfying it settles the section.
                    pass
                elif sec and absent:
                    # (3) Carrier absent FOR THIS SECTION (Story 20.173, shape
                    # preserved): the section anchors pointers the ledger does
                    # not carry — an interview answer id, or a pin from a run
                    # whose examinations were never joined — so "no time-axis
                    # source found" cannot be told apart from "the carrier does
                    # not carry these pointers". The #751 false-gap shape at
                    # per-section granularity.
                    evidence_cannot_determine.append(dict(
                        common,
                        unresolved_pointers=sorted(set(absent)),
                        reason=("carrier absent — " + str(len(set(absent)))
                                + " anchored pointer(s) in this section are not "
                                  "in the supplied --pin-ledger "
                                  "($WS/examination-pins.txt), so the declared "
                                  "type was neither found nor established "
                                  "missing"),
                    ))
                    continue
                elif sec and undecidable:
                    # (4) The decidable half is REFUTED but the declaration is a
                    # disjunction whose remaining members have no predicate — so
                    # the section as a whole is undecided, not failing.
                    evidence_cannot_determine.append(dict(
                        common,
                        decided=decidable, undecided=undecidable,
                        reason=("no anchored pointer resolves to a time-axis "
                                "source, so `" + "|".join(decidable) + "` is "
                                "refuted — but the declaration also offers "
                                + ", ".join(undecidable) + ", which has no "
                                "established predicate over the pin ledger. The "
                                "disjunction is undecided, and reporting a "
                                "missing-input finding here would rest on a "
                                "guessed mapping (#1288)"),
                    ))
                    continue
                if not (sec and time_axis):
                    tlist = "|".join(sorted(types))
                    evidence_missing.append({
                        "section": slot,
                        "section_present": bool(sec),
                        "declared": sorted(types),
                        "class_distribution": dist,
                        "carrier": "examination-pins",
                        "carried_pointers": sorted(set(carried)),
                        # #750: a section the join never FOUND is a different
                        # defect class than a found-but-hollow one — the first
                        # is a draft-shape defect (renamed heading), repaired
                        # by a heading fix; only the second is an evidence gap
                        # whose remedy is the `ask` elicitation hop. Reporting
                        # the first as "found nothing" routed a full revision
                        # cycle into re-eliciting evidence that was present all
                        # along (run 20260726T165310).
                        "classification": ("section-not-found" if not sec
                                           else "missing-input"),
                        "upstream": (
                            # A ready-made `Upstream:` remediation in exactly
                            # the shape `repair-hop` consumes — the bounded
                            # route, never open-ended re-harvest.
                            (f"ask Section '{slot}' declares minimum evidence "
                             f"type {tlist} and the draft satisfies none: which "
                             f"concrete {tlist} from the sources should fill it? "
                             "Name its source.") if sec else
                            (f"rename the section heading: no draft section "
                             f"normalizes to the slot key '{slot}' — actual "
                             "headings: "
                             + "; ".join(s[0] for s in sections if s[0])
                             + ". Align the heading with the framework slot "
                               "(a heading fix, never an ask elicitation — "
                               "the evidence may be present under the wrong "
                               "heading, #750)")),
                    })
            # A determinable section still reports its ordinary verdict (a
            # cannot-determine elsewhere never converts a real finding, and
            # never suppresses a real pass). Only when nothing failed AND
            # something was unresolvable does the dimension itself carry the
            # third state — `cannot-determine` is not in `failing`, so it never
            # blocks publication on its own (AC-4), and it is not `pass`, so it
            # is never counted toward one (AC-1).
            if evidence_missing:
                results["evidence"] = ("fail", "; ".join(
                    (f"{m['section']}: section not found (expected slot key "
                     f"'{m['section']}'; heading mismatch — see upstream)")
                    if m["classification"] == "section-not-found" else
                    f"{m['section']}: declared {'|'.join(m['declared'])}, no "
                    f"anchored pointer resolves to a time-axis source "
                    f"({len(m['carried_pointers'])} pointer(s) in the ledger)"
                    for m in evidence_missing))
            elif evidence_cannot_determine:
                results["evidence"] = ("cannot-determine", "; ".join(
                    _evidence_cannot_determine_line(c)
                    for c in evidence_cannot_determine))
            else:
                results["evidence"] = ("pass", "")

    failing = [d for d, (v, _) in results.items() if v == "fail"]
    out = {"gate": "quality", "pass": not failing,
           "dimensions": {d: {"verdict": v, "locations": loc} for d, (v, loc) in results.items()},
           "failing_dimensions": failing}
    if vocab_stamp:
        out["dim3_inventory"] = vocab_stamp
    out["dim4_inventory"] = dim4_measures
    if evidence_checked:
        out["evidence_types"] = {
            "checked": True,
            "missing_input": evidence_missing,
            "note": ("a failing section is a MISSING-INPUT finding — route its "
                     "`upstream` line through `repair-hop` (the bounded repair "
                     "route, same two-cycle bound); never backfill with "
                     "unrelated factual material"),
        }
    # The third outcome, PRINTED (Story 20.173, #1288). It rides in the report
    # itself — the defect was silence, so a state that only a return value
    # carried would repeat it — and is echoed on stderr for the human reading
    # the run. It is deliberately NOT in `missing_input[]`: a cannot-determine
    # is not an evidence gap, and routing one to `episode-candidates` would
    # manufacture the very absence the state exists to avoid asserting (AC-3,
    # the #751 failure the fail-closed refusals were built to prevent).
    if evidence_cannot_determine:
        cd_lines = [_evidence_cannot_determine_line(c)
                    for c in evidence_cannot_determine]
        et = out.setdefault("evidence_types", {"checked": evidence_checked,
                                               "missing_input": []})
        et["cannot_determine"] = evidence_cannot_determine
        et["cannot_determine_lines"] = cd_lines
        et["cannot_determine_note"] = (
            "cannot-determine is neither a pass nor a failure: it is never "
            "counted toward a pass, never enters `missing_input[]`, never "
            "routes to `episode-candidates` or any repair hop, and is never a "
            "publish blocker on its own — disclose it in the completion "
            "summary (SPEC-writing-assistant clause (b); Story 20.173, #1288)")
        out.setdefault("notices", []).extend(cd_lines)
        for ln in cd_lines:
            sys.stderr.write(ln + "\n")
    # Delta re-check accounting (#349): what the second cycle suppressed as a
    # fresh interpretive dim1/dim2 finding (not in cycle-1's locations), so the
    # convergence decision is auditable from the gate output alone.
    if delta_suppressed:
        out["cycle"] = getattr(args, "cycle", 1)
        out["delta_recheck"] = {
            "suppressed_new_interpretive": delta_suppressed,
            "note": ("second cycle is a delta re-check: a dim1/dim2 fail at a "
                     "location cycle 1 never flagged is not actionable (only a "
                     "mechanical dim may raise a new finding); isolation is "
                     "preserved — the judge received cycle-1 locations as scope, "
                     "not prior verdicts"),
        }
    # The judge's dim3 opinion, when it offered one, rides along as an advisory
    # for the completion summary's informational bucket — never a gate verdict
    # (#305). It is recorded, not obeyed.
    if "dim3" in judged:
        verdict, locations = judged["dim3"]
        out["advisories"] = [{"dimension": "dim3", "source": "rubric-judge",
                              "verdict": verdict, "locations": locations,
                              "note": "advisory only — dim3 is gated by the mechanical scan"}]

    # The authoritative Stage 3->4 verdict RECORD (Story 18.18): the gate writes
    # ALL FOUR dimensions — dim3 with its inventory stamp, dim4 with measured
    # values — so the recorded verdicts can never be the dim1/dim2-only partial
    # that let review compensate for an unrun gate (#492). This is the file the
    # completion gate blocks on when partial.
    if getattr(args, "verdicts_out", None):
        record = _host._render_verdict_record(results, vocab_stamp, dim4_measures,
                                        draft_text=draft)
        try:
            with open(args.verdicts_out, "w", encoding="utf-8") as fh:
                fh.write(record)
            out["verdicts_written"] = os.path.abspath(args.verdicts_out)
        except OSError as e:
            sys.stderr.write(f"error: could not write --verdicts-out "
                             f"{args.verdicts_out}: {e}\n")
            return 2

    # The gate block's judgment, in the record's terms (CAP-2/CAP-3). The SKIPS
    # are the sub-obligations this invocation did not discharge — named, so a
    # partial gate can never close as a clean `ran`. The per-section
    # evidence-type check is NOT among them: its repair is #1288's.
    run_record.note(
        outcome="pass" if not failing else "fail",
        route=["profile=%s" % getattr(args, "profile", "full"),
               "cycle=%s" % getattr(args, "cycle", 1)]
              + (["delta re-check suppressed %d interpretive finding(s)"
                  % len(delta_suppressed)] if delta_suppressed else []),
        detail=("all dimensions pass" if not failing
                else "failing: " + ", ".join(failing)),
        skipped=([run_record.skip(
            "dim1-2 rubric judge",
            "profile slim (working-note): the interpretive dimensions are waived "
            "by ratified contract, so this gate judged 3-4 only")]
                 if getattr(args, "profile", "full") == "slim" else [])
                + ([run_record.skip(
                    "provenance-map checks (stitched-fact-sheet, dim4 density)",
                    "no --map supplied, so the map-dependent half of the gate had "
                    "nothing to read")] if not args.map else []))
    print(json.dumps(out, indent=2))
    return 0 if not failing else 1


def cmd_variants(args):
    """Emit platform-ready variants of the PERSISTED canonical draft as
    PROJECTIONS through declared platform profiles (Story 16.3; Story 13.69 —
    a standalone post-review invocation, SPEC-platform-variants CAP-1/CAP-3,
    not a stage of the draft flow). The sanctioned input is the persisted
    canonical at `<output.drafts>/<slug>.md` (loaded via `--slug`, written by
    the draft flow's `complete` gate) — never a run-workspace copy. Which
    platforms come from the config canonical policy; HOW each is packaged comes
    entirely from that platform's profile (Story 16.1) — there is no hardcoded
    per-platform code path. WHICH configured platforms are actually emitted is
    the owner's explicit publish decision (Story 16.4): `--list-platforms` (or no
    choice) reports the options and emits nothing; `--platforms <ids|all>` emits
    exactly that subset — the stage never auto-emits every configured platform.
    Each variant is written to the resolved output.drafts location (or --out),
    carrying the canonical draft's content hash; the profile-resolution log lands
    in the run workspace.
    """
    # Input resolution (Story 13.69): the sanctioned form is `--slug`, which
    # loads the persisted canonical. A positional path is accepted only when it
    # already IS inside the resolved output.drafts (i.e. the persisted
    # canonical), or under the test-only --allow-external-draft escape. A
    # workspace-only canonical is a pointed refusal, never a silent fallback.
    if getattr(args, "slug", None):
        drafts_dir = _host._resolve_drafts_dir(args.root)
        canonical_path = os.path.join(drafts_dir, f"{args.slug}.md")
        if not os.path.isfile(canonical_path):
            sys.stderr.write(
                f"error: no persisted canonical at {canonical_path} — variants "
                "consume the persisted canonical draft (SPEC-platform-variants "
                "CAP-1), never a workspace copy. Finish the draft flow first: "
                "`draft-pipeline.py complete --draft <ws-draft> --slug "
                f"{args.slug}` persists <output.drafts>/{args.slug}.md, then "
                "re-run variants --slug.\n")
            return 1
        text = open(canonical_path, encoding="utf-8").read()
    else:
        text = sys.stdin.read() if args.draft == "-" else open(args.draft, encoding="utf-8").read()
        if not getattr(args, "allow_external_draft", False):
            drafts_dir = os.path.realpath(_host._resolve_drafts_dir(args.root))
            src = None if args.draft == "-" else os.path.realpath(args.draft)
            if src is None or not src.startswith(drafts_dir + os.sep):
                try:
                    slug_hint = _host._read_frontmatter(text)[0].get("slug") or "<slug>"
                except SystemExit:
                    slug_hint = "<slug>"
                expected = os.path.join(drafts_dir, f"{slug_hint}.md")
                sys.stderr.write(
                    f"error: draft {args.draft!r} is not the persisted canonical "
                    f"— variants consume {expected} (SPEC-platform-variants "
                    "CAP-1), never a workspace copy. Run the draft flow's "
                    "completion first (`draft-pipeline.py complete --draft "
                    f"<ws-draft> --slug {slug_hint}`), then invoke `variants "
                    f"--slug {slug_hint}`.\n")
                return 1
    # The persisted canonical carries the emission trailer; project and hash
    # the trailer-stripped content so the recorded canonical_sha256 equals the
    # trailer's own hash and no inherited trailer rides into a variant body.
    text = _host._strip_emission_trailer(text)

    # Precondition: a verified draft carries zero well-formed [VERIFY] markers.
    unresolved = [c for c in _host.VERIFY_CANDIDATE.findall(text) if _host.VERIFY_CANONICAL.match(c)]
    if unresolved:
        sys.stderr.write(f"error: draft still has {len(unresolved)} unresolved [VERIFY] "
                         "marker(s); complete verification before emitting variants\n")
        return 1

    fields, body = _host._read_frontmatter(text)
    lang = fields.get("language")
    if not lang:
        sys.stderr.write("error: draft frontmatter has no `language`; cannot pick a variant policy\n")
        return 1

    # Config drives WHICH platforms + the canonical policy; profiles drive HOW.
    rf = _host._load("render-frontmatter.py")
    cfg_args = argparse.Namespace(config_json=args.config_json, root=args.root,
                                  global_config=args.global_config, repo_config=args.repo_config)
    cfg = rf.load_config(cfg_args)
    owner_variants = cfg.get("syndication", {}).get("variants", {})

    # Working-note lane (Story 18.87, #657; SPEC-platform-variants slim-profile
    # "Routing"): a working-note (F5) selects its newsletter platforms DIRECTLY
    # from the resolvable profiles whose packaging.layout targets the
    # `newsletter/` section — it does NOT consult the language-keyed
    # `syndication.policy` that routes ordinary articles, which has no
    # article-type dimension. Any other framework (or none) keeps the article
    # routing unchanged.
    _fw = getattr(args, "framework", None)
    is_working_note = bool(_fw) and _host.resolve_framework(_fw) in _host.SLIM_PROFILE_FRAMEWORKS
    if is_working_note:
        pp = _host._load("resolve-platform-profiles.py")
        pdir = pp.profiles_dir(pp.host_root(args.root), None)
        nl_profiles, _nl_findings = pp.load_profiles(pdir)
        available = sorted(name for name, prof in nl_profiles.items()
                           if _host._targets_newsletter_section(prof))
        if not available:
            sys.stderr.write(
                "error: no resolvable newsletter platform profile (a profile whose "
                "packaging.layout targets the `newsletter/` section) — seed one, e.g. "
                "`resolve-platform-profiles.py seed newsletter-email` "
                "(SPEC-platform-variants working-note lane)\n")
            return 1
        policy_mode = "newsletter"
    else:
        policy = cfg.get("syndication", {}).get("policy", {}).get(lang)
        if not policy:
            sys.stderr.write(f"error: no syndication.policy for language {lang!r} in config\n")
            return 1
        available = list(policy.get("variants", []))
        policy_mode = policy.get("mode")

    # Emission is per explicit publish decision (Story 16.4, CAP-3): the pipeline
    # NEVER auto-emits all configured platforms. The owner's choice arrives as
    # --platforms (a subset of `available`); `--list-platforms` (or no choice at
    # all) reports the choices for the in-conversation selection and emits
    # nothing. `--platforms all` is an explicit opt-in to every configured one.
    if getattr(args, "list_platforms", False) or not getattr(args, "platforms", None):
        # CROSS-LANGUAGE TARGETS ROUTE THROUGH ADAPTATION (SPEC-platform-variants
        # CAP-3, amended 2026-07-22 per #582). Nothing filtered by language here
        # before, which is how #574 got offered a JA-profile projection of an
        # English canonical as an ordinary choice — an English title, English
        # headings and an English body on a ja-practitioner platform. A platform
        # whose profile language differs from this canonical's is NOT a
        # direct-projection choice: it is presented as "adapt first", naming the
        # route to a derived canonical in that language. What the owner MAY do is
        # unchanged — `--platforms <id>` still emits it, and the language-mismatch
        # publish blocker still reports the outcome — only what is OFFERED moves.
        pp = _host._load("resolve-platform-profiles.py")
        pdir = pp.profiles_dir(pp.host_root(args.root), None)
        profiles, _findings = pp.load_profiles(pdir)
        direct, adapt_first = [], []
        for name in available:
            prof_lang = (profiles.get(name) or {}).get("language")
            if prof_lang and prof_lang != lang:
                adapt_first.append({
                    "platform": name, "profile_language": prof_lang,
                    "canonical_language": lang,
                    "route": f"adapt canonical {fields.get('slug')} for {name}",
                    # Within the proposal contract's 140-char effect budget, so
                    # a screen composed from this entry is presentable as-is.
                    # The owner's register, not the pipeline's (#790): no
                    # `canonical`, `projection` or `retarget` — an owner reads
                    # this at the moment of choosing and has nowhere to look
                    # those up. check-cross-language-offer.sh asserts the
                    # PROPERTIES of this string, deliberately not its wording.
                    "effect": (f"creates a separate {prof_lang} article from this one; "
                               f"{name} publishes that instead. "
                               "Nothing is emitted until you approve its plan.")})
            else:
                direct.append(name)
        out = {"stage": "variants", "language": lang, "mode": policy_mode,
               "available": available, "direct": direct,
               "emitted": [], "written": False,
               "note": "choose platforms to emit with --platforms <ids|all>; "
                       "nothing is auto-emitted"}
        if adapt_first:
            out["adapt_first"] = adapt_first
            out["note"] += ("; a cross-language target is not a direct-projection "
                            "choice — it is offered as `adapt first`")
        print(json.dumps(out, indent=2, ensure_ascii=False))
        return 0
    requested = [p.strip() for p in args.platforms.split(",") if p.strip()]
    chosen = available if requested == ["all"] else requested
    unknown = [p for p in chosen if p not in available]
    if unknown:
        sys.stderr.write(
            f"error: {', '.join(unknown)} not configured for language {lang!r} "
            f"(available: {', '.join(available) or 'none'})\n")
        return 1

    # The canonical draft must declare its named reader (Story 16.5): the
    # lede-retarget trigger is a deterministic comparison of the draft's declared
    # `audience`/`language` against each profile's, so a missing/unfilled
    # `audience` is a hard stop here (presence enforced before any variant).
    draft_audience = fields.get("audience")
    if not draft_audience or draft_audience == "{audience}":
        sys.stderr.write(
            "error: draft frontmatter has no resolved `audience`; the "
            "pipeline-internal audience field (the named reader) must be filled "
            "before variants — set it at draft time.\n")
        return 1
    # Story 13.71 (#363): the trigger compares the STABLE machine-readable
    # `audience_id` (declared at draft time from the installed profiles'
    # audience vocabulary), never the free-text named reader — free-text vs
    # profile slug can never be equal, which made the no-touchpoint branch
    # unreachable. audience_id is never re-inferred here: absent means a
    # presence-validation failure, not a guess.
    draft_audience_id = fields.get("audience_id")
    if not draft_audience_id or draft_audience_id == "{audience_id}":
        sys.stderr.write(
            "error: draft frontmatter has no resolved `audience_id`; the "
            "pipeline-internal audience compatibility identifier (chosen from "
            "the installed profiles' audience vocabulary) must be declared at "
            "draft time — it is never inferred at emission.\n")
        return 1

    # The canonical draft's content hash is recorded with every emitted variant
    # (embedded + reported) so stale-variant detection (Story 16.7) can tell when
    # a variant's source draft has moved since emission.
    canonical_sha = hashlib.sha256(text.encode("utf-8")).hexdigest()

    # Resolve platform profiles — the single declaration source (no builder table).
    pp = _host._load("resolve-platform-profiles.py")
    prof_root = pp.host_root(args.root)
    pdir = pp.profiles_dir(prof_root, None)
    profiles, prof_findings = pp.load_profiles(pdir)

    # Profile-resolution log is an intermediate → the run workspace, never a
    # product (footprint invariant, NFR17). Only the variant files land at
    # output.drafts below.
    if getattr(args, "ws", None):
        try:
            with open(os.path.join(args.ws, "platform-profiles.resolution.json"),
                      "w", encoding="utf-8") as fh:
                json.dump({"profiles_dir": pdir, "resolved": sorted(profiles),
                           "findings": prof_findings}, fh, indent=2)
        except OSError as exc:  # pragma: no cover - defensive
            sys.stderr.write(f"warning: could not write profile-resolution log: {exc}\n")

    slug = fields.get("slug") or "draft"
    out_dir = args.out if args.out else _host._resolve_drafts_dir(args.root)

    # A config-resolved output.drafts OUTSIDE the host repo (the recommended
    # home — a private articles repo, #213) is never silently scaffolded:
    # creating directory trees outside the host needs explicit consent
    # (--create-out, given after the skill asks the owner). Inside the host,
    # creation stays automatic — and an explicit --out IS the consent.
    if not args.dry_run and not args.out and not os.path.isdir(out_dir):
        host = os.path.realpath(args.root) if args.root else _host._git_toplevel()
        inside_host = host and os.path.realpath(out_dir).startswith(host + os.sep)
        if not inside_host and not args.create_out:
            sys.stderr.write(
                f"error: output.drafts resolves outside the host repo to {out_dir}, "
                "which does not exist. Create it yourself, or re-run with "
                "--create-out after confirming the location with the owner.\n")
            return 1

    emitted = []
    blockers = []
    delivered_blockers = []           # illegal delivered basenames (#715)
    lede_proposals = []
    for name in chosen:
        profile = profiles.get(name)
        if not profile:
            sys.stderr.write(
                f"error: no platform profile for configured variant {name!r}. "
                f"Add `{name}.yaml` under {pdir} "
                "(see config/platform-profiles/*.example.yaml).\n")
            return 1
        # Lede-retarget trigger (Story 16.5; amended Story 13.71/#363): a
        # DETERMINISTIC comparison of the declared `audience_id`/`language`/
        # `register` — draft vs profile. Inequality on any calls for exactly
        # one judgment step (re-targeting the lede/framing to the profile's
        # named reader; です/ます for `ja`), presented to the owner as a
        # proposal — the variant's only owner touchpoint. Equality on all
        # three means pure packaging, no proposal. The trigger is never agent
        # judgment over content, and there is no `lede_retarget` profile
        # override field. Register defaults from language when undeclared
        # (`ja` implies です/ます), on both sides identically.
        def _register(explicit, language):
            return explicit or ("です/ます" if language == "ja" else None)
        draft_register = _register(fields.get("register"), lang)
        profile_register = _register(profile.get("register"), profile.get("language"))
        retarget = (draft_audience_id != profile.get("audience")
                    or lang != profile.get("language")
                    or draft_register != profile_register)
        content, blocked = _host._project_variant(fields, body, profile,
                                            owner_variants.get(name, {}))
        # Emission metadata: the canonical draft's hash rides with the variant
        # (an unobtrusive trailing comment both platforms ignore) so Story 16.7
        # can detect a variant whose source draft has since changed.
        content = content.rstrip("\n") + \
            f"\n\n<!-- writing-assistant: canonical-sha256={canonical_sha} -->\n"
        # Placement routes through the profile's declared projection dir
        # (SPEC-platform-variants placement amendment, #688): a variant lands in
        # `packaging.layout.dir` at the output.drafts DESTINATION REPO ROOT — a
        # sibling of the drafts dir per the hub-ratified layout, not co-located
        # beside the canonical in the drafts root — or falls back to the drafts
        # root (out_dir) when the profile declares no layout. The projection dir
        # is created if missing, inside the same destination repo whose out_dir
        # the --create-out consent above already governs.
        subdir = _host._variant_layout_subdir(profile)
        emit_dir = os.path.join(_host._dest_repo_root(out_dir), subdir) if subdir else out_dir
        # The delivered basename comes from the profile's declared mapping
        # (#715); with none declared this is `<slug>.<platform>` as before.
        try:
            stem = _host._delivered_stem(slug, name, profile)
        except ValueError as e:
            sys.stderr.write(f"error: {e}\n")
            return 1
        delivered_blockers.extend(_host._undeclared_basename_findings(stem, name, profile))
        delivered_blockers.extend(_host._delivered_slug_findings(stem, name, profile))
        path = os.path.join(emit_dir, f"{stem}.md")
        if not args.dry_run:
            os.makedirs(emit_dir, exist_ok=True)
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(content)
        entry = {"platform": name, "path": path, "canonical_sha256": canonical_sha,
                 "lede_retarget": retarget}
        emitted.append(entry)
        if blocked:
            blockers.append({"platform": name, "blocker": "unrendered-mermaid"})
        if retarget:
            # One proposal per cross-audience variant — the SKILL performs the
            # actual re-targeting (a judgment step) and presents it under the
            # owner-facing proposal contract. The script only fires the trigger.
            lede_proposals.append({
                "platform": name, "path": path,
                "draft_audience": draft_audience,
                "draft_audience_id": draft_audience_id,
                "draft_language": lang,
                "draft_register": draft_register,
                "profile_audience": profile.get("audience"),
                "profile_language": profile.get("language"),
                "register": profile_register,
            })

    out = {
        "stage": "variants",
        "next_stage": "review",           # draft exits into SPEC-article-review
        "language": lang,
        "mode": policy_mode,
        "available": available,
        "chosen": chosen,                 # the owner's explicit publish decision
        "emitted": emitted,
        "written": not args.dry_run,
    }
    if blockers:
        out["render_blockers"] = blockers
    # The `reviewed` half of "persisted, reviewed canonical" (#716). Both this
    # spec (CAP-3) and SPEC-article-draft-pipeline promise a *reviewed*
    # canonical; only *persisted* was ever checked, so the promise carried no
    # mechanism (#534). It is asserted here as a DISCLOSURE and never a
    # refusal — the owner may legitimately emit ahead of review, and "a
    # promotion threshold gates what surfaces by default, not what the human
    # may act on" (`consulted: product-lab@<private-pin>
    # LESSONS.md:68`).
    #
    # DELIBERATELY NOT READ: the review re-entry's `review_evidence_class`
    # (#704). It is written to `<ws>/checkpoint.json` via `_checkpoint_path`,
    # the RUN WORKSPACE, and emission is a separate invocation with its own
    # `$WS` — it can never see the review run's checkpoint. #716 proposed it as
    # the substrate; recorded here because the next reader will reach for it
    # again.
    publish_blockers = list(delivered_blockers)
    if not _host._review_evidence(slug, out_dir):
        publish_blockers.append({
            "slug": slug,
            "blocker": "review-evidence-not-found",
            "detail": (
                "no review record found for this canonical under "
                f"{os.path.join(_host._dest_repo_root(out_dir), 'reviews')} — this is "
                "CANNOT-DETERMINE, not a finding that the canonical is "
                "unreviewed: the pipeline writes no review records, so absence "
                "of a record is not absence of a review. If a review ran, its "
                "record is not where this check looks; if none ran, a "
                "claims-bearing canonical owes one."),
        })
    if publish_blockers:
        out["publish_blockers"] = publish_blockers
    if lede_proposals:
        out["lede_proposals"] = lede_proposals   # SKILL presents one per variant
    print(json.dumps(out, indent=2))
    return 0
