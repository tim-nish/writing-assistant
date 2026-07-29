#!/usr/bin/env python3
"""draft_policy — the policy-classification command family (Story 20.46, #920).

Extracted from `draft-pipeline.py` per the packaging invariant's scripts-family
clause (`specs/spec-writing-assistant/SPEC.md`, amended 2026-07-29, #914): the
dominant CLI/commands class takes the dispatcher-plus-per-command-module split,
by COMMAND FAMILY. The review family went first (Story 20.45); this is the
second, not a step toward lifting the layer wholesale.

**The CLI surface is the invariant.** `skills/draft-article/` invokes these
commands by name, so a changed command name, flag or exit code is a breaking
change wearing a refactor's clothes. Nothing here alters the surface: the same
three commands, the same arguments, the same returns.

**Why the host module is passed in rather than imported** — the same reasoning
as `draft_review.py`, unchanged: the family borrows helpers still defined in
`draft-pipeline.py` (a file that cannot be imported, its name carrying a
hyphen), so the host binds itself once and every borrowed name reads as
`_host.<name>` at its use site. The shared declarative table is different: it
already lives in its own importable module (`policy_subjects.py`, extracted for
Story 13.76 precisely so there is never a second copy), so it is imported
directly here rather than routed through the host.
"""

import argparse
import copy
import hashlib
import json
import os
import re
import subprocess
import sys  # noqa: F401  (kept: extracted code may reach for it)

import policy_subjects as _policy_subjects

# The host (`draft-pipeline.py`), bound once at import by the dispatcher. Never
# imported here: the host owns these helpers, and a second import path to them
# would be the drift this extraction exists to remove.
#
# The binding is over the host's GLOBALS, not its module object, and resolution
# is LAZY — same rationale as draft_review.py: several checks load
# `draft-pipeline.py` through `importlib.exec_module`, under which it is never
# registered in `sys.modules`, and a helper defined after the bind point must
# still resolve.
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
                f"{name!r} is not defined in the host module — the policy "
                f"family borrows it, so it must stay in draft-pipeline.py "
                f"or move here with the family") from None


def bind(namespace):
    """Bind the host's globals; call as `draft_policy.bind(globals())`."""
    global _host
    _host = _Host(namespace)


# The owner-judgment classes CAP-7 structurally exempts from every class but
# open/conflict: judgment is never pre-decided or candidate-filtered, even
# when an item's text happens to match a comparable subject.
JUDGMENT_CLASSES = {
    "opinion", "significance", "surprise", "tradeoff", "warning", "audience",
    "motivation", "retrospective",
}

# The declarative comparable-subjects table and its detector live in the
# shared module `policy_subjects.py` (extracted for Story 13.76 so the plan
# conformance gate validates against the SAME table — never a second copy).
COMPARABLE_SUBJECTS = _policy_subjects.COMPARABLE_SUBJECTS
_parse_policy_surface = _policy_subjects.parse_policy_surface
_config_lookup = _policy_subjects.config_lookup


def cmd_classify_policy(args):
    """Stage 2 pre-step: classify the served policy result for every candidate
    policy item BEFORE the interview (Story 13.75, SPEC-policy-source-seam
    CAP-7; seam-formats.md §2 reconciliation item). MECHANICAL — no LLM, no
    semantic parsing of arbitrary subjects: classification is computed over the
    declarative COMPARABLE_SUBJECTS table, which scopes it to RATIFIED FACTS
    (CAP-7's ratified-fact vs owner-judgment boundary).

    Four classes, per CAP-7:

      determined — structurally present but EMPTY-BY-DEFAULT: it activates as
        comparable subjects gain DETERMINING semantics in the table (the
        extension point).
      constrained — a served line rules some answers OUT without determining
        one (Story 18.49, #566): the question is STILL ASKED, and each
        candidate proposing a ruled-out value stays IN the presented list
        MARKED `excluded` with the governing line's verbatim quote and pinned
        pointer. The override is real — the owner may still pick it, which
        routes to the staging candidate as a proposed policy change. Silent
        suppression (dropping the candidate) is a defect of this CAP: it makes
        a constrained question indistinguishable from a free choice and hides
        the exclusion from audit.
      open       — the default pass-through: policy does not answer; the item
        is presented unchanged.
      conflict   — a served policy line and an authoritative user-config key
        disagree on a comparable subject: emit ONE reconciliation item
        (`gap_type: reconciliation`, a `positions` array carrying every
        disagreeing side with its pointer + authority) and REFUSE to pass any
        candidate tension item on that subject through as an ordinary item —
        the original is marked `superseded_by_reconciliation` (R9's
        classifier half: the reconciliation gate cannot be bypassed).

    Structural exemption: an item whose gap_type is an owner-judgment class
    (opinion, significance, surprise, tradeoff, warning, audience, motivation,
    retrospective) is ALWAYS `open` — judgment is never pre-decided or
    filtered, even when its text matches a conflict subject.

    Inputs: --surface (the reader's `read` output: pin + line-numbered files);
    the resolved user config (--config-json, or --root like other
    subcommands); --items (the candidate policy items the agent authored,
    seam-formats.md §2); --facts (harvest-state JSON — reserved for repo-state
    positions as subjects gain repo comparability); --config-version (the
    cited configVersion; default: a sha256 prefix of the resolved config).

    Output JSON: {pin, config_version, classified, reconciliation_items,
    determined, constrained, journal_records, interview_items} —
    `interview_items` is the ready-to-pass `--items` array for `interview`
    (reconciliation items first, then the open pass-throughs, superseded
    originals excluded).
    """
    try:
        surface_text = open(args.surface, encoding="utf-8").read()
    except OSError as e:
        sys.stderr.write(f"error: cannot read policy surface {args.surface!r}: {e}\n")
        return 2
    pin, surface_lines = _parse_policy_surface(surface_text)

    rf = _host._load("render-frontmatter.py")
    cfg_args = argparse.Namespace(config_json=args.config_json, root=args.root,
                                  global_config=args.global_config,
                                  repo_config=args.repo_config)
    try:
        cfg = rf.load_config(cfg_args)
    except Exception as e:
        sys.stderr.write(f"error: cannot resolve user config: {e}\n")
        return 2
    config_version = args.config_version or hashlib.sha256(
        json.dumps(cfg, sort_keys=True).encode("utf-8")).hexdigest()[:12]

    items = []
    if args.items:
        items = _host._load_json_state(args.items, "candidate policy items")
        if isinstance(items, dict) and "items" in items:
            items = items["items"]
        if not isinstance(items, list):
            sys.stderr.write("error: --items must be a JSON array of interview items\n")
            return 2
    if args.facts:
        # Reserved: repo-state positions join as the subject table gains
        # repo-comparable rows; loading validates the input exists and parses.
        _host._load_json_state(args.facts, "harvest state")

    # 1. Conflict detection over the declared comparable subjects (shared
    # detector — the conformance gate runs the same one). Constraint detection
    # runs the same table; precedence (conflict > constrained) lives in the
    # detector, so a subject never lands in both classes.
    conflicts = _policy_subjects.detect_conflicts(surface_lines, cfg, config_version)
    constraints = _policy_subjects.detect_constraints(surface_lines, cfg, config_version)

    reconciliation_items = []
    journal_records = []
    for i, c in enumerate(conflicts, 1):
        subject = c["subject"]
        rid = f"rc{i}"
        question = (
            f"Served policy records \"{c['policy']['quote']}\" "
            f"({c['policy']['pointer']}), while your authoritative config "
            f"declares {c['config']['quote']} ({c['config']['pointer']}) — "
            f"these disagree on {subject['label']}. Which position governs "
            "this run, and should the losing record be updated?")
        parse = dict(subject.get("parse") or {})
        reconciliation_items.append({
            "id": rid, "gap_type": "reconciliation",
            "positions": [c["policy"], c["config"]],
            # The machine's parse, rendered in the gate banner BEFORE the
            # options (#739): rule / predicate / reading / binds — so the owner
            # can catch a misparse while it is still cheap.
            "parse": parse,
            # Structured outcomes (#739): "no conflict" is a first-class
            # option, never only free-form — the incident's truthful answer
            # had no structured carrier and all three options encoded the
            # false premise.
            "options": [
                {"id": "no-conflict",
                 "label": "No conflict — both records stand",
                 "effect": "changes neither config nor policy; both records "
                           "stay in force and the journal records "
                           "reconciliation_outcome: no-conflict"},
                {"id": "config-governs",
                 "label": f"Config governs ({c['config']['quote']})",
                 "effect": "the served line is recorded as not governing this "
                           "run; the answer routes to a staging-candidate "
                           "block proposing the policy-side update"},
                {"id": "policy-governs",
                 "label": "Policy governs (the served line stands)",
                 "effect": "the config value is the losing record; a PROPOSED "
                           "change routed via the staging candidate — never "
                           "treated as current policy by this run"},
            ],
            "question": question, "owner_answer": "",
        })
        journal_records.append({
            "id": rid, "class": "conflict", "subject": subject["id"],
            "positions": [c["policy"], c["config"]],
        })

    def conflict_for(item):
        """The detected conflict a candidate tension item's seed line sits on
        (matched by pinned pointer file:line, or by the subject's own line
        pattern over the seed quote) — else None."""
        seed = item.get("seed") or {}
        seed_ptr = str(seed.get("pointer", "")).rsplit("@", 1)[0]
        seed_quote = str(seed.get("quote", ""))
        for i, c in enumerate(conflicts):
            policy_loc = c["policy"]["pointer"].rsplit("@", 1)[0]
            if seed_ptr and seed_ptr == policy_loc:
                return i
            if seed_quote and c["subject"]["policy_line"].search(seed_quote):
                return i
        return None

    def constrain_item(item):
        """Mark every candidate answer a served line rules out, in place on a
        COPY. Returns (new_item, marks) or (None, []) when nothing is excluded.

        The excluded candidate is never dropped: it stays in the presented list
        carrying `excluded: {value, reason, quote, pointer, authority}` so the
        owner sees WHAT was ruled out and BY WHICH line, and can still pick it.
        """
        # Item-level `candidates` — NOT `recommended_default`, whose eligibility
        # (R6/R7) is the editorial-judgment classes, and judgment is structurally
        # exempt from this class. The two carriers are mutually exclusive by
        # construction, so a constrained question carries its own answers.
        positions = item.get("candidates")
        if not isinstance(positions, list):
            return None, []

        marks = []
        for idx, pos in enumerate(positions):
            if not isinstance(pos, dict) or pos.get("excluded") is not None:
                continue
            for c in constraints:
                value = _policy_subjects.excluded_by(c, pos.get("answer", ""))
                if value is None:
                    continue
                marks.append({
                    "index": idx, "value": value, "subject": c["subject"]["id"],
                    "excluded": {
                        "value": value,
                        "reason": (f"served policy rules out {value!r} for "
                                   f"{c['subject']['label']}"),
                        "quote": c["policy"]["quote"],
                        "pointer": c["policy"]["pointer"],
                        "authority": "policy",
                    },
                })
                break
        if not marks:
            return None, []

        new_item = copy.deepcopy(item)
        for m in marks:
            new_item["candidates"][m["index"]]["excluded"] = m["excluded"]
        # The class travels WITH the item so the presentation layer and the
        # validator can both tell a constrained question from a free choice.
        new_item["policy_class"] = "constrained"
        return new_item, marks

    # 2. Classify every candidate item.
    classified = []
    open_items = []
    constrained = []
    for item in items:
        gap_type = item.get("gap_type")
        if gap_type in JUDGMENT_CLASSES:
            # Structural exemption: owner judgment is never pre-decided or
            # filtered — always open, text match or not.
            classified.append({"id": item.get("id"), "class": "open",
                               "exemption": "owner-judgment", "item": item})
            open_items.append(item)
            continue
        ci = conflict_for(item)
        if ci is not None:
            rid = reconciliation_items[ci]["id"]
            classified.append({"id": item.get("id"), "class": "conflict",
                               "superseded_by_reconciliation": rid,
                               "item": item})
            journal_records.append({
                "id": item.get("id"), "class": "conflict",
                "superseded_by_reconciliation": rid,
                "subject": conflicts[ci]["subject"]["id"],
            })
            continue
        constrained_item, marks = constrain_item(item)
        if constrained_item is not None:
            classified.append({"id": item.get("id"), "class": "constrained",
                               "item": constrained_item})
            constrained.append({
                "id": item.get("id"),
                "subject": marks[0]["subject"],
                "excluded": [m["excluded"] for m in marks],
            })
            journal_records.append({
                "id": item.get("id"), "class": "constrained",
                "subject": marks[0]["subject"],
                "excluded": [m["excluded"] for m in marks],
            })
            # Still ASKED — a constrained question is presented, never suppressed.
            open_items.append(constrained_item)
            continue
        classified.append({"id": item.get("id"), "class": "open", "item": item})
        open_items.append(item)

    out = {
        "stage": "classify-policy",
        "pin": pin,
        "config_version": config_version,
        "classified": classified,
        "reconciliation_items": reconciliation_items,
        "determined": [],
        "constrained": constrained,
        "journal_records": journal_records,
        "interview_items": reconciliation_items + open_items,
    }
    print(json.dumps(out, indent=2))
    return 0


# --- Stage 2→3 policy-block gate (Story 13.77, #365) --------------------------
#
# SPEC-article-draft-pipeline (2026-07-18 amendment): draft generation BLOCKS
# on a conflict or stale plan — a stage-progression precondition like the
# quality gate, surfaced as a publish blocker naming the conflicting positions
# (or the moved pin/configVersion), never silently proceeded past. The block
# point is the Stage 2→3 boundary: pre-draft the gate input is the
# `classify-policy` result (+ recorded answers), and on resumed runs with an
# existing plan, the plan's recorded CAP-4 conformance status (recomputed at
# the current pin when a fresh surface is supplied).

# Dispositions that count as an OWNER ANSWER to a reconciliation question —
# any recorded decision, INCLUDING a reversal (which proceeds as a proposed
# policy change via its staging-candidate block, never as current policy). A
# skip records no decision, so the conflict stays unresolved and blocking.
RECONCILIATION_ANSWERED = {"answered", "modified", "replaced", "approved",
                           "ratified"}

# The suggested block checkpoint: the run resumes AT the block — the
# reconciliation question re-presents on resume (`next_stage: interview`) —
# never before Stage 2, and never past the gate at `fill`.
BLOCK_CHECKPOINT = {"stage": "policy-block", "next_stage": "interview"}


def _conformance_recompute(args):
    """Re-run the CAP-4 conformance gate over --plan against the supplied
    surface (read-only — never --write) and return its parsed JSON. Delegated
    to `write-article-plan.py conformance` via subprocess so this gate and the
    plan gate can never diverge (same table, same rules, one implementation)."""
    here = os.path.dirname(os.path.realpath(__file__))
    cmd = [sys.executable, os.path.join(here, "write-article-plan.py"),
           "conformance", "--plan", args.plan, "--surface", args.surface]
    if args.config_json:
        cmd += ["--config-json", args.config_json]
    if args.root:
        cmd += ["--root", args.root]
    if args.config_version:
        cmd += ["--config-version", args.config_version]
    if args.staging:
        cmd += ["--staging", args.staging]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip() or "conformance recompute failed")
    return json.loads(r.stdout)


def _conflict_blocker_text(blockers):
    """The copy-pasteable publish-blocker wording for unresolved conflicts:
    every disagreeing position named with its pointer, plus the repair."""
    parts = []
    for b in blockers:
        pos = " vs ".join(
            f"{p.get('authority', '?')}: \"{p.get('quote', '')}\" "
            f"({p.get('pointer', '?')})" for p in b.get("positions", []))
        if pos:
            parts.append(pos)
        elif b.get("recorded"):
            rec = b["recorded"]
            parts.append(f"recorded policy_conformance: conflict at "
                         f"policy_pin {rec.get('policy_pin')} / configVersion "
                         f"{rec.get('policy_config_version')} (re-run the "
                         "conformance gate with the current surface to name "
                         "the positions)")
    return ("Draft generation is blocked: served policy and the "
            "authoritative config disagree — " + "; ".join(parts) + ". "
            "Answer the reconciliation question to choose which position "
            "governs this run; an owner reversal proceeds as a proposed "
            "policy change (its staging-candidate block), never as current "
            "policy.")


def _stale_blocker_text(pin_delta):
    cur = pin_delta.get("current_pin") or ("unknown — re-consult at the "
                                           "current pin to learn it")
    changed = ", ".join(pin_delta.get("changed") or []) or "(unenumerated)"
    return ("Draft generation is blocked: the consulted policy pin moved — "
            f"recorded {pin_delta.get('recorded_pin')} (configVersion "
            f"{pin_delta.get('recorded_config_version')}), current {cur}; "
            f"changed consulted lines: {changed}. Re-consult at the current "
            "pin (re-run the policy reader, classify-policy, and the "
            "conformance recompute against the fresh surface), then re-run "
            "this check — it proceeds or re-blocks per the new status.")


def cmd_policy_block_check(args):
    """The Stage 2→3 stage-progression precondition (Story 13.77,
    SPEC-article-draft-pipeline 2026-07-18 amendment): draft generation blocks
    on an unresolved config↔policy conflict or a stale plan. MECHANICAL — no
    LLM; it reads what earlier mechanical steps already computed.

    Blocked iff:

      (a) --classification (a `classify-policy` output) contains a
          reconciliation item with NO recorded owner answer — pass --answers
          (the recorded answer records) to check dispositions; ANY recorded
          decision unblocks, including a reversal (it proceeds as a proposed
          policy change via staging, never as current policy). A skip is not
          an answer;
      (b) --plan (an existing article plan, the resumed-run half) whose
          conformance status is `conflict` or `stale` — the recorded
          `policy_conformance` frontmatter by default; with --surface the
          status is RECOMPUTED at the current pin through the CAP-4 gate
          (`write-article-plan.py conformance`, read-only), so a re-consult
          whose referenced lines still hold clears a recorded `stale`.

    `conformant` and `open` proceed unchanged. Generic mode — no
    classification and no policy-touched plan — never fires the gate:
    {blocked: false, reason: "generic-mode"}.

    Blocked output is a publish-blocker payload: `action: publish-blocker`,
    the conflicting positions with pointers (or `pin_delta` naming the moved
    pin/configVersion), copy-pasteable `publish_blocker` wording, the in-run
    `repair`, and the suggested block `checkpoint`
    {"stage": "policy-block", "next_stage": "interview"} — resumable at the
    block (the reconciliation question re-presents), never at `fill`.
    """
    blockers = []
    positions = []
    pin_delta = None
    reasons = []
    policy_in_play = False

    # (a) The classification half: unresolved reconciliation items block.
    if args.classification:
        policy_in_play = True
        data = _host._load_json_state(args.classification, "classify-policy output")
        rec_items = data.get("reconciliation_items", []) \
            if isinstance(data, dict) else []
        answers = {}
        if args.answers:
            parsed = _host._load_json_state(args.answers, "answers batch")
            for a in (parsed if isinstance(parsed, list) else [parsed]):
                answers[a.get("id")] = a.get("disposition")
        unresolved = 0
        for item in rec_items:
            disp = answers.get(item.get("id"))
            if disp in RECONCILIATION_ANSWERED:
                continue   # answered — a reversal rides staging as a proposal
            unresolved += 1
            blockers.append({
                "kind": "conflict", "id": item.get("id"),
                "positions": item.get("positions", []),
                "question": item.get("question"),
                "why": ("skipped — a skip records no reconciliation decision"
                        if disp == "skipped" else "no recorded owner answer"),
            })
            positions.extend(item.get("positions", []))
        if rec_items and not unresolved:
            reasons.append("reconciliation-answered")
        elif not rec_items:
            reasons.append("no-conflict-classified")

    # (b) The plan half (resumed runs): recorded status, or a recompute at
    # the current pin when a fresh surface is in hand.
    if args.plan:
        wap = _host._load("write-article-plan.py")
        try:
            plan_text = open(args.plan, encoding="utf-8").read()
        except OSError as e:
            sys.stderr.write(f"error: cannot read plan {args.plan!r}: {e}\n")
            return 2
        fields, _body, _errs = wap.split_frontmatter(plan_text)
        seeded = wap._truthy(fields.get("policy_seeded", ""))
        recorded = fields.get("policy_conformance", "")
        conf = None
        if args.surface:
            # Re-consult path: recompute through the CAP-4 gate at the
            # current pin — a recorded `stale` clears when the referenced
            # lines still hold; a live conflict re-blocks with positions.
            policy_in_play = True
            try:
                conf = _conformance_recompute(args)
            except (RuntimeError, json.JSONDecodeError, OSError) as e:
                sys.stderr.write(f"error: conformance recompute failed: {e}\n")
                return 2
            status = conf["status"]
        else:
            if seeded or recorded:
                policy_in_play = True
            status = recorded or None

        if status == "conflict":
            conflict_findings = [f for f in (conf or {}).get("findings", [])
                                 if f.get("kind") == "conflict"]
            if conflict_findings:
                for f in conflict_findings:
                    blockers.append({"kind": "conflict",
                                     "subject": f.get("subject"),
                                     "positions": f.get("positions", []),
                                     "why": f.get("note")})
                    positions.extend(f.get("positions", []))
            else:
                blockers.append({
                    "kind": "conflict",
                    "recorded": {
                        "policy_pin": fields.get("policy_pin"),
                        "policy_config_version":
                            fields.get("policy_config_version")},
                    "why": "the plan records policy_conformance: conflict"})
        elif status == "stale":
            stale_findings = [f for f in (conf or {}).get("findings", [])
                              if f.get("kind") == "stale"]
            pin_delta = {
                "recorded_pin": fields.get("policy_pin"),
                "current_pin": (conf or {}).get("pin"),
                "recorded_config_version": fields.get("policy_config_version"),
                "current_config_version": (conf or {}).get("config_version"),
                "changed": [f["pointer"] for f in stale_findings
                            if f.get("pointer")],
            }
            blockers.append({"kind": "stale", "pin_delta": pin_delta,
                             "why": "the consulted policy pin moved and a "
                                    "referenced consulted line changed"
                                    if conf else
                                    "the plan records policy_conformance: "
                                    "stale"})
        elif status in ("conformant", "open"):
            reasons.append(f"plan-{status}")

    # Generic mode: no policy_source in play anywhere — the gate NEVER fires.
    if not policy_in_play:
        print(json.dumps({"stage": "policy-block-check", "blocked": False,
                          "reason": "generic-mode",
                          "note": "no policy classification and no "
                                  "policy-seeded plan — behavior identical "
                                  "to a repo without the seam"}, indent=2))
        return 0

    out = {"stage": "policy-block-check", "blocked": bool(blockers)}
    if not blockers:
        out["reason"] = "; ".join(reasons) or "no-policy-conflict"
        print(json.dumps(out, indent=2))
        return 0

    conflict_blockers = [b for b in blockers if b["kind"] == "conflict"]
    out["reason"] = "; ".join(
        (["unresolved config↔policy conflict"] if conflict_blockers else []) +
        (["stale plan (moved pin)"] if pin_delta else []))
    out["action"] = "publish-blocker"
    out["blockers"] = blockers
    if positions:
        out["positions"] = positions
    if pin_delta:
        out["pin_delta"] = pin_delta
    texts = []
    if conflict_blockers:
        texts.append(_conflict_blocker_text(conflict_blockers))
    if pin_delta:
        texts.append(_stale_blocker_text(pin_delta))
    out["publish_blocker"] = " ".join(texts)
    out["repair"] = ("Repairable in-run: answer the reconciliation question "
                     "(record it via `answer`, re-run this check — any "
                     "recorded decision unblocks, a reversal routes to "
                     "staging as a proposed policy change), or for a stale "
                     "plan re-consult at the current pin (re-run the reader "
                     "+ classify-policy + conformance) and re-run this check.")
    out["checkpoint"] = dict(BLOCK_CHECKPOINT)
    print(json.dumps(out, indent=2))
    return 0


def cmd_policy_prefilter(args):
    """Stage-2 policy-surface pre-filter (Story 19.7, #741) — a DETERMINISTIC,
    behavior-preserving reduction of the materialized policy surface to the
    lines Stage 2 actually classifies against, before the surface enters model
    context. Observed cost without it: a 214KB (~55k-token) surface consumed
    whole for ~10KB of outputs.

    Allowlist, fail-open to inclusion:
      * structural lines (the pin, `=== FILE @ sha` section headers);
      * every line ANY comparable subject's patterns match — `policy_line` AND
        `policy_line_excludes` — so no line class the conflict/constraint gate
        reads is ever filtered out;
      * every line mentioning a subject's `config_key` (or its head token);
      * every line a candidate item's seed pointer names (`--items`);
      * section headings (`## …`) and state lines, as cheap skeleton context.

    Writes the filtered artifact BESIDE the full one (never over it) for
    auditability, and prints the size disclosure the run status relays.
    """
    try:
        text = open(args.surface, encoding="utf-8").read()
    except OSError as e:
        sys.stderr.write(f"error: cannot read policy surface {args.surface!r}: {e}\n")
        return 2
    seed_locs = set()
    if args.items:
        items = _host._load_json_state(args.items, "candidate policy items")
        if isinstance(items, dict) and "items" in items:
            items = items["items"]
        for it in items if isinstance(items, list) else []:
            ptr = str(((it or {}).get("seed") or {}).get("pointer", ""))
            if ptr:
                seed_locs.add(ptr.rsplit("@", 1)[0])   # file:line

    key_tokens = set()
    subj_patterns = []
    for s in COMPARABLE_SUBJECTS:
        subj_patterns.append(s["policy_line"])
        excl = s.get("policy_line_excludes")
        if excl is not None:
            subj_patterns.append(excl)
        key = s.get("config_key", "")
        if key:
            key_tokens.add(key)
            key_tokens.add(key.split(".")[0])

    kept, total = [], 0
    current_file = None
    line_re = re.compile(r"^(\d+):")
    for raw in text.splitlines():
        if raw.startswith("pin: ") or raw.startswith("=== ") or raw.startswith("miss: "):
            if raw.startswith("=== "):
                current_file = raw[4:].rsplit(" @ ", 1)[0].strip()
            kept.append(raw)
            continue
        m = line_re.match(raw)
        if not m:
            kept.append(raw)          # fail-open: unrecognized shapes stay
            continue
        total += 1
        body = raw.split(":", 1)[1]
        keep = (
            any(p.search(body) for p in subj_patterns)
            or any(k in body for k in key_tokens)
            or (current_file and f"{current_file}:{m.group(1)}" in seed_locs)
            or body.lstrip().startswith("## ")
            or body.lstrip().startswith("`state:")
        )
        if keep:
            kept.append(raw)
    out_path = args.out or (args.surface[:-4] + ".filtered.txt"
                            if args.surface.endswith(".txt")
                            else args.surface + ".filtered.txt")
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(kept) + "\n")
    full_b, filt_b = len(text.encode()), os.path.getsize(out_path)
    disclosure = (f"policy surface pre-filtered (#741): {full_b} -> {filt_b} bytes "
                  f"({total} content lines -> {sum(1 for k in kept if line_re.match(k))} kept); "
                  f"full surface retained at {args.surface}")
    print(json.dumps({"stage": "policy-prefilter", "surface": args.surface,
                      "filtered": out_path, "full_bytes": full_b,
                      "filtered_bytes": filt_b, "disclosure": disclosure},
                     indent=2))
    return 0
