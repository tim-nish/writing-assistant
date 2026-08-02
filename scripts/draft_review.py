#!/usr/bin/env python3
"""draft_review — the review command family (Story 20.45, #919).

Extracted from `draft-pipeline.py` per the packaging invariant's scripts-family
clause (`specs/spec-writing-assistant/SPEC.md`, amended 2026-07-29, #914): that
file measured 61% CLI/commands, the case the sanctioned dispatcher-plus-
per-command shape was written for. The 41 commands spread across roughly twenty
stems, so the extraction proceeds by COMMAND FAMILY — this is the first, not a
step toward lifting the layer wholesale.

**The CLI surface is the invariant.** `skills/draft-article/` invokes these
commands by name, so a changed command name, flag or exit code is a breaking
change wearing a refactor's clothes. Nothing here alters the surface: the same
four commands, the same arguments, the same returns.

**Why the host module is passed in rather than imported.** The four commands
depend on seventeen names still defined in `draft-pipeline.py`, whose own
transitive closure runs to a dozen more — and that file cannot be imported at
all, its name carrying a hyphen. Chasing the closure into a shared-base module
is the right end state and a poor first move: it would put several hundred
lines of unmeasured refactoring inside a story whose hard invariant is a
byte-identical CLI. So the dependency is made EXPLICIT instead of hidden — the
host binds itself once, and every borrowed name reads as `_host.<name>` at its
use site, which is what makes the shared base's eventual shape legible rather
than guessed. Stories 20.46 and 20.47 extract two more families against the
same seventeen-ish set; if that set proves stable, it IS the shared base and
should be lifted then, on evidence rather than in advance.
"""

import hashlib
import json
import os
import re
import subprocess
import sys  # noqa: F401  (kept: extracted code may reach for it)

# The host (`draft-pipeline.py`), bound once at import by the dispatcher. Never
# imported here: the host owns these helpers, and a second import path to them
# would be the drift this extraction exists to remove.
#
# The binding is over the host's GLOBALS, not its module object, and resolution
# is LAZY. Both matter: several checks load `draft-pipeline.py` through
# `importlib.exec_module`, under which it is never registered in `sys.modules`,
# so binding `sys.modules[__name__]` raises there while working fine under a
# normal run — a failure that appears only in the test path. Lazy lookup also
# means a helper defined after the bind point still resolves.
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
                f"{name!r} is not defined in the host module — the review "
                f"family borrows it, so it must stay in draft-pipeline.py "
                f"or move here with the family") from None


def bind(namespace):
    """Bind the host's globals; call as `draft_review.bind(globals())`."""
    global _host
    _host = _Host(namespace)


def _verdict_record_sha(text):
    """The record's `attestation: draft-sha256=<hex>` value, or None for a
    pre-19.15 record (which re-entry treats as PARTIAL — never grandfathered)."""
    for ln in text.splitlines():
        m = re.match(r"attestation:\s*draft-sha256=([0-9a-fA-F]{64})\s*$", ln.strip())
        if m:
            return m.group(1).lower()
    return None


def _rubric_dimension_count(path=None):
    """How many dimensions the VERSIONED rubric defines — counted from
    quality-rubric.md's `## Dimension N` sections, never a hardcoded number. The
    completion summary quotes this so a gate report can never miscount the
    rubric (#496). A missing/unreadable rubric raises (OSError) rather than
    inventing a count: a summary that cannot read the rubric must not assert
    one."""
    p = path or _host.RUBRIC_ASSET
    with open(p, encoding="utf-8") as fh:
        return len(_host._RUBRIC_DIM_RE.findall(fh.read()))


def _diff_change_list(before_lines, after_lines):
    """Fold a difflib opcode stream into a compact applied-change list — one
    entry per replaced/inserted/deleted block, each carrying its removed/added
    lines and an anchor into the AFTER draft (owner-facing, for in-conversation
    display alongside the unified diff)."""
    import difflib
    sm = difflib.SequenceMatcher(a=before_lines, b=after_lines, autojunk=False)
    changes = []
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            continue
        changes.append({
            "kind": tag,                       # replace | insert | delete
            "after_line": j1 + 1,              # 1-based anchor into the AFTER draft
            "removed": before_lines[i1:i2],
            "added": after_lines[j1:j2],
        })
    return changes


def _derived_ancestry_evidence(draft_text):
    """Ancestry evidence for a DERIVED canonical's review re-entry (Story
    18.110, #704). Returns (evidence_dict_or_None, problems_list).

    A derived canonical owns no claims of its own — they are inherited under
    SPEC-canonical-adaptation CAP-2 — so it has no provenance map, and requiring
    one would re-attest claims that are not its to attest. Its completion
    evidence is its ANCESTRY instead.

    WHAT THIS FUNCTION JUDGES, AND WHAT IT DELIBERATELY DOES NOT
    ------------------------------------------------------------
    It judges the pin's SHAPE only: present, and the ratified scalar
    `<slug>@<64-hex>`. Whether that pin RESOLVES — a real source canonical at a
    matching content hash — is `lint-ancestry`'s business, and this module does
    not call it: the adaptation invocation imports THIS module, and CAP-1's
    boundary forbids the draft pipeline from referencing adaptation at all — the
    guard is a grep for the module's NAME, so this file does not even spell it.
    The resolution check is REPORTED in the required-checks worklist instead,
    exactly as `verify-provenance` is for an authored canonical — this command
    emits worklists and runs no checks.

    Accepted cost, decided at the #704 re-triage and recorded in
    SPEC-canonical-adaptation: the checkpoint is therefore written before the
    ancestry is known to RESOLVE. A malformed pin refuses here; an unresolvable
    one is caught by the reported check.
    """
    fields, _body = _host._read_frontmatter(draft_text)
    raw = (fields or {}).get("adapted_from")
    if raw is None:
        return None, []                      # not a derivation
    pin = str(raw).strip().strip('"\'')
    if not _host._ANCESTRY_PIN_SHAPE.match(pin):
        return ({"pin": pin},
                [f"`adapted_from` is not the scalar pin `<slug>@<sha256>` "
                 f"(a slug, `@`, and a 64-char sha256 digest); got {raw!r}"])
    return {"pin": pin, "pin_shape": "well-formed",
            "resolution_check": "reported, not run — see required_checks"}, []


def _reproject_plan(slug, root, canonical_text, ws):
    """Re-project plans/<slug>.md from the reviewed canonical (Story 19.17,
    #757). A review round that applies edits can change exactly the facts the
    plan exists to carry — the observed incident: an owner-directed audience
    narrowing left `plans/<slug>.md` stating an audience the reviewed
    canonical contradicts, so a cold Revise session would confidently
    reconstruct the pre-review article.

    Deterministic projection, no new owner interaction (SPEC-article-plan
    CAP-1 as amended 2026-07-26):
      * frontmatter `audience:` mirrors the reviewed canonical's;
      * frontmatter `sections:` re-derives from the edited draft's `##`
        headings — a heading matching an existing entry (normalized) keeps
        its elements; a renamed heading inherits by position, or the sole
        consumed element when there is exactly one;
      * everything else (claim, consumed, pins, body) is plan-owned and
        carried unchanged.
    Returns a result dict; raises _host._CanonicalWriteError-style failure via
    (False, reason) — the caller refuses the checkpoint on it. A slug with no
    plan (hand-adopted canonical, derived canonical) skips with a note.
    """
    wap = _host._load("write-article-plan.py")
    try:
        plan_path, _conf, _repo = wap.resolve_dest(
            _host._load("resolve-paths.py").host_root(root), slug)
    except Exception as e:
        return {"reprojected": False, "note": f"plan destination unresolvable: {e}"}
    if not os.path.isfile(plan_path):
        return {"reprojected": False,
                "note": f"no plan at {plan_path} — nothing to re-project "
                        "(hand-adopted or derived canonical)"}
    plan_text = open(plan_path, encoding="utf-8").read()
    fields, body, errs = wap.split_frontmatter(plan_text)
    if errs:
        return {"reprojected": False,
                "note": f"existing plan unparseable ({errs[0][1]}) — left untouched"}

    cfields, _cbody = _host._read_frontmatter(canonical_text)
    changed = []

    # audience mirrors the canonical
    new_audience = (cfields or {}).get("audience")
    if new_audience and fields.get("audience") != new_audience:
        changed.append(("audience", fields.get("audience"), new_audience))

    # sections re-derive from the edited draft's headings
    old_sections = wap.parse_sections(fields.get("sections", "")) or []
    consumed = wap.parse_id_list(fields.get("consumed", ""))
    def norm(h):
        return re.sub(r"[^a-z0-9]+", " ", h.lower()).strip()
    old_by_title = {norm(s.get("title", "")): s.get("elements", [])
                    for s in old_sections}
    headings = [ln.lstrip("#").strip() for ln in canonical_text.splitlines()
                if ln.startswith("## ") and "{Pointer block}" not in ln]
    if not headings:
        # A draft with no `##` headings gives the derivation nothing to work
        # from — keep the plan's recorded sections rather than erasing them.
        headings = None
    new_sections = []
    for i, h in enumerate(headings or []):
        els = old_by_title.get(norm(h))
        if els is None:
            if len(consumed) == 1:
                els = list(consumed)
            elif i < len(old_sections):
                els = old_sections[i].get("elements", [])
            else:
                els = []
        new_sections.append({"title": h, "elements": els})
    old_render = json.dumps(old_sections, sort_keys=True)
    new_render = json.dumps(new_sections, sort_keys=True)
    if headings is not None and old_render != new_render:
        changed.append(("sections", f"{len(old_sections)} entries",
                        f"{len(new_sections)} entries re-derived"))

    if not changed:
        return {"reprojected": False, "note": "plan already mirrors the "
                "reviewed canonical — nothing to re-emit"}

    # rewrite only the changed frontmatter lines; body carried unchanged
    lines = plan_text.splitlines(keepends=True)
    close = next(i for i, ln in enumerate(lines[1:], 1) if ln.strip() == "---")
    fm = lines[1:close]
    def set_key(key, value):
        nonlocal fm
        rendered = f"{key}: {value}\n"
        for i, ln in enumerate(fm):
            if ln.split(":", 1)[0].strip() == key:
                fm[i] = rendered
                return
        fm.append(rendered)
    for key, _old, _new in changed:
        if key == "audience":
            set_key("audience", new_audience)
        if key == "sections":
            set_key("sections", json.dumps(new_sections, ensure_ascii=False))
    new_plan = lines[0] + "".join(fm) + "".join(lines[close:])

    defects = list(wap.validate_plan(new_plan,
                                     os.path.join("plans", f"{slug}.md")))
    if defects:
        return {"reprojected": False, "failed": True,
                "note": "re-projected plan failed the writer's validation: "
                        + "; ".join(f"{k}: {v}" for k, v in defects[:3])}
    with open(plan_path, "w", encoding="utf-8") as fh:
        fh.write(new_plan)
    return {"reprojected": True, "path": plan_path,
            "changed": [{"field": k, "from": str(a)[:60], "to": str(b)[:60]}
                        for k, a, b in changed]}


def cmd_review_consulted(args):
    """Review-side consulted: line (Story 15.3, SPEC-policy-consistency-pass
    CAP-4) — the same /ask-style audit grammar as the interview seam's, mapping
    checked policy lines to the FINDINGS they produced instead of questions.

    Modes:
      * findings present: each finding's policy pointer (sans pin) -> `finding
        <n>`; whitelisted files with no finding close as `(no conflict)`;
      * pass ran, zero findings: every checked file -> `(no conflict)`;
      * pass skipped: THREE states, not two (#1306, SPEC-run-record CAP-5) —
        `policy_source unavailable: <reason>` when the reader itself said so
        via --policy-note; else derived from `--ws`: a policy-surface artifact
        in the run workspace means the source was configured AND read, so an
        empty result is the EDITORIAL fact `policy surface read; no seeds
        authored`, and only its absence licenses `policy_source unset`.
        Reporting a derived absence as a configured one points the next
        debugger at a config key when the fact is editorial (#1289).
    """
    if args.policy_note is not None:
        # Shared normalization with the interview seam (_host.cmd_journal): a caller
        # pasting the whole rendered `none (...)` phrase must not double-wrap
        # to `consulted: none (none (...))` (F77). The derivation is the interview
        # seam's own (`run_record.consulted_reason`), not a second copy of it.
        #
        # NO `fallback_path` HERE, and that is a decline rather than an omission:
        # `cmd_journal` could fall back to `--interview`'s directory because that
        # input sits in the run workspace. This command's skipped mode takes no
        # such input — `--pin`/`--file` are not paths, and `--findings` exists
        # only when the pass RAN. Inventing a fallback would manufacture evidence.
        print("consulted: none (%s)" % _host.run_record.consulted_reason(
            _host._bare_policy_reason(args.policy_note), getattr(args, "ws", None)))
        return 0
    if not args.pin:
        sys.stderr.write("error: pass --pin product-lab@<sha> (seeded mode) "
                         "or --policy-note (skipped mode)\n")
        return 2
    pin = args.pin.split("@", 1)[1] if "@" in args.pin else args.pin
    findings = []
    if args.findings:
        data = _host._load_json_state(args.findings, "policy findings")
        findings = data if isinstance(data, list) else [data]
    parts = []
    seen_files = set()
    for i, f in enumerate(findings, 1):
        ptr = ((f.get("policy") or {}).get("pointer") or "").rsplit("@", 1)[0]
        if not ptr:
            continue
        parts.append(f"{ptr} → finding {i}")
        seen_files.add(ptr.split(":", 1)[0])
    for rel in (args.file or []):
        if rel not in seen_files:
            parts.append(f"{rel} → (no conflict)")
    if not parts:
        parts.append("(nothing checked)")
    print(f"consulted: product-lab@{pin} — " + "; ".join(parts))
    return 0


def cmd_review_reentry(args):
    """Post-arbitration re-entry into the gate regime (Story 13.70). Invoked by
    the review SKILL after an arbitration round that applied >=1 accepted
    finding, with the edited draft and the provenance map rebuilt against it.
    The ordered sequence, stopping at the first failure:

      (a) persist the reviewed canonical to `<output.drafts>/<slug>.md` via
          the SAME write path as the draft flow's `complete` gate
          (`_host._persist_canonical` — one write path, one trailer convention);
      (b) validate the re-entry EVIDENCE, typed by artifact class (#704): an
          AUTHORED canonical's is the rebuilt map, structurally validated
          against the edited draft with anchors required (the
          `provenance --map --draft` checks, reused); a DERIVED canonical's
          (one carrying `adapted_from`) is its ANCESTRY — `lint-ancestry`
          clean — because it owns no claims of its own (CAP-2) and a map over
          it would re-attest claims that are not its to attest. `--map` is
          required for the first class and unused by the second;
      (c) report the scoped regression checks the SKILL must now run — this
          command spawns NO judges; it emits the worklist (verify-provenance
          re-run always; the quality gate's mechanical dims when
          --rubric-applied says a rubric-mapped finding was applied);
      (d) mark existing variants stale: run the staleness comparison
          (`variant-staleness` internals, reused) and list the stale variants;
      (e) STOP — review never emits or re-emits a variant (CAP-3); it writes
          the `{"stage":"review","next_stage":"done","reviewed":true}`
          checkpoint and re-emission stays a fresh explicit publish decision
          (`variants --slug <slug>`).

    Invalid evidence is a refusal in either class: non-zero, named error, NO
    checkpoint — the dangling-anchor-under-done/reviewed failure (#362) cannot
    recur, and neither can a derived canonical checkpointed over an ancestry pin
    that resolves to nothing. The checkpoint records WHICH class it was written
    on, so "reviewed" never silently means two different things. With
    `--applied 0` the command is a strict no-op: nothing persisted, nothing
    marked, exit 0."""
    if args.applied == 0:
        print(json.dumps({
            "stage": "review-reentry", "applied": 0, "noop": True,
            "reason": "zero applied edits — the draft, map, and variants are "
                      "unchanged; nothing persisted, no variants marked stale, "
                      "no checkpoint written",
        }, indent=2))
        return 0
    if not os.path.isdir(args.ws):
        sys.stderr.write(f"error: run workspace does not exist: {args.ws}\n")
        return 1

    # Precondition (Story 18.21, #496) — the re-entry verdict RECORD. When a
    # rubric-mapped finding was applied, SKILL step 3 re-ran the quality gate
    # over the edited draft; that gate must have PERSISTED its full four-
    # dimension record as the VERSIONED `rubric-verdicts-v2.txt` in this
    # workspace — dim3 with its inventory stamp, dim4 with measured values — the
    # SAME completeness contract the draft-flow gate owes `rubric-verdicts.txt`
    # (#492/Story 18.18). A re-entry may NOT report done/reviewed (PASS) over a
    # missing or partial v2 record: the re-run gate's outcome must be verifiable
    # from an artifact, never asserted in the completion summary's prose alone
    # (the #496 failure — "PASS (all six dimensions)" over an untouched partial
    # dim1/dim2 record). Checked before any product is persisted and before any
    # checkpoint is written; no checkpoint is written on refusal.
    verdicts_v2_path = os.path.join(args.ws, "rubric-verdicts-v2.txt")
    if args.rubric_applied:
        if not os.path.isfile(verdicts_v2_path):
            sys.stderr.write(
                "error: review-reentry: re-entry verdict record not persisted — "
                "a rubric-mapped finding was applied, so the re-run quality gate "
                "must write its full four-dimension record to "
                f"{verdicts_v2_path} (`quality-gate --draft <edited> --map "
                "<rebuilt> --verdicts-out <ws>/rubric-verdicts-v2.txt`) before "
                "re-entry may report done/reviewed. No checkpoint written.\n")
            return 1
        try:
            v2_gaps = _host._verdict_record_gaps(_host._read_text(verdicts_v2_path))
        except OSError as e:
            sys.stderr.write(
                "error: review-reentry: cannot read the re-entry verdict record "
                f"{verdicts_v2_path}: {e}\n")
            return 1
        if v2_gaps:
            sys.stderr.write(
                "error: review-reentry: the re-entry verdict record is partial "
                "— missing " + ", ".join(v2_gaps) + "; the re-run gate must "
                "write all four dimension verdicts (dim3 with its inventory "
                "stamp, dim4 with measured values) to rubric-verdicts-v2.txt "
                "before re-entry may report done/reviewed. No checkpoint "
                "written.\n")
            return 1
        # Freshness (Story 19.15, #751): completeness alone proved acceptable
        # while STALE — re-entry once checkpointed done over a record computed
        # from an older draft version while the newest gate run had failed.
        # The record's attestation must match the edited draft; a record with
        # no attestation (pre-19.15) is treated as partial, never grandfathered.
        v2_sha = _verdict_record_sha(_host._read_text(verdicts_v2_path))
        draft_text_for_sha = _host._read_text(args.draft)
        cur_sha = hashlib.sha256(draft_text_for_sha.encode("utf-8")).hexdigest()
        if v2_sha is None:
            sys.stderr.write(
                "error: review-reentry: the re-entry verdict record carries no "
                "`attestation: draft-sha256=` line (pre-19.15 format) — treated "
                "as partial, never grandfathered; re-run the gate "
                "(`quality-gate --draft <edited> --map <rebuilt> --verdicts-out "
                f"{verdicts_v2_path}`). No checkpoint written.\n")
            return 1
        if v2_sha != cur_sha:
            sys.stderr.write(
                "error: review-reentry: the re-entry verdict record was computed "
                f"from a DIFFERENT draft version (record {v2_sha[:12]}…, edited "
                f"draft {cur_sha[:12]}…) — a stale record never authorizes "
                "done/reviewed; re-run the gate on the edited draft. No "
                "checkpoint written.\n")
            return 1

    # Read the edited draft first: its own frontmatter decides which evidence
    # class this re-entry runs under (Story 18.110, #704), and that decides
    # whether --map is required at all.
    try:
        text = _host._read_text(args.draft)
    except OSError as e:
        sys.stderr.write(
            f"error: review-reentry: cannot read the edited draft: {e}\n")
        return 1
    ancestry_evidence, ancestry_problems = _derived_ancestry_evidence(text)
    evidence_class = "ancestry" if ancestry_evidence is not None else "provenance-map"
    if ancestry_evidence is None and not args.map:
        sys.stderr.write(
            "error: review-reentry: --map is required for an AUTHORED canonical — "
            "it owns its claims, so its re-entry evidence is the provenance map "
            "rebuilt against the edited draft. (A DERIVED canonical, one carrying "
            "`adapted_from`, re-enters on ancestry evidence instead and needs no "
            "map: SPEC-canonical-adaptation CAP-4.) No checkpoint written.\n")
        return 1

    # (a) Persist the reviewed canonical — the completion gate's write path.
    try:
        canonical_path, canonical_sha = _host._persist_canonical(
            text, args.slug, args.root, create_out=getattr(args, "create_out", False),
            ws=getattr(args, "ws", None), owned=True,
            replace=getattr(args, "replace_canonical", False))
    except _host._CanonicalWriteError as e:
        sys.stderr.write(
            "error: review-reentry: reviewed canonical not persisted — "
            f"{e.reason} (path: {e.path})\n")
        return 1

    # (b) Validate the re-entry EVIDENCE — typed by artifact class (Story
    # 18.110, #704). An AUTHORED canonical's evidence is its rebuilt provenance
    # map, validated against the edited draft (anchors required, the
    # `provenance --map --draft` standard). A DERIVED canonical owns no claims
    # of its own (CAP-2), so it carries no map by design; its evidence is its
    # ANCESTRY. Both refuse the same way: non-zero, named, NO checkpoint.
    entries, tally = [], {}
    if ancestry_evidence is not None:
        if ancestry_problems:
            sys.stderr.write(
                "error: review-reentry: invalid-ancestry — this draft is a "
                "DERIVED canonical, so its re-entry evidence is its ancestry "
                "pin, and a done/reviewed checkpoint over an ancestry that does "
                "not resolve is refused (no checkpoint written):\n")
            for pr in ancestry_problems:
                sys.stderr.write(f"  {pr}\n")
            return 1
    else:
        try:
            map_text = _host._read_text(args.map)
        except OSError as e:
            sys.stderr.write(
                f"error: review-reentry: cannot read the rebuilt map: {e}\n")
            return 1
        draft_lines = _host._strip_emission_trailer(text).splitlines()
        try:
            entries = _host.parse_provenance_map(map_text)
            tally, problems = _host._provenance_problems(entries, draft_lines)
        except ValueError as e:
            entries, tally, problems = [], {}, [str(e)]
        if problems:
            sys.stderr.write(
                "error: review-reentry: invalid-provenance-map — the rebuilt map "
                "does not validate against the edited draft, and a done/reviewed "
                "checkpoint over an INVALID map is refused (no checkpoint "
                "written):\n")
            for pr in problems:
                sys.stderr.write(f"  {pr}\n")
            return 1

    # (c) The scoped regression worklist — reported, never run here.
    if ancestry_evidence is not None:
        # A DERIVED canonical's evidence is its ancestry, and the half this
        # command cannot reach — does the pin RESOLVE to a real source at a
        # matching content hash — is reported exactly as verify-provenance is
        # for an authored draft (#704). Calling the lint from here would put the
        # pipeline in reference to adaptation, which CAP-1's boundary forbids.
        required_checks = [{
            "check": "lint-ancestry",
            "reason": "this draft is a DERIVED canonical, so its re-entry "
                      "evidence is its ancestry; the gate verified the pin's "
                      "SHAPE only — run the ancestry lint on this draft to "
                      "confirm it RESOLVES (a real source "
                      "canonical at a matching content hash). The checkpoint is "
                      "written before this runs, by decision at the #704 "
                      "re-triage; an unresolvable pin is this check's to catch",
        }]
    else:
        required_checks = [{
            "check": "verify-provenance",
            "reason": "the draft changed in review, so the prior judge run's "
                      "attestation (Story 13.67) no longer binds to this content "
                      "hash — a FRESH isolated judge must grade the rebuilt map",
        }]
    if args.rubric_applied:
        required_checks.append({
            "check": "quality-gate-mechanical",
            "reason": "a rubric-mapped finding was applied — re-run the "
                      "quality gate's mechanical dimensions on the edited "
                      "draft and PERSIST the full four-dimension verdict record "
                      "(`quality-gate --draft --map --verdicts-out "
                      "<ws>/rubric-verdicts-v2.txt`); re-entry refuses "
                      "done/reviewed over a missing or partial v2 record (#496)",
        })

    # (d) Mark existing variants stale — the staleness comparison, reused,
    # over the just-persisted canonical (its trailer-stripped hash).
    out_dir = os.path.dirname(canonical_path)
    # Discover variants through the profile projection dirs too, not only the
    # drafts root (SPEC-platform-variants placement amendment, #688), so a
    # review-applied canonical edit still marks a projected variant stale.
    variant_paths = []
    for d in _host._variant_scan_dirs(out_dir, args.root):
        variant_paths.extend(
            os.path.join(d, f) for f in sorted(os.listdir(d))
            if f.startswith(f"{args.slug}.") and f.endswith(".md")
            and f != f"{args.slug}.md")
    # UNION with forward-resolved delivered names (#715), same reason as the
    # staleness command's scan: a profile-declared basename is not `<slug>.`
    # prefixed, so a review-applied edit would otherwise leave it ungraded.
    variant_paths.extend(
        p for p in _host._delivered_variant_paths(args.slug, out_dir, args.root)
        if p not in variant_paths)
    staleness = _host._staleness_report(
        open(canonical_path, encoding="utf-8").read(), paths=variant_paths)
    stale_variants = [v for v in staleness["variants"]
                      if v["status"] != "fresh"]

    # (d2) Re-project the article plan (Story 19.17, #757): a round with >=1
    # applied edit re-emits plans/<slug>.md as a deterministic projection of
    # the reviewed canonical — audience mirrored, sections re-derived from the
    # edited draft's headings — through the plan writer's own validation. A
    # projection that FAILS validation refuses the checkpoint (fail-closed);
    # a slug with no plan, or a derived canonical, skips with a note. Zero
    # applied edits never reach this command (the SKILL's zero-edit path
    # hand-writes the checkpoint), so the trigger is simply being here.
    plan_result = None
    if evidence_class == "provenance-map":
        plan_result = _reproject_plan(args.slug, args.root,
                                      open(canonical_path, encoding="utf-8").read(),
                                      args.ws)
        if plan_result.get("failed"):
            sys.stderr.write(
                "error: review-reentry: plan re-projection failed the writer's "
                f"validation — {plan_result['note']}. The reviewed canonical is "
                "persisted, but done/reviewed is refused over a plan the run "
                "knows is stale (Story 19.17, #757). No checkpoint written.\n")
            return 1

    # (e) STOP — nothing is emitted. Write the done/reviewed checkpoint (this
    # command is its only sanctioned writer for a round with applied edits).
    checkpoint_path = _host._checkpoint_path(args.ws)
    tmp = checkpoint_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"stage": "review", "next_stage": _host.DONE_STAGE,
                   "reviewed": True,
                   # Which evidence class this "reviewed" was written on
                   # (#704): a later reader must be able to tell an
                   # ancestry-evidenced review from a provenance-evidenced one.
                   "review_evidence_class": evidence_class}, f, indent=2)
    os.replace(tmp, checkpoint_path)

    out = {
        "stage": "review-reentry",
        "next_stage": _host.DONE_STAGE,
        "slug": args.slug,
        "applied": args.applied,
        "canonical": {"path": canonical_path,
                      "canonical_sha256": canonical_sha},
        "review_evidence_class": evidence_class,
        **({"ancestry_validation": {"ok": True, **ancestry_evidence}}
           if ancestry_evidence is not None else
           {"map_validation": {"ok": True, "entries": len(entries),
                               "tally": tally}}),
        # The rubric's OWN dimension count (from quality-rubric.md) — the
        # completion summary quotes THIS when it reports the quality-gate
        # outcome, never a hardcoded literal (#496: "all six dimensions" over a
        # four-dimension rubric).
        "rubric_dimensions": _rubric_dimension_count(),
        "required_checks": required_checks,
        "stale_variants": stale_variants,
        # Review never emits or re-emits a variant (CAP-3) — re-emission is a
        # fresh explicit publish decision through the standalone variants flow.
        "emitted_variants": [],
        "re_emission": f"variants --slug {args.slug} "
                       "(owner publish decision; skills/draft-article/variants.md)",
        # Story 19.17 (#757): what re-projection did to plans/<slug>.md —
        # relay `changed`/`note` in the completion summary.
        **({"plan_reprojection": plan_result} if plan_result is not None else {}),
        "checkpoint": checkpoint_path,
    }
    # The versioned re-entry verdict record the run persisted (Story 18.21) —
    # its presence-and-completeness was the precondition above, so a done/
    # reviewed re-entry ALWAYS carries a verifiable v2 record path here.
    if args.rubric_applied:
        out["verdicts_v2"] = os.path.abspath(verdicts_v2_path)
    print(json.dumps(out, indent=2))
    return 0


def cmd_review_checkpoint_proposal(args):
    """At review START, surface a one-line CHECKPOINT PROPOSAL when the canonical
    draft is UNTRACKED or DIRTY in its destination (articles) repo — so the owner
    can commit the pre-review state and git becomes the durable before/after
    comparison surface (Story 18.25, #495; SPEC-article-review CAP-6, Alt A).

    The pipeline PROPOSES; the owner COMMITS. This command NEVER writes the
    destination repo — it runs only READ-ONLY git (`rev-parse`, `status`) and
    prints a proposal string for the owner to run (or decline). Declining is
    allowed: the run's in-conversation before/after diff (`review-diff`) still
    shows what review did this run.

    tracked_state in {untracked, dirty, clean, absent, not-a-repo}; a proposal is
    surfaced only for untracked/dirty (clean already has the pre-review state in
    git; the pipeline-proposes/owner-commits stance, hub topics/articles.md
    2026-07-18)."""
    draft = os.path.abspath(args.draft)
    slug = args.slug or os.path.splitext(os.path.basename(draft))[0]

    def emit(state, proposed, proposal, note):
        print(json.dumps({
            "stage": "review-checkpoint-proposal",
            "draft": draft,
            "slug": slug,
            "repo": repo,
            "tracked_state": state,
            "checkpoint_proposed": proposed,
            "proposal": proposal,
            "declinable": True,
            "writes_destination_repo": False,
            "note": note,
        }, indent=2))
        return 0

    repo = _host._git_toplevel(draft)
    if repo is None:
        return emit(
            "not-a-repo", False, None,
            "the draft's destination is not a git working tree — git cannot be "
            "the before/after surface; the in-conversation diff still shows this "
            "run's edits. The pipeline writes nothing.")
    if not os.path.exists(draft):
        return emit(
            "absent", False, None,
            "no canonical draft at the destination path yet — nothing to "
            "checkpoint. The pipeline writes nothing.")

    # READ-ONLY porcelain status for just this file. `??` = untracked; any other
    # non-empty XY = tracked-but-modified (staged and/or worktree); empty = clean.
    r = subprocess.run(
        ["git", "-C", repo, "status", "--porcelain", "--untracked-files=all",
         "--", draft],
        capture_output=True, text=True)
    line = r.stdout.rstrip("\n")
    if line == "":
        return emit(
            "clean", False, None,
            "the canonical draft is committed and unmodified in its destination "
            "repo — git already holds the pre-review state, so no checkpoint is "
            "needed.")
    state = "untracked" if line[:2] == "??" else "dirty"
    try:
        rel = os.path.relpath(draft, repo)
    except ValueError:  # pragma: no cover - different drive on Windows
        rel = draft
    proposal = (f'(cd "{repo}" && git add "{rel}" && '
                f'git commit -m "pre-review checkpoint: {slug}")')
    note = (
        f"the canonical draft is {state} in its destination repo. Proposal only: "
        "run the one-liner above to commit the pre-review state (owner commits; "
        "the pipeline never writes the destination repo — footprint invariant). "
        "Declining is fine — the in-conversation before/after diff still shows "
        "this run's edits.")
    return emit(state, True, proposal, note)


def cmd_review_diff(args):
    """Produce the owner-facing BEFORE/AFTER comparison for an arbitration round
    that applied edits: a unified diff of the pre-arbitration workspace snapshot
    (BEFORE) against the applied draft (AFTER), plus the applied change list —
    both for IN-CONVERSATION display (interaction contract #226; the run-workspace
    snapshot underlies it, artifact paths printed informationally only). Story
    18.25, #495; SPEC-article-review CAP-6.

    Reads only the two inputs; writes NOTHING — never the destination repo, never
    a reviews/ artifact. Emission trailers are stripped so a persistence-only
    hash change never reads as an edit."""
    before = os.path.abspath(args.before)
    after = os.path.abspath(args.after)
    slug = args.slug or os.path.splitext(os.path.basename(after))[0]
    before_text = _host._strip_emission_trailer(_host._read_text(before))
    after_text = _host._strip_emission_trailer(_host._read_text(after))
    before_lines = before_text.splitlines()
    after_lines = after_text.splitlines()

    identical = before_lines == after_lines
    change_list = [] if identical else _diff_change_list(before_lines, after_lines)
    added = sum(len(c["added"]) for c in change_list)
    removed = sum(len(c["removed"]) for c in change_list)

    import difflib
    diff = "" if identical else "".join(difflib.unified_diff(
        [l + "\n" for l in before_lines],
        [l + "\n" for l in after_lines],
        fromfile=f"before/{slug} (pre-arbitration snapshot)",
        tofile=f"after/{slug} (this run's edits)",
        lineterm="\n"))

    out = {
        "stage": "review-diff",
        "before": before,
        "after": after,
        "slug": slug,
        "identical": identical,
        "added": added,
        "removed": removed,
        "diff": diff,
        "change_list": change_list,
        "note": "before/after diff + change list are presented IN-CONVERSATION "
                "(interaction contract #226); the snapshot/draft paths above are "
                "informational only — no artifact is written to the destination "
                "repo. An empty diff means arbitration applied no edit this run.",
    }
    print(json.dumps(out, indent=2, ensure_ascii=False))
    return 0
