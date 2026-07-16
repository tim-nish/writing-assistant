#!/usr/bin/env python3
"""Draft-article pipeline — stage 0 (invocation), Story 4.1.

`draft article <framework> from <sources>` starts the harvest-to-variant flow.
This helper does the mechanical part of stage 0: validate the framework against
the closed allowlist, classify each source token (path / glob / commit-range),
and emit a run-state record that stage 1 (harvest) consumes unmodified.

  start <FRAMEWORK> [SOURCE ...]

  * FRAMEWORK ∈ {F1, F2, F3, F4} (case-insensitive). Anything else is rejected
    with the valid set, a non-zero exit, and NO run-state emitted — no work
    begins, no partial state.
  * Each SOURCE is classified, with this precedence (disambiguation is explicit,
    not assumed):
      1. glob         — contains a glob metacharacter (* ? [ ])
      2. commit-range — `A..B` / `A...B` of ref-like parts, not a relative path
      3. path         — anything else (prefix a literal path with ./ to force it)
  * On success, prints the run-state JSON (framework, framework file, the raw
    sources verbatim, and their classification) and next_stage = harvest.

The recorded sources are a SELECTION for harvest, never a scope widener: stage 1
enumerates the writing-sources-declared files and INTERSECTS this selection, so
an undeclared path passed here cannot expand what gets read.
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

FRAMEWORKS = {
    "f1": "F1-project-introduction.md",
    "f2": "F2-engineering-lessons.md",
    "f3": "F3-evaluation-methodology.md",
    "f4": "F4-research-survey.md",
}

# Owner-facing intent labels (SPEC-draft-article-ux CAP-1, Story 13.27). The
# invocation accepts these; F1-F4 stay valid as the internal/expert alias and
# never appear in owner-facing text. Closed mapping — no fuzzy matching: an
# unknown label is rejected, never guessed.
INTENT_LABELS = {
    "f1": "introduce the project",
    "f2": "share engineering lessons",
    "f3": "explain the evaluation methodology",
    "f4": "survey a research area",
}
INTENT_ALIASES = {
    "introduce-the-project": "f1",
    "project-introduction": "f1",
    "share-engineering-lessons": "f2",
    "engineering-lessons": "f2",
    "explain-the-evaluation-methodology": "f3",
    "evaluation-methodology": "f3",
    "survey-a-research-area": "f4",
    "research-survey": "f4",
}


def resolve_framework(name):
    """Resolve an invocation's article-type argument — an intent label or an
    F1-F4 id — to the canonical framework key, or None if it matches neither."""
    key = re.sub(r"[^a-z0-9]+", "-", name.strip().lower()).strip("-")
    if key in FRAMEWORKS:
        return key
    return INTENT_ALIASES.get(key)
GLOB_RE = re.compile(r"[*?\[\]{}]")
RANGE_RE = re.compile(r"^[A-Za-z0-9_.\-~^@]+\.\.\.?[A-Za-z0-9_.\-~^@/]+$")


def classify(token):
    if GLOB_RE.search(token):
        return "glob"
    # a relative/absolute path is never a commit-range, even with `..` in it
    if not token.startswith(("./", "../", "/")) and RANGE_RE.match(token) and ".." in token:
        return "commit-range"
    return "path"


def plugin_root():
    return os.path.dirname(os.path.dirname(os.path.realpath(__file__)))


def _load(name):
    import importlib.util
    here = os.path.dirname(os.path.realpath(__file__))
    spec = importlib.util.spec_from_file_location(name.replace("-", "_").replace(".py", ""),
                                                  os.path.join(here, name))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# Stage-2 gap-interview question bank (from pipeline-stages.md). Each question
# has a topic aligned with the NEEDS-OWNER topics and a synonym-rich `covers`
# set: if a fact-sheet claim already contains that content, the question is
# redundant (semantic de-dup, not literal-string match) and is suppressed unless
# a NEEDS-OWNER gap re-raises it.
QUESTION_BANK = {
    "q1": {"text": "What surprised you most while building this?", "topic": "surprise",
           "covers": ["surprise", "surprising", "unexpected", "caught us off guard", "to our shock"]},
    "q2": {"text": "Which single result or number matters most, and why that one?", "topic": "significance",
           "covers": ["most important result", "headline number", "key result", "matters most",
                      "flagship metric", "primary metric", "the result that counts"]},
    "q3": {"text": "What would you warn a reader about before they adopt this?", "topic": "warning",
           "covers": ["warning", "caveat", "caution", "pitfall", "limitation", "gotcha", "watch out", "do not use"]},
    "q4": {"text": "What did this decision cost you — what did you give up?", "topic": "tradeoff",
           "covers": ["tradeoff", "trade-off", "cost us", "gave up", "sacrificed", "at the expense of"]},
    "q5": {"text": "Who exactly is this article for, and what should they do after reading?", "topic": "audience",
           "covers": ["intended audience", "written for", "target reader", "this is for", "aimed at", "readers are"]},
    "q6": {"text": "What opinion in this piece are you willing to defend in comments?", "topic": "opinion",
           "covers": ["our opinion", "we argue", "we believe", "hot take", "controversial", "we contend"]},
    "q7": {"text": "What would you do differently if starting over?", "topic": "retrospective",
           "covers": ["in hindsight", "would do differently", "if starting over", "lessons for next time"]},
    # Conditional evidence fallback (SPEC-draft-article-ux CAP-5, Story 13.30):
    # joins the candidate set ONLY when harvest yielded no `number`/`result`
    # fact-sheet entry — the evidence GATE's interview fallback, so the gap
    # surfaces in Stage 2 instead of failing late at Stage 3. Not in any
    # FRAMEWORK_PRIORITY list; cmd_interview inserts it on its condition.
    "q8": {"text": "What result or worked example would convince a skeptical reader?",
           "topic": "significance",
           "covers": ["convincing result", "worked example", "demonstration", "proof point"]},
}

# Owner-facing presentation order (SPEC-draft-article-ux CAP-4, Story 13.30).
# Selection priority (NEEDS-OWNER first, policy seeds, generic; GATE-slot
# tie-break; ≤5 cap) is UNCHANGED — this orders only how the survivors are
# PRESENTED: claim/angle first (the policy-seeded tension question when one
# exists — it reframes every later answer; else the opinion/claim question),
# audience second, then headline/significance, then color (surprise, tradeoff,
# warning, retrospective). The order is contract, not discretion; it is echoed
# in the journal so a mis-ordered run is attributable. Batching within the
# order is free; ordering is not.
_PRESENTATION_SLOTS = {"opinion": 0, "audience": 1, "significance": 2}


def presentation_slot(rec):
    """0 = claim/angle, 1 = audience, 2 = headline/significance, 3 = color."""
    if rec.get("rationale") == "policy-seed":
        return 0
    return _PRESENTATION_SLOTS.get(rec.get("topic"), 3)

# Per-framework question priority, ORDERED by that framework's GATE slots (not
# question-bank order) — so the same fact sheet yields a stable, framework-
# tailored interview and the ordering is the deterministic tie-break under the
# ≤5 cap.
#
# Invariant: every framework's list contains q2 (significance — the claim the
# article exists to communicate) and q5 (audience). They are the review skill's
# intent anchors: the cold-read pass compares its reader answers against the
# journal's q2/q5 entries, so a framework that never asks them would make that
# comparison unexecutable (issue #120).
FRAMEWORK_PRIORITY = {
    "F1": ["q2", "q4", "q3", "q5", "q1"],   # evidence GATE, decision cost, limits, audience, surprise
    "F2": ["q1", "q4", "q3", "q2", "q5"],   # what-happened, mechanism/cost, applicability, significance, audience
    "F3": ["q2", "q3", "q4", "q5", "q6"],   # what-it-caught, cannot-tell, tradeoff, audience, opinion
    "F4": ["q6", "q2", "q3", "q5", "q1"],   # my-take opinion, significance, warning, audience, surprise
}
QUESTION_BUDGET = 5

# Stage-3 `[VERIFY]` marker contract. The canonical marker is exactly
# `[VERIFY: <reason>]` — an inferred claim carries one naming WHY it is
# unverified. Stage 4 (resolve markers) and the lint (5.1) match this exact
# form, so the format is machine-detectable and non-negotiable.
VERIFY_CANDIDATE = re.compile(r"\[VERIFY\b[^\]]*\]", re.IGNORECASE)
VERIFY_CANONICAL = re.compile(r"^\[VERIFY: [^\]]+\]$")

# Stage-4 rewrite budget (Story 4.5). The verification pass allows ONE rewrite
# per section; a section needing more than that routes back into a new interview
# question instead of open-ended editing (SPEC-article-draft-pipeline constraint:
# "A section needing more than one rewrite routes back to a new interview
# question, never into open-ended editing.").
REWRITE_BUDGET = 1


# Stage-3 sidecar provenance map (Story 11.1; `docs/harness-architecture.md` D1).
# Every draft sentence belongs to exactly one provenance class:
#   sourced   — asserts something traceable to ONE fact-sheet entry or interview
#               answer; carries that pointer;
#   derived   — a synthesis over >=2 named sourced claims (compress / combine /
#               restate); inherits ALL their pointers;
#   narration — asserts nothing checkable (falsifiability test, D2); no pointer;
#   verify    — an inferred claim beyond sources/derivation; carries an inline
#               [VERIFY] marker in the draft body (no pointer in the map).
# The map lives in the run workspace, never inline, so the draft body stays clean
# for variants and review. This command parses and STRUCTURALLY validates the map
# (pointer-count rules per class); the independent `verify-provenance` check
# (Story 11.2) adds the semantic layer (falsifiability + the six forbidden
# derivation categories).
PROV_CLASSES = ("sourced", "derived", "narration", "verify")
PROV_LINE = re.compile(
    r"^(?P<pos>\S+):\s*(?P<cls>sourced|derived|narration|verify)"
    r"(?:\s*<-\s*(?P<ptrs>.+?))?\s*$"
)


def parse_provenance_map(text):
    """Parse the sidecar map text into [(pos, cls, [pointers])], raising
    ValueError on a malformed line or a class name outside the closed set."""
    entries = []
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = PROV_LINE.match(line)
        if not m:
            raise ValueError(f"line {lineno}: malformed provenance entry: {raw!r}")
        ptrs = [p.strip() for p in (m.group("ptrs") or "").split(",") if p.strip()]
        entries.append((m.group("pos"), m.group("cls"), ptrs))
    return entries


def cmd_provenance(args):
    """Stage 3: parse and structurally validate the sidecar provenance map
    (Story 11.1). Enforces the per-class pointer contract:

      - sourced   → exactly-traceable: >=1 pointer;
      - derived   → synthesis over >=2 named sourced claims: >=2 pointers;
      - narration → asserts nothing: 0 pointers;
      - verify    → inferred, marked inline in the draft: 0 pointers here.

    --count prints the per-class tallies (dimension-4 quote-density reads these).
    A structural violation exits non-zero; the semantic checks live in
    `verify-provenance` (Story 11.2).
    """
    text = sys.stdin.read() if args.map == "-" else open(args.map, encoding="utf-8").read()
    try:
        entries = parse_provenance_map(text)
    except ValueError as e:
        sys.stderr.write(f"error: {e}\n")
        return 1

    tally = {c: 0 for c in PROV_CLASSES}
    problems = []
    for pos, cls, ptrs in entries:
        tally[cls] += 1
        if cls == "sourced" and len(ptrs) < 1:
            problems.append(f"{pos}: sourced claim carries no pointer")
        elif cls == "derived" and len(ptrs) < 2:
            problems.append(f"{pos}: derived claim must inherit >=2 pointers (got {len(ptrs)})")
        elif cls in ("narration", "verify") and ptrs:
            problems.append(f"{pos}: {cls} must carry no pointer (got {len(ptrs)})")

    if args.count:
        print(json.dumps(tally))
        return 0
    if problems:
        sys.stderr.write("provenance map INVALID:\n")
        for p in problems:
            sys.stderr.write(f"  {p}\n")
        return 1
    print(f"provenance map OK: {json.dumps(tally)}")
    return 0


# Stage-3→4 quality gate (Story 11.4; `docs/harness-architecture.md` D3–D5).
# Dimension 4 (readability mechanics) is checked here MECHANICALLY (zero tokens);
# dimensions 1–3 are judged by one single-pass cheap-tier rubric judge whose
# pass/fail verdicts this command consumes. The gate is a stage-progression
# PRECONDITION, not an advisory finding: any failing dimension blocks stage 4.
# Conservative v1 thresholds live in the rubric asset (skills/draft-article/
# quality-rubric.md); mirror them here.
QG_MEAN_SENTENCE_WORDS = 30
QG_LONG_SENTENCE_WORDS = 40
QG_LONG_SENTENCE_FRACTION = 0.25
QG_PARA_MAX_SENTENCES = 8
QG_PARA_MAX_WORDS = 160
QG_STITCH_SOURCED_FRACTION = 0.70
_SENT_SPLIT = re.compile(r"(?<=[.!?])\s+")


def _draft_body(text):
    """Strip YAML frontmatter and heading lines; return prose paragraphs."""
    if text.startswith("---"):
        parts = text.split("\n---", 1)
        if len(parts) == 2:
            text = parts[1]
    lines = [ln for ln in text.splitlines() if not ln.lstrip().startswith("#")]
    blocks, cur = [], []
    for ln in lines:
        if ln.strip() == "":
            if cur:
                blocks.append(" ".join(cur)); cur = []
        else:
            cur.append(ln.strip())
    if cur:
        blocks.append(" ".join(cur))
    return blocks


def _sentences(paragraph):
    return [s for s in _SENT_SPLIT.split(paragraph.strip()) if s.strip()]


def _dimension4(draft_text, prov_entries):
    """Mechanical readability-mechanics checks; returns a list of failing
    locations (empty = pass)."""
    fails = []
    paragraphs = _draft_body(draft_text)
    sentences = [s for p in paragraphs for s in _sentences(p)]
    if sentences:
        lens = [len(s.split()) for s in sentences]
        mean = sum(lens) / len(lens)
        if mean > QG_MEAN_SENTENCE_WORDS:
            fails.append(f"sentence length: mean {mean:.0f} words > {QG_MEAN_SENTENCE_WORDS}")
        long = sum(1 for n in lens if n > QG_LONG_SENTENCE_WORDS)
        if long / len(lens) > QG_LONG_SENTENCE_FRACTION:
            fails.append(f"sentence length: {long}/{len(lens)} sentences over {QG_LONG_SENTENCE_WORDS} words")
    for i, p in enumerate(paragraphs):
        ns, nw = len(_sentences(p)), len(p.split())
        if ns > QG_PARA_MAX_SENTENCES or nw > QG_PARA_MAX_WORDS:
            fails.append(f"paragraph {i + 1}: {ns} sentences / {nw} words (wall of text)")
    if "## " not in draft_text and "\n#" not in draft_text:
        fails.append("heading density: no section headings")
    # Stitched-fact-sheet signature: wall-to-wall sourced claims, no
    # derived/narration connective tissue (reads the provenance map).
    if prov_entries:
        classes = [c for _, c, _ in prov_entries]
        total = len(classes)
        sourced = classes.count("sourced")
        tissue = classes.count("derived") + classes.count("narration")
        if tissue == 0 and sourced > 0:
            fails.append("stitched fact sheet: all sourced claims, no derived/narration tissue")
        elif total and sourced / total > QG_STITCH_SOURCED_FRACTION and tissue == 0:
            fails.append(f"stitched fact sheet: {sourced}/{total} sourced, no connective tissue")
    return fails


def cmd_quality_gate(args):
    """Stage 3→4 quality gate (Story 11.4). Dimension 4 is mechanical here;
    dimensions 1–3 come from the single-pass judge's verdicts (--judge, a file of
    `dim1|dim2|dim3: pass|fail [locations]`). Emits a per-dimension verdict; a
    non-zero exit BLOCKS stage 4 (a precondition, not an advisory finding).
    """
    draft = sys.stdin.read() if args.draft == "-" else open(args.draft, encoding="utf-8").read()
    prov_entries = []
    if args.map:
        try:
            prov_entries = parse_provenance_map(_read_text(args.map))
        except ValueError as e:
            sys.stderr.write(f"error: provenance map: {e}\n")
            return 2

    results = {}
    # Dimensions 1–3: judge verdicts.
    judged = {}
    if args.judge:
        for ln in _read_text(args.judge).splitlines():
            ln = ln.strip()
            if not ln or ln.startswith("#"):
                continue
            dim, _, rest = ln.partition(":")
            judged[dim.strip()] = rest.strip()
    for dim in ("dim1", "dim2", "dim3"):
        verdict = judged.get(dim, "")
        passed = verdict.lower().startswith("pass")
        results[dim] = ("pass" if passed else "fail",
                        "" if passed else (verdict[4:].strip(" :-") if verdict else "no judge verdict"))
    # Dimension 4: mechanical.
    d4 = _dimension4(draft, prov_entries)
    results["dim4"] = ("pass", "") if not d4 else ("fail", "; ".join(d4))

    # Audience presence — a stage-progression precondition (Story 13.41,
    # SPEC-platform-variants CAP-4). `audience` is born at stage-3 fill, so this
    # gate is where presence is enforceable on a fresh run; the variant stage's
    # hard stop remains as backstop. Mechanical: frontmatter parse only.
    try:
        fields, _ = _read_frontmatter(draft)
    except SystemExit:
        fields = {}
    aud = fields.get("audience")
    if not aud or aud == "{audience}":
        results["audience"] = ("fail",
                               "frontmatter `audience` missing or unfilled — set the named "
                               "reader at stage-3 fill (from the interview's audience answer, "
                               "the backlog item, or the draft-start declaration)")
    else:
        results["audience"] = ("pass", "")

    failing = [d for d, (v, _) in results.items() if v == "fail"]
    out = {"gate": "quality", "pass": not failing,
           "dimensions": {d: {"verdict": v, "locations": loc} for d, (v, loc) in results.items()},
           "failing_dimensions": failing}
    print(json.dumps(out, indent=2))
    return 0 if not failing else 1


def _read_text(path):
    return sys.stdin.read() if path == "-" else open(path, encoding="utf-8").read()


def _load_json_state(path, label):
    """Read `path` (`-` == stdin) and parse it as JSON, raising SystemExit with a
    named, actionable message instead of an opaque traceback when the input is
    empty or malformed. An empty capture is the common case — a prior stage that
    produced no output piped into the next — so it gets its own clear diagnostic
    rather than a bare JSONDecodeError."""
    text = _read_text(path)
    if not text.strip():
        raise SystemExit(
            f"error: {label} produced no output (empty input from "
            f"{'stdin' if path == '-' else path}) — the prior stage wrote nothing"
        )
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        raise SystemExit(f"error: {label} is not valid JSON: {e}")


def cmd_verify_markers(args):
    """Stage 3/4: validate the `[VERIFY: reason]` markers in a draft. Every
    VERIFY-shaped bracket must match the canonical form exactly; anything else
    (bare `[VERIFY]`, empty reason, wrong case, missing colon) is malformed.
    --count prints the number of well-formed markers (Stage 4 drives it to zero).
    """
    text = sys.stdin.read() if args.draft == "-" else open(args.draft, encoding="utf-8").read()
    candidates = VERIFY_CANDIDATE.findall(text)
    well = [c for c in candidates if VERIFY_CANONICAL.match(c)]
    malformed = [c for c in candidates if not VERIFY_CANONICAL.match(c)]

    if args.count:
        print(len(well))
        return 0
    for c in well:
        print(f"VALID     {c}")
    for c in malformed:
        print(f"MALFORMED {c}   (must be exactly `[VERIFY: <reason>]`)")
    print(f"\n{len(well)} well-formed, {len(malformed)} malformed.")
    return 1 if malformed else 0


def cmd_verify(args):
    """Stage 4: build the owner's verification worklist — one entry per
    well-formed `[VERIFY: reason]` marker, carrying its line and the reason so
    the owner resolves each to a source, a confirmation, or deletion. The pass
    is complete (next_stage = variants) only when zero markers remain; any
    malformed marker blocks the pass (Stage 3 must have produced canonical ones).
    """
    text = sys.stdin.read() if args.draft == "-" else open(args.draft, encoding="utf-8").read()
    worklist = []
    for lineno, line in enumerate(text.splitlines(), 1):
        for m in VERIFY_CANDIDATE.finditer(line):
            frag = m.group(0)
            if not VERIFY_CANONICAL.match(frag):
                sys.stderr.write(
                    f"error: malformed marker at line {lineno}: {frag}   "
                    "(must be exactly `[VERIFY: <reason>]`; resolve Stage 3 first)\n"
                )
                return 1
            worklist.append({"line": lineno, "marker": frag,
                             "reason": frag[len("[VERIFY: "):-1]})
    remaining = len(worklist)
    out = {
        "stage": "verify",
        # The pass exits to Stage 5 only when every marker is resolved.
        "next_stage": "variants" if remaining == 0 else "verify",
        "remaining": remaining,
        "worklist": worklist,
    }
    print(json.dumps(out, indent=2))
    return 0


def cmd_reroute(args):
    """Stage 4 constraint: a section needing more than one rewrite routes back to
    a NEW interview question rather than open-ended editing. Given the rewrites
    already applied to a section, decide `edit` (the one allowed pass-time
    rewrite) or `reroute` — the latter emits a bounded interview question that
    re-enters Stage 2's answer capture instead of continuing to edit.
    """
    if args.rewrites < 0:
        sys.stderr.write("error: --rewrites must be >= 0\n")
        return 2
    if args.rewrites < REWRITE_BUDGET:
        out = {
            "stage": "verify",
            "section": args.section,
            "rewrites": args.rewrites,
            "decision": "edit",
            "remaining_edits": REWRITE_BUDGET - args.rewrites,
        }
    else:
        out = {
            "stage": "verify",
            "section": args.section,
            "rewrites": args.rewrites,
            "decision": "reroute",
            "next_stage": "interview",
            "reason": ("past the one allowed rewrite; route to a new interview "
                       "question, not open-ended editing"),
            "question": {
                "id": f"reroute:{args.section}",
                "text": (f"Section {args.section!r} still needs change after one "
                         "rewrite. In a bullet: what exactly should it say, and "
                         "what source or fact supports that?"),
                "from_reroute": True,
            },
        }
    print(json.dumps(out, indent=2))
    return 0


def _read_frontmatter(text):
    """Parse the leading `---` article frontmatter into a dict. Stdlib-only
    line surgery (host repos have no PyYAML): top-level `key: value` pairs, with
    `[a, b]` lists split and a folded `key: >` block collapsing its indented
    continuation lines. Returns (fields, body) — body is everything after the
    closing fence, verbatim (the full article text).
    """
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        raise SystemExit("error: draft has no `---` frontmatter block")
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        raise SystemExit("error: draft frontmatter is not closed with `---`")

    fields = {}
    i = 1
    while i < end:
        line = lines[i]
        m = re.match(r"^([A-Za-z_][\w-]*):\s*(.*)$", line)
        if not m:
            i += 1
            continue
        key, val = m.group(1), m.group(2).strip()
        if val in (">", "|"):                       # folded/literal block
            block = []
            i += 1
            while i < end and (lines[i].startswith((" ", "\t")) or lines[i].strip() == ""):
                if lines[i].strip():
                    block.append(lines[i].strip())
                i += 1
            fields[key] = " ".join(block)
            continue
        if val.startswith("[") and val.endswith("]"):
            inner = val[1:-1].strip()
            fields[key] = [t.strip().strip('"\'') for t in inner.split(",") if t.strip()]
        else:
            fields[key] = val.strip().strip('"\'')
        i += 1

    body = "\n".join(lines[end + 1:]).lstrip("\n")
    return fields, body


# --------------------------------------------------------------------------
# Profile-driven variant projection (Story 16.3, SPEC-platform-variants CAP-4).
#
# A variant is a PROJECTION of the canonical draft: the body carries over
# unchanged (claims, evidence, provenance, section structure), and the
# frontmatter is rendered from the platform PROFILE's `packaging`, never from a
# per-platform code path. There is no per-platform function and no builder table
# — one field-renderer registry keyed by field NAME serves every platform, so
# adding a platform is a profile file (Story 16.1) and zero stage-code change.
# --------------------------------------------------------------------------

# Fenced ```mermaid block, used by the profile-declared visual treatment.
_MERMAID_FENCE = re.compile(r"^```mermaid[^\n]*\n.*?^```[^\n]*$", re.MULTILINE | re.DOTALL)


def _sanitize_tags(topics, cap):
    """Lowercase-alphanumeric, de-duplicated, capped at the profile's tag_cap."""
    out = []
    for t in topics or []:
        clean = re.sub(r"[^a-z0-9]", "", str(t).lower())
        if clean and clean not in out:
            out.append(clean)
    return out[:cap] if cap else out


def _canonical_url(fields, packaging, owner_values):
    """Compose canonical_url per packaging.canonical_url (WHERE/FORMAT); the base
    VALUE is an owner value from user config (never duplicated in the profile).
    Returns None when the profile declares `policy: none` (a repo-sync-canonical
    platform, whose variant carries no canonical_url)."""
    cu = packaging.get("canonical_url") or {}
    if cu.get("policy") in (None, "none", "None"):
        return None
    base = owner_values.get("canonical_url_base") or "{site_url}/articles"
    fmt = cu.get("format", "{base}/{slug}")
    return fmt.replace("{base}", base).replace("{slug}", fields.get("slug", "{slug}"))


def _render_field(field, fields, packaging, owner_values):
    """Render one frontmatter line for a profile-declared field NAME (platform-
    agnostic). Returns the line, or None to omit the field."""
    cap = packaging.get("tag_cap")
    if field == "slug":
        return f"slug: {fields.get('slug', '{slug}')}"
    if field == "title":
        return f'title: "{fields.get("title", "{title}")}"'
    if field == "date":
        return f"date: {fields.get('date', '{date}')}"
    if field == "language":
        return f"language: {fields.get('language', '')}"
    if field == "published":
        return "published: false"           # a variant is always emitted unpublished
    if field == "description":
        return f"description: {fields.get('summary', '')}"
    if field == "summary":
        return f"summary: {fields.get('summary', '')}"
    if field == "tags":
        return f"tags: {', '.join(_sanitize_tags(fields.get('topics'), cap))}"
    if field == "topics":
        tags = _sanitize_tags(fields.get("topics"), cap)
        return "topics: [" + ", ".join(f'"{t}"' for t in tags) + "]"
    if field == "emoji":
        return 'emoji: "📝"'                 # placeholder — owner may change
    if field == "type":
        return 'type: "tech"'
    if field == "canonical_url":
        cu = _canonical_url(fields, packaging, owner_values)
        return f"canonical_url: {cu}" if cu else None
    # Unknown field: pass the draft's value through if present, else omit.
    val = fields.get(field)
    return f"{field}: {val}" if val is not None else None


def _apply_visuals(body, treatment):
    """Apply the profile-declared diagram treatment (SPEC-article-visuals CAP-5),
    driven by `packaging.visuals` — never a per-platform branch. Returns
    (body, blocked): `blocked` is True when a render publish blocker was raised."""
    if treatment in (None, "", "mermaid-embedded"):
        return body, False               # platform renders Mermaid inline
    if treatment == "html-comment-blocked":
        if not _MERMAID_FENCE.search(body):
            return body, False
        def _wrap(m):
            return ("<!-- render blocker: this platform does not render Mermaid; "
                    "replace with a rendered image before publishing.\n"
                    + m.group(0) + "\n-->")
        return _MERMAID_FENCE.sub(_wrap, body), True
    return body, False                   # unknown treatment: leave body, no claim


def _project_variant(fields, body, profile, owner_values):
    """Project the canonical draft through a platform profile → (content, blocked).
    Frontmatter from packaging.frontmatter; body carried over unchanged but for
    the declared visual treatment."""
    packaging = profile.get("packaging", {}) or {}
    fm = ["---"]
    for field in packaging.get("frontmatter", []) or []:
        line = _render_field(field, fields, packaging, owner_values)
        if line is not None:
            fm.append(line)
    fm.append("---")
    body_out, blocked = _apply_visuals(body, packaging.get("visuals"))
    return "\n".join(fm) + "\n\n" + body_out.rstrip() + "\n", blocked


def _git_toplevel():
    """realpath of the git toplevel of cwd, or None (mirrors the resolvers)."""
    r = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                       capture_output=True, text=True)
    top = r.stdout.strip()
    return os.path.realpath(top) if r.returncode == 0 and top else None


def _resolve_drafts_dir(root):
    """Resolve output.drafts via resolve-writing-sources.py (Story 1.3). Exit 3
    there means the location is undeclared — surface that, no silent default."""
    here = os.path.dirname(os.path.realpath(__file__))
    cmd = [sys.executable, os.path.join(here, "resolve-writing-sources.py")]
    if root:
        cmd += ["--root", root]
    cmd.append("draft-location")
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode == 3:
        raise SystemExit("error: output.drafts is undeclared in writing-sources.yaml; "
                         "declare it (resolve-writing-sources.py set-draft-location) "
                         "or pass --out")
    if r.returncode != 0:
        raise SystemExit(r.stderr.strip() or "error: could not resolve output.drafts")
    return r.stdout.strip()


def cmd_variants(args):
    """Stage 5: emit platform-ready variants of a VERIFIED draft as PROJECTIONS
    of the canonical draft through declared platform profiles (Story 16.3). Which
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
    text = sys.stdin.read() if args.draft == "-" else open(args.draft, encoding="utf-8").read()

    # Precondition: a verified draft carries zero well-formed [VERIFY] markers.
    unresolved = [c for c in VERIFY_CANDIDATE.findall(text) if VERIFY_CANONICAL.match(c)]
    if unresolved:
        sys.stderr.write(f"error: draft still has {len(unresolved)} unresolved [VERIFY] "
                         "marker(s); complete Stage 4 before emitting variants\n")
        return 1

    fields, body = _read_frontmatter(text)
    lang = fields.get("language")
    if not lang:
        sys.stderr.write("error: draft frontmatter has no `language`; cannot pick a variant policy\n")
        return 1

    # Config drives WHICH platforms + the canonical policy; profiles drive HOW.
    rf = _load("render-frontmatter.py")
    cfg_args = argparse.Namespace(config_json=args.config_json, root=args.root,
                                  global_config=args.global_config, repo_config=args.repo_config)
    cfg = rf.load_config(cfg_args)
    policy = cfg.get("syndication", {}).get("policy", {}).get(lang)
    if not policy:
        sys.stderr.write(f"error: no syndication.policy for language {lang!r} in config\n")
        return 1
    owner_variants = cfg.get("syndication", {}).get("variants", {})
    available = list(policy.get("variants", []))

    # Emission is per explicit publish decision (Story 16.4, CAP-3): the pipeline
    # NEVER auto-emits all configured platforms. The owner's choice arrives as
    # --platforms (a subset of `available`); `--list-platforms` (or no choice at
    # all) reports the choices for the in-conversation selection and emits
    # nothing. `--platforms all` is an explicit opt-in to every configured one.
    if getattr(args, "list_platforms", False) or not getattr(args, "platforms", None):
        print(json.dumps({"stage": "variants", "language": lang,
                          "mode": policy.get("mode"), "available": available,
                          "emitted": [], "written": False,
                          "note": "choose platforms to emit with --platforms "
                                  "<ids|all>; nothing is auto-emitted"}, indent=2))
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

    # The canonical draft's content hash is recorded with every emitted variant
    # (embedded + reported) so stale-variant detection (Story 16.7) can tell when
    # a variant's source draft has moved since emission.
    canonical_sha = hashlib.sha256(text.encode("utf-8")).hexdigest()

    # Resolve platform profiles — the single declaration source (no builder table).
    pp = _load("resolve-platform-profiles.py")
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
    out_dir = args.out if args.out else _resolve_drafts_dir(args.root)

    # A config-resolved output.drafts OUTSIDE the host repo (the recommended
    # home — a private articles repo, #213) is never silently scaffolded:
    # creating directory trees outside the host needs explicit consent
    # (--create-out, given after the skill asks the owner). Inside the host,
    # creation stays automatic — and an explicit --out IS the consent.
    if not args.dry_run and not args.out and not os.path.isdir(out_dir):
        host = os.path.realpath(args.root) if args.root else _git_toplevel()
        inside_host = host and os.path.realpath(out_dir).startswith(host + os.sep)
        if not inside_host and not args.create_out:
            sys.stderr.write(
                f"error: output.drafts resolves outside the host repo to {out_dir}, "
                "which does not exist. Create it yourself, or re-run with "
                "--create-out after confirming the location with the owner.\n")
            return 1

    emitted = []
    blockers = []
    lede_proposals = []
    for name in chosen:
        profile = profiles.get(name)
        if not profile:
            sys.stderr.write(
                f"error: no platform profile for configured variant {name!r}. "
                f"Add `{name}.yaml` under {pdir} "
                "(see config/platform-profiles/*.example.yaml).\n")
            return 1
        # Lede-retarget trigger (Story 16.5): a DETERMINISTIC comparison of the
        # declared `audience`/`language` — draft vs profile. Inequality on either
        # calls for exactly one judgment step (re-targeting the lede/framing to
        # the profile's named reader; です/ます for `ja`), presented to the owner
        # as a proposal — the variant's only owner touchpoint. Equality means
        # pure packaging, no proposal. The trigger is never agent judgment over
        # content, and there is no `lede_retarget` profile override field.
        retarget = (draft_audience != profile.get("audience")
                    or lang != profile.get("language"))
        content, blocked = _project_variant(fields, body, profile,
                                            owner_variants.get(name, {}))
        # Emission metadata: the canonical draft's hash rides with the variant
        # (an unobtrusive trailing comment both platforms ignore) so Story 16.7
        # can detect a variant whose source draft has since changed.
        content = content.rstrip("\n") + \
            f"\n\n<!-- writing-assistant: canonical-sha256={canonical_sha} -->\n"
        path = os.path.join(out_dir, f"{slug}.{name}.md")
        if not args.dry_run:
            os.makedirs(out_dir, exist_ok=True)
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
                "draft_audience": draft_audience, "draft_language": lang,
                "profile_audience": profile.get("audience"),
                "profile_language": profile.get("language"),
                "register": "です/ます" if profile.get("language") == "ja" else None,
            })

    out = {
        "stage": "variants",
        "next_stage": "review",           # draft exits into SPEC-article-review
        "language": lang,
        "mode": policy.get("mode"),
        "available": available,
        "chosen": chosen,                 # the owner's explicit publish decision
        "emitted": emitted,
        "written": not args.dry_run,
    }
    if blockers:
        out["render_blockers"] = blockers
    if lede_proposals:
        out["lede_proposals"] = lede_proposals   # SKILL presents one per variant
    print(json.dumps(out, indent=2))
    return 0


_CANONICAL_SHA = re.compile(r"canonical-sha256=([0-9a-f]{64})")


def cmd_variant_staleness(args):
    """Detect stale variants (Story 16.7, SPEC-platform-variants constraint
    "variants are views"). Each variant carries the canonical draft's content
    hash at emission (Story 16.4); this compares that recorded hash against the
    CURRENT canonical draft. A variant whose source draft has changed since
    emission is a **publish blocker** (CAP-6 bucket) — never a silent
    inconsistency. A wanted change routes to the canonical draft first, then the
    variant is re-emitted: re-emission records the new hash and clears the
    blocker. A variant with no recorded hash cannot be verified fresh and is a
    blocker too (re-emit to record one).
    """
    text = sys.stdin.read() if args.draft == "-" else open(args.draft, encoding="utf-8").read()
    canonical_sha = hashlib.sha256(text.encode("utf-8")).hexdigest()

    if args.variants:
        paths = list(args.variants)
    else:
        out_dir = args.out if args.out else _resolve_drafts_dir(args.root)
        slug = None
        try:
            fields, _ = _read_frontmatter(text)
            slug = fields.get("slug")
        except SystemExit:
            slug = None
        pattern = f"{slug}." if slug else ""
        paths = [os.path.join(out_dir, f) for f in sorted(os.listdir(out_dir))
                 if f.startswith(pattern) and f.endswith(".md")] if os.path.isdir(out_dir) else []

    variants, publish_blockers = [], []
    for path in paths:
        platform = os.path.basename(path).split(".")[-2] if path.endswith(".md") \
            and len(os.path.basename(path).split(".")) >= 3 else None
        try:
            content = open(path, encoding="utf-8").read()
        except OSError:
            continue
        m = _CANONICAL_SHA.search(content)
        recorded = m.group(1) if m else None
        if recorded is None:
            status = "unrecorded"
        elif recorded == canonical_sha:
            status = "fresh"
        else:
            status = "stale"
        entry = {"path": path, "platform": platform, "status": status,
                 "recorded_sha256": recorded}
        variants.append(entry)
        if status != "fresh":
            publish_blockers.append({
                "platform": platform, "path": path,
                "blocker": "stale-variant" if status == "stale" else "unrecorded-canonical-hash",
                "detail": ("the canonical draft changed since this variant was emitted; "
                           "route the change to the draft and re-emit"
                           if status == "stale"
                           else "no recorded canonical hash; re-emit to record one"),
            })

    out = {
        "stage": "variant-staleness",
        "canonical_sha256": canonical_sha,
        "variants": variants,
    }
    if publish_blockers:
        out["publish_blockers"] = publish_blockers
    print(json.dumps(out, indent=2))
    return 0


def cmd_site_record(args):
    """Propose the site's `mode: external` record AFTER the owner publishes an
    external-canonical variant (Story 16.9, FR62). The record is not a variant
    and no platform profile is consulted — the site is owner identity, not a
    platform. Its load-bearing field (the final published URL) exists only after
    the publish event, so this is a post-publish, post-budget step: without a
    confirmed `--url` it reports the offer as pending (re-runnable — the offer is
    never dropped); with one it builds a ready-to-paste record conforming to the
    user-config site frontmatter schema and writes the PROPOSAL to the run
    workspace only — never the site tree (applying it is the owner's act).
    """
    text = sys.stdin.read() if args.draft == "-" else open(args.draft, encoding="utf-8").read()
    fields, _ = _read_frontmatter(text)
    lang = fields.get("language")
    if not lang:
        sys.stderr.write("error: draft frontmatter has no `language`\n")
        return 1

    rf = _load("render-frontmatter.py")
    cfg_args = argparse.Namespace(config_json=args.config_json, root=args.root,
                                  global_config=args.global_config, repo_config=args.repo_config)
    cfg = rf.load_config(cfg_args)
    mode = (cfg.get("syndication", {}).get("policy", {}).get(lang, {}) or {}).get("mode")
    if mode != "external":
        print(json.dumps({"stage": "site-record", "language": lang, "mode": mode,
                          "applicable": False,
                          "note": f"language {lang!r} is canonical on the site; "
                                  "no external record is needed"}, indent=2))
        return 0

    # Site-record schema constants come from the owner's `site_record` block in
    # user config (Story 16.1 routing: the external-record schema is owner-site
    # identity, not platform packaging). Absent → the ratified defaults.
    site_rec = cfg.get("site_record") or {}
    max_lines = site_rec.get("external_record_max_lines", 20)
    body_forbidden = site_rec.get("body_forbidden", True)

    if not args.url:
        print(json.dumps({"stage": "site-record", "language": lang, "mode": "external",
                          "applicable": True, "url_confirmed": False,
                          "note": "confirm the final published URL to generate the site "
                                  "record — re-run with --url; the offer persists until then"},
                         indent=2))
        return 0

    schema = (cfg.get("frontmatter", {}) or {}).get("schema", []) or []
    slug = fields.get("slug") or "draft"
    pub_date = args.date or fields.get("date") or "{date}"
    related_keys = (cfg.get("frontmatter", {}) or {}).get("related_keys",
                                                          ["projects", "publications", "products"])

    def field_line(name):
        if name == "mode":
            return "mode: external"
        if name == "slug":
            return f"slug: {slug}"
        if name == "title":
            return f'title: "{fields.get("title", "{title}")}"'
        if name == "date":
            return f"date: {pub_date}"          # the REAL publication date
        if name == "language":
            return f"language: {lang}"
        if name == "summary":
            return f"summary: {fields.get('summary', '')}"
        if name == "topics":
            return "topics: [" + ", ".join(fields.get("topics", []) or []) + "]"
        if name == "related":
            return "related: { " + ", ".join(f"{k}: []" for k in related_keys) + " }"
        # audience and any non-site field are never emitted into the record.
        return None

    lines = ["---"]
    for name in schema:
        line = field_line(name)
        if line is not None:
            lines.append(line)
    lines.append(f"canonical_url: {args.url}")   # index-facing pointer to the published copy
    lines.append("---")
    record = "\n".join(lines) + "\n"             # body forbidden — no body follows

    proposal_path = None
    if args.ws:
        proposal_path = os.path.join(args.ws, f"site-record.{slug}.md")
        try:
            with open(proposal_path, "w", encoding="utf-8") as fh:
                fh.write(record)
        except OSError as exc:  # pragma: no cover - defensive
            sys.stderr.write(f"warning: could not write site-record proposal: {exc}\n")
            proposal_path = None

    out = {
        "stage": "site-record",
        "language": lang, "mode": "external",
        "applicable": True, "url_confirmed": True, "url": args.url,
        "lines": len(lines), "max_lines": max_lines, "body_forbidden": body_forbidden,
        "over_line_budget": len(lines) > max_lines,
        "proposal_path": proposal_path,
        "record": record,
        "note": "proposal only — apply it to the site yourself (or via a site-side "
                "command); the pipeline never writes the site tree",
    }
    print(json.dumps(out, indent=2, ensure_ascii=False))
    return 0


def cmd_interview(args):
    """Stage 2: triage every candidate question against the harvest output
    (fact sheet + NEEDS-OWNER) into exactly one of three outcomes, then present
    the surviving (non-suppressed) ones, at most 5, prioritized by the
    framework's GATE slots with confirmed NEEDS-OWNER gaps first.

    Three-outcome triage (Story 10.2; `docs/interview-architecture.md` D1),
    reading NOTHING beyond the harvest output carried in the state:

      - suppressed  : a fact-sheet entry already covers the question's
                      information need (semantic de-dup) and no NEEDS-OWNER
                      gap re-raises it — the owner never sees it;
      - recommended : a NEEDS-OWNER entry re-raises the topic — always
                      recommended (confirm/deny the claim), grounded on that
                      entry (D1: re-raises are never `open`);
      - open        : neither — genuinely owner-only knowledge, answered as a
                      bullet.

    The recommended/open split here is the deterministic baseline the script
    can compute from harvest output alone; the SKILL's recommendation pass may
    additionally ground an `open` question from a fact-sheet owner-judgment
    entry and present it as recommended (rationale `owner-judgment`). Zero
    questions are asked when everything is covered — never padded.
    """
    framework = args.framework.upper()
    if framework not in FRAMEWORK_PRIORITY:
        sys.stderr.write(f"error: invalid framework {args.framework!r}. Valid: F1, F2, F3, F4.\n")
        return 2

    # Externally supplied candidate items (e.g. policy-seeded tension questions,
    # Story 14.4) are schema-validated BEFORE any triage runs — an invalid item
    # set halts here, so a malformed or confirmation-shaped question can never
    # reach the owner (Story 14.3; SPEC-policy-source-seam CAP-3).
    seeded_candidates = []
    if getattr(args, "items", None):
        vii = _load("validate-interview-items.py")
        try:
            with open(args.items, encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, json.JSONDecodeError) as e:
            sys.stderr.write(f"error: cannot load interview items {args.items!r}: {e}\n")
            return 2
        if isinstance(data, dict) and "items" in data:
            data = data["items"]
        rejections = vii.validate_items(data)
        if rejections:
            for iid, code, msg in rejections:
                sys.stderr.write(f"[{iid}] {code}: {msg}\n")
            sys.stderr.write("\ninterview items failed validation; triage not run.\n")
            return 1
        seeded_candidates = data

    state = _load_json_state(args.state, "stage-0 state capture")
    fact_sheet = state.get("fact_sheet", [])
    needs_owner = state.get("needs_owner", [])
    gap_topics = {n.get("topic") for n in needs_owner}

    def covering_entries(qid):
        """Fact-sheet entries whose claim contains one of the question's synonym
        keywords — the semantic (not literal) de-dup evidence."""
        kws = QUESTION_BANK[qid]["covers"]
        return [e.get("claim", "") for e in fact_sheet
                if any(kw in e.get("claim", "").lower() for kw in kws)]

    def grounding_for(topic):
        """NEEDS-OWNER candidates re-raising this topic — the recommended
        answer's grounding (confirm/deny)."""
        return [n.get("candidate", n.get("reason", "")) for n in needs_owner
                if n.get("topic") == topic]

    # Triage EVERY bank question (the journal, Story 10.4, records all of them),
    # walking the framework's GATE-slot order so the classification is stable.
    triage = []
    # Policy-seeded tension items (validated above) join the candidate set as
    # ASKED questions: a tension between the material and a recorded position
    # is owner-only by nature — the fact sheet cannot cover it, so suppression
    # does not apply, and the policy source supplies QUESTIONS only, never a
    # recommended answer (NFR15). Their seed rides into the journal (`seed`)
    # and the consulted: line (Story 14.4).
    for item in seeded_candidates:
        rec = {"id": item["id"], "text": item["question"],
               "topic": item["gap_type"], "outcome": "open"}
        if item.get("seed"):
            rec.update(rationale="policy-seed", seed=item["seed"])
        else:
            # A supplied item without a seed is a generic extra candidate,
            # not a policy-seeded one — attribution stays honest.
            rec.update(rationale="topic-absent")
        triage.append(rec)
    for qid in FRAMEWORK_PRIORITY[framework]:
        topic = QUESTION_BANK[qid]["topic"]
        is_gap = topic in gap_topics
        covers = covering_entries(qid)
        rec = {"id": qid, "text": QUESTION_BANK[qid]["text"], "topic": topic}
        if is_gap:
            rec.update(outcome="recommended", rationale="needs-owner-reraise",
                       grounding=grounding_for(topic))
        elif covers:
            rec.update(outcome="suppressed", covered_by=covers)
        else:
            rec.update(outcome="open", rationale="topic-absent")
        triage.append(rec)

    # Evidence fallback (Story 13.30, CAP-5): only when harvest produced no
    # `number`/`result` entry does q8 join the candidates — the evidence GATE
    # has no material and the owner is the only remaining source.
    if not any(e.get("kind") in ("number", "result") for e in fact_sheet):
        q8 = QUESTION_BANK["q8"]
        triage.append({"id": "q8", "text": q8["text"], "topic": q8["topic"],
                       "outcome": "open", "rationale": "evidence-fallback"})

    # Survivors = the non-suppressed questions. Confirmed gaps first, then
    # policy-seeded tension questions, then generic open (stable → framework
    # order preserved within each group), and the ≤5 hard cap holds even with
    # seeded candidates in play — never padded, never exceeded.
    survivors = [r for r in triage if r["outcome"] != "suppressed"]
    survivors.sort(key=lambda r: 0 if r["outcome"] == "recommended"
                   else 1 if r["rationale"] == "policy-seed" else 2)
    survivors = survivors[:QUESTION_BUDGET]

    # Presentation reorder (Story 13.30, CAP-4): selection above is untouched;
    # the asked set is SHOWN claim/angle → audience → significance → color.
    # Python's sort is stable, so ties keep the selection order within a slot.
    presented = sorted(survivors, key=presentation_slot)

    questions = [{"id": r["id"], "text": r["text"], "topic": r["topic"],
                  "from_gap": r["outcome"] == "recommended", "outcome": r["outcome"],
                  "rationale": r["rationale"],
                  **({"grounding": r["grounding"]} if "grounding" in r else {}),
                  **({"seed": r["seed"]} if "seed" in r else {})}
                 for r in presented]
    out = {
        "stage": "interview",
        "next_stage": "fill",
        "framework": framework,
        "budget": QUESTION_BUDGET,
        "asked": len(questions),
        "presentation_order": [q["id"] for q in questions],
        "questions": questions,
        "triage": triage,
    }
    print(json.dumps(out, indent=2))
    return 0


# Stage-2 answer dispositions (Story 10.3; `docs/interview-architecture.md` D2).
# Each disposition maps deterministically to the provenance class the answer
# carries into stage 3, so the drafting stage never has to re-derive it:
#   - approved : the recommended answer is adopted VERBATIM and KEEPS its source
#                pointers → SOURCED provenance (grounds claims like a fact-sheet
#                entry);
#   - modified : the owner edited the recommendation → INTERVIEW provenance
#                (owner judgment on top of the grounding);
#   - replaced : the owner supplied their own bullet → INTERVIEW provenance;
#   - answered : an OPEN question answered with a free-text bullet → INTERVIEW;
#   - skipped  : unanswered — the engine records ONLY the disposition; the slot
#                effect is the framework's declared contract (Story 10.5),
#                resolved at stage 3, never by the interview engine.
DISPOSITION_PROVENANCE = {
    "approved": "sourced",
    "modified": "interview",
    "replaced": "interview",
    "answered": "interview",
    "skipped": None,
}


def _validate_answer(spec):
    """Validate one interview answer spec against the D2 disposition rules.

    Returns (record, None) when valid, or (None, reason) when not. `spec` is a
    dict with `id`, `disposition`, optional `text`, optional `pointers` — the
    same fields the single-answer flags carry. This is the shared core of both
    the single-answer and the batch paths so their rules can never diverge."""
    qid = spec.get("id")
    if not qid:
        return None, "missing `id` (the question this answer keys to)"
    disposition = spec.get("disposition")
    if disposition not in DISPOSITION_PROVENANCE:
        return None, (f"invalid disposition {disposition!r} "
                      f"(valid: {', '.join(DISPOSITION_PROVENANCE)})")
    provenance = DISPOSITION_PROVENANCE[disposition]
    text = (spec.get("text") or "").strip()
    pointers = list(spec.get("pointers") or [])

    if disposition == "skipped":
        if text or pointers:
            return None, ("a skipped answer records only the disposition (no text, no "
                          "pointers); its slot effect is the framework's (Story 10.5)")
    elif disposition == "approved":
        if not pointers:
            return None, ("an approved answer must inherit >=1 source pointer "
                          "(pass --pointer; it grounds sourced claims like a "
                          "fact-sheet entry)")
        if not text:
            return None, ("an approved answer must carry the adopted recommendation "
                          "text (pass --text)")
    else:  # modified / replaced / answered
        if not text:
            return None, f"a {disposition} answer must carry the owner's text (pass --text)"
        if pointers:
            return None, (f"a {disposition} answer is owner judgment (interview-sourced); "
                          "it carries no source pointers")

    return ({"id": qid, "disposition": disposition, "provenance": provenance,
             "answer": text or None, "pointers": pointers}, None)


def cmd_answer(args):
    """Stage 2: record interview answers with their disposition and the
    provenance class it implies (Story 10.3), enforcing the D2 rules so a
    malformed record cannot reach stage 3:

      - approved  → must carry >=1 inherited source pointer and the adopted text;
      - modified / replaced / answered → must carry owner text, no pointers
        (owner judgment is interview-sourced, not source-pointed);
      - skipped   → carries neither text nor pointers; only the disposition,
        its slot effect deferred to the framework (Story 10.5).

    Two forms share one validation core (`_validate_answer`):
      - single answer via the flags (--id/--disposition/--text/--pointer);
      - a batch via `--batch <file|->` (a JSON list of answer specs), validated
        in one pass that reports EVERY rejection at once rather than failing on
        the first — the round-trip cut of Story 13.6, so the interview does not
        pay one reject-and-retry cycle per bad answer.
    """
    if args.batch is not None:
        text = _read_text(args.batch)
        try:
            specs = json.loads(text)
        except json.JSONDecodeError as e:
            sys.stderr.write(f"error: --batch is not valid JSON: {e}\n")
            return 1
        if not isinstance(specs, list):
            sys.stderr.write("error: --batch must be a JSON list of answer specs\n")
            return 1
        records, rejects = [], []
        for i, spec in enumerate(specs):
            if not isinstance(spec, dict):
                rejects.append((i, "?", "answer spec must be a JSON object"))
                continue
            record, reason = _validate_answer(spec)
            if reason is None:
                records.append(record)
            else:
                rejects.append((i, spec.get("id", "?"), reason))
        if rejects:
            # One consolidated, actionable report — every problem, its id, and
            # the fix — instead of one reject per attempt.
            sys.stderr.write(f"{len(rejects)} of {len(specs)} answers rejected:\n")
            for i, qid, reason in rejects:
                sys.stderr.write(f"  [{i}] id={qid}: {reason}\n")
            return 1
        print(json.dumps(records, indent=2))
        return 0

    if not args.id or not args.disposition:
        sys.stderr.write("error: single-answer form needs --id and --disposition "
                         "(or use --batch for a list)\n")
        return 2
    record, reason = _validate_answer(
        {"id": args.id, "disposition": args.disposition,
         "text": args.text, "pointers": args.pointer})
    if reason is not None:
        sys.stderr.write(f"error: {reason}\n")
        return 1
    print(json.dumps(record, indent=2))
    return 0


def cmd_journal(args):
    """Stage 2: assemble the interview journal — one entry per candidate question —
    from the triage (Story 10.2) and the recorded answers (Story 10.3), so a
    mis-asked or mis-suppressed question is attributable from run state rather
    than discovered mid-interview (Story 10.4; `docs/interview-architecture.md` D3).

    Merges what each side already recorded:
      - every ASKED question (recommended/open) → its survival rationale
        (`topic-absent` | `needs-owner-reraise` | `owner-judgment`), the
        recommendation's grounding pointers (when recommended), and the owner's
        disposition;
      - every SUPPRESSED question → the covering fact-sheet entries.

    The journal is written to the run workspace by the SKILL; this command emits
    it. It fails closed if an asked question has no recorded disposition — an
    unattributable interview is a contract violation, not a silent gap.
    """
    interview = _load_json_state(args.interview, "interview journal")
    triage = interview.get("triage")
    if triage is None:
        sys.stderr.write("error: interview JSON has no `triage` array (run `interview` first)\n")
        return 1

    answers = {}
    answer_text = {}
    if args.answers:
        parsed = _load_json_state(args.answers, "answers batch")
        for a in (parsed if isinstance(parsed, list) else [parsed]):
            answers[a.get("id")] = a.get("disposition")
            if a.get("text"):
                answer_text[a.get("id")] = a["text"]

    # The asked set is the ≤5 survivors the owner actually saw; a candidate
    # that survived triage but fell to the question budget was never asked, so
    # it needs no disposition — it is journaled as `capped`, keeping the
    # boundary attributable without inventing owner input (Story 14.4: policy
    # seeds can push the candidate count past the budget).
    asked_ids = {q["id"] for q in interview.get("questions", triage)}

    entries = []
    for t in triage:
        qid = t["id"]
        if t["outcome"] == "suppressed":
            entries.append({"id": qid, "status": "suppressed",
                            "covered_by": t.get("covered_by", [])})
            continue
        if qid not in asked_ids:
            entry = {"id": qid, "status": "capped", "outcome": t["outcome"],
                     "rationale": t.get("rationale")}
            if "seed" in t:
                entry["seed"] = [t["seed"]["pointer"]]
            entries.append(entry)
            continue
        disposition = answers.get(qid)
        if disposition is None:
            sys.stderr.write(f"error: asked question {qid} has no recorded disposition — "
                             "the interview is not attributable (Story 10.4)\n")
            return 1
        entry = {"id": qid, "status": "asked", "outcome": t["outcome"],
                 "rationale": t.get("rationale"), "disposition": disposition}
        if "grounding" in t:
            entry["grounding"] = t["grounding"]
        if "seed" in t:
            # Policy-seeded question: the journal's seed<- field, parallel to
            # the recommendation grounding (Story 14.4).
            entry["seed"] = [t["seed"]["pointer"]]
        entries.append(entry)

    # The /ask-style consulted: line the run artifact must end with (CAP-5):
    # pin + seed -> question map when the run was policy-seeded, else an
    # explicit `none` naming why (unset vs unavailable, from --policy-note).
    seeds = [(t["seed"]["pointer"], t["id"]) for t in triage
             if t.get("seed") and t["id"] in asked_ids]
    # Decision-level influences (Story 13.37): '<pointer>=<label>' pairs — e.g.
    # the policy-informed article-type recommendation — join the same audited
    # mapping; the grammar is unchanged (pointer → what it shaped, at the pin).
    for extra in getattr(args, "seed_extra", []) or []:
        ptr, _, label = extra.partition("=")
        if not label or "@" not in ptr:
            sys.stderr.write(f"error: --seed-extra {extra!r} is not "
                             "'file:line@commit=label'\n")
            return 1
        seeds.append((ptr, label))
    if seeds:
        pin = seeds[0][0].rsplit("@", 1)[1]
        mapping = "; ".join(f"{ptr.rsplit('@', 1)[0]} → {qid}" for ptr, qid in seeds)
        consulted = f"consulted: product-lab@{pin} — {mapping}"
    else:
        consulted = f"consulted: none ({args.policy_note or 'policy_source unset'})"

    out = {"stage": "interview", "journal": entries, "consulted": consulted}
    # Echo the pinned presentation order (Story 13.30, CAP-4) so a mis-ordered
    # run is attributable from the journal alone.
    if interview.get("presentation_order"):
        out["presentation_order"] = interview["presentation_order"]

    # Editorial anchor (Story 13.38, SPEC-policy-editorial-direction CAP-2):
    # the claim/angle answer — the first presented question that received
    # owner text — is the run's editorial anchor, carried into review as the
    # claim intent anchor. It shapes argument and emphasis; it NEVER grounds
    # a factual claim (no-facts invariant — its provenance stays whatever the
    # disposition rules assigned).
    owner_text = {"approved", "modified", "replaced", "answered"}
    rationale_by_id = {t["id"]: t.get("rationale") for t in triage}
    for qid in interview.get("presentation_order") or []:
        if answers.get(qid) in owner_text:
            out["editorial_anchor"] = {
                "id": qid,
                "text": answer_text.get(qid, ""),
                "policy_seeded": rationale_by_id.get(qid) == "policy-seed",
            }
            break
    print(json.dumps(out, indent=2))
    return 0


def cmd_staging_candidates(args):
    """Stage 2 epilogue: emit staging-candidate blocks — proposal-only
    contribute-back (Story 14.5, SPEC-policy-source-seam CAP-4;
    seam-formats.md §3).

    Detection rule (mechanical, stated): a POLICY-SEEDED tension question whose
    answer carries owner text (disposition answered/modified/replaced) records
    a durable position — the owner just answered a contradiction, ambiguity,
    missing-rationale, or reversal probe against their own policy repo. Each
    such answer yields one block whose frontmatter mirrors product-lab's
    `q_a/staging/` schema. Skipped questions and generic answers yield nothing.

    Review-side input (Story 15.2): `--findings` takes arbitrated
    policy-consistency findings instead of interview answers — each entry
    `{id, issue, article: {quote, pointer}, policy: {quote, pointer},
    outcome, decision}`; only `outcome: position-moved` with a non-empty
    owner `decision` emits a block (fix-article and dismiss propose nothing
    back to the recall surface).

    The emitter writes to STDOUT only — the SKILL routes it into the run
    workspace. Nothing is ever written under `policy_source.path`: the owner
    copies accepted blocks into `q_a/staging/` by hand, and `/qa-batch` takes
    it from there. No candidates -> no output (never an empty block).
    """
    if getattr(args, "findings", None):
        findings = _load_json_state(args.findings, "arbitrated policy findings")
        findings = findings if isinstance(findings, list) else [findings]
        blocks = []
        for f in findings:
            if f.get("outcome") != "position-moved":
                continue
            decision = (f.get("decision") or "").strip()
            if not decision:
                continue
            fid = f.get("id") or f"f{len(blocks) + 1}"
            tags = ["policy-contradiction"] + (args.tag or [])
            policy = f.get("policy") or {}
            q_line = (f.get("issue") or "").strip() or (
                f"the article ({(f.get('article') or {}).get('pointer', '?')}) conflicts "
                f"with the recorded position at {policy.get('pointer', '?')}")
            blocks.append("\n".join([
                "<!-- staging-candidate -->",
                "---",
                f"slug: {args.created}-{args.source_repo}-reversal-{fid}",
                f"created: {args.created}",
                f"source_repo: {args.source_repo}",
                "perishable: true",
                f"tags: [{', '.join(tags)}]",
                "---",
                f"Q: {q_line} (recorded position: \"{policy.get('quote', '')}\" — {policy.get('pointer', '')})",
                f"Decision: {decision}",
            ]))
        if not blocks:
            return 0
        print("\n\n".join(blocks))
        return 0

    if not args.interview or not args.answers:
        sys.stderr.write("error: pass --interview and --answers (interview form) "
                         "or --findings (review form)\n")
        return 2
    interview = _load_json_state(args.interview, "interview output")
    answers = _load_json_state(args.answers, "answers batch")
    answers = answers if isinstance(answers, list) else [answers]
    by_id = {a.get("id"): a for a in answers}

    questions = {q["id"]: q for q in interview.get("questions", [])}
    blocks = []
    for qid, q in questions.items():
        if q.get("rationale") != "policy-seed":
            continue
        a = by_id.get(qid)
        if not a or a.get("disposition") not in ("answered", "modified", "replaced"):
            continue
        # `answer --batch` records carry the owner text as `answer`; accept the
        # raw answer-spec `text` form too (found by the 2026-07-14 seam dogfood:
        # real records emitted zero blocks).
        text = (a.get("answer") or a.get("text") or "").strip()
        if not text:
            continue
        gist = re.sub(r"[^a-z0-9]+", "-", q["topic"].lower()).strip("-")
        tags = [q["topic"]] + (args.tag or [])
        blocks.append("\n".join([
            "<!-- staging-candidate -->",
            "---",
            f"slug: {args.created}-{args.source_repo}-{gist}-{qid}",
            f"created: {args.created}",
            f"source_repo: {args.source_repo}",
            "perishable: true",
            f"tags: [{', '.join(tags)}]",
            "---",
            f"Q: {q['text']}",
            f"Decision: {text}",
        ]))
    if not blocks:
        return 0
    print("\n\n".join(blocks))
    return 0


def cmd_review_consulted(args):
    """Review-side consulted: line (Story 15.3, SPEC-policy-consistency-pass
    CAP-4) — the same /ask-style audit grammar as the interview seam's, mapping
    checked policy lines to the FINDINGS they produced instead of questions.

    Modes:
      * findings present: each finding's policy pointer (sans pin) -> `finding
        <n>`; whitelisted files with no finding close as `(no conflict)`;
      * pass ran, zero findings: every checked file -> `(no conflict)`;
      * pass skipped: `consulted: none (policy_source unset)` or
        `consulted: none (policy_source unavailable: <reason>)` via
        --policy-note — every review run states its policy provenance.
    """
    if args.policy_note is not None:
        print(f"consulted: none ({args.policy_note or 'policy_source unset'})")
        return 0
    if not args.pin:
        sys.stderr.write("error: pass --pin product-lab@<sha> (seeded mode) "
                         "or --policy-note (skipped mode)\n")
        return 2
    pin = args.pin.split("@", 1)[1] if "@" in args.pin else args.pin
    findings = []
    if args.findings:
        data = _load_json_state(args.findings, "policy findings")
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


def cmd_consume(args):
    """Stage 1: consume harvest's output document (fact sheet + NEEDS-OWNER) into
    pipeline state — WITHOUT re-reading any source. Source pointers are carried
    verbatim; the harvest contract (KINDS, pointer forms, TOPICS) is imported
    from the Epic 3 validators so a schema change surfaces here, not silently.
    """
    # Lazy import: stage 0 stays independent of these.
    vfs = _load("validate-fact-sheet.py")
    vno = _load("validate-needs-owner.py")

    text = sys.stdin.read() if args.doc == "-" else open(args.doc, encoding="utf-8").read()
    fs_lines, no_lines, has_no = vno.split_sections(text)
    if not has_no:
        sys.stderr.write("error: harvest output has no `# NEEDS-OWNER` section (contract violation)\n")
        return 1

    fact_sheet = []
    for e in vno.entries(fs_lines):
        parts = [p.strip() for p in e.rsplit(" / ", 2)]
        if len(parts) != 3 or any(p == "" for p in parts):
            sys.stderr.write(f"error: malformed fact-sheet entry (want `CLAIM / SOURCE / KIND`): {e}\n")
            return 1
        claim, source, kind = parts
        if kind not in vfs.KINDS:
            sys.stderr.write(f"error: fact-sheet KIND {kind!r} outside the harvest contract: {e}\n")
            return 1
        # Use the validator's shared SOURCE grammar so consume can never diverge
        # from it (Story 13.8): a multi-line `quote` range that validate-fact-sheet
        # accepts must not be rejected here.
        if not vfs.source_form_ok(source, kind):
            sys.stderr.write(f"error: fact-sheet SOURCE {source!r} is not a valid pointer form for KIND {kind!r}: {e}\n")
            return 1
        fact_sheet.append({"claim": claim, "source": source, "kind": kind})   # source verbatim

    needs_owner = []
    for e in vno.entries(no_lines):
        parts = [p.strip() for p in e.rsplit(" / ", 2)]
        if len(parts) != 3 or any(p == "" for p in parts):
            sys.stderr.write(f"error: malformed NEEDS-OWNER entry (want `CANDIDATE / REASON / TOPIC`): {e}\n")
            return 1
        candidate, reason, topic = parts
        if topic not in vno.TOPICS:
            sys.stderr.write(f"error: NEEDS-OWNER TOPIC {topic!r} outside the harvest contract: {e}\n")
            return 1
        needs_owner.append({"candidate": candidate, "reason": reason, "topic": topic})

    state = {
        "stage": "consume",
        "next_stage": "interview",          # NEEDS-OWNER threads into the gap interview (Story 4.3)
        "fact_sheet": fact_sheet,
        "needs_owner": needs_owner,
    }
    print(json.dumps(state, indent=2))
    return 0


def cmd_start(args):
    state, code = _run_state(args.framework, args.sources, args.root)
    if state is None:
        return code
    print(json.dumps(state, indent=2))
    return 0


# --- Durability: per-stage checkpoint + resume (Story 13.5) ------------------
# The pipeline's turn/compute budget is a real ceiling even though wall-clock is
# unconstrained (SPEC constraints, 2026-07-12). Each stage's output state already
# carries `next_stage`; persisting that state to the run workspace after a stage
# completes makes a re-invocation resume from the last completed stage instead of
# restarting — a turn-ceiling casualty is recoverable, not a total loss. The
# checkpoint file IS the stage state, so writing it twice is idempotent and
# resuming never re-runs a completed stage (next_stage points past it).

CHECKPOINT_FILE = "checkpoint.json"


def _checkpoint_path(ws):
    return os.path.join(ws, CHECKPOINT_FILE)


def cmd_checkpoint(args):
    """Persist a completed stage's output state to `<ws>/checkpoint.json` so the
    run can resume from `next_stage`. Idempotent: re-writing the same stage's
    state yields an identical file. The write is atomic (temp + os.replace) so an
    interrupted write never leaves a half-written checkpoint to resume from."""
    if not os.path.isdir(args.ws):
        sys.stderr.write(f"error: run workspace does not exist: {args.ws}\n")
        return 1
    text = _read_text(args.state)
    try:
        state = json.loads(text)
    except json.JSONDecodeError as e:
        sys.stderr.write(f"error: checkpoint state is not valid JSON: {e}\n")
        return 1
    if not isinstance(state, dict):
        sys.stderr.write("error: checkpoint state must be a JSON object\n")
        return 1
    if "next_stage" not in state:
        sys.stderr.write(
            "error: checkpoint state has no `next_stage` — pass a stage's output "
            "state (start/consume/interview/...), which records where to resume\n")
        return 1
    path = _checkpoint_path(args.ws)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)
    os.replace(tmp, path)
    print(f"checkpoint: next_stage={state['next_stage']} -> {path}")
    return 0


def cmd_resume(args):
    """Report where to resume a run from its workspace checkpoint. Prints a JSON
    object: `{"resumed": true, ...state}` when a checkpoint exists (resume from
    its `next_stage`), or `{"resumed": false, "next_stage": "harvest"}` when none
    exists yet (a fresh run starts at stage 1)."""
    if not os.path.isdir(args.ws):
        sys.stderr.write(f"error: run workspace does not exist: {args.ws}\n")
        return 1
    path = _checkpoint_path(args.ws)
    if not os.path.isfile(path):
        print(json.dumps({"resumed": False, "next_stage": "harvest"}, indent=2))
        return 0
    with open(path, encoding="utf-8") as f:
        state = json.load(f)
    out = {"resumed": True}
    out.update(state)
    print(json.dumps(out, indent=2))
    return 0


# A completed run's final checkpoint carries next_stage == DONE_STAGE so
# `autostart` never resumes it (Story 13.12).
DONE_STAGE = "done"


def _autostart(root):
    """Core of automatic resume (Story 13.12): return the workspace to use and
    where to start — resuming the newest in-progress run (checkpoint next_stage
    != done), or minting a fresh run when none is in progress. Shared by the
    `autostart` and `stage0` commands."""
    rp = _load("resolve-paths.py")
    base = rp.runs_dir(root)
    if os.path.isdir(base):
        # Run ids are timestamp-based, so reverse-lexicographic == newest-first.
        for run_id in sorted(os.listdir(base), reverse=True):
            cp = os.path.join(base, run_id, CHECKPOINT_FILE)
            if not os.path.isfile(cp):
                continue
            try:
                with open(cp, encoding="utf-8") as f:
                    state = json.load(f)
            except (OSError, json.JSONDecodeError):
                continue
            if state.get("next_stage") and state["next_stage"] != DONE_STAGE:
                out = {"resumed": True, "ws": os.path.join(base, run_id), "run_id": run_id}
                out.update(state)
                return out
    # No in-progress run — start fresh (this is the AC4 no-false-resume path).
    ws = rp.new_run(root)
    return {"resumed": False, "ws": ws, "run_id": os.path.basename(ws), "next_stage": "harvest"}


def cmd_autostart(args):
    """Stage 0: automatic resume (Story 13.12). Resumption is the DEFAULT, not an
    agent choice — so instead of always minting a new run, find the newest
    in-progress run for this repo (a run workspace whose checkpoint records a
    `next_stage` other than `done`) and resume it; if none exists, mint a fresh
    run at stage 1. Prints the workspace to use and where to start:
      {"resumed": true,  "ws": …, "run_id": …, "next_stage": …}  # continue here
      {"resumed": false, "ws": …, "run_id": …, "next_stage": "harvest"}  # new run
    A large draft completing across several invocations is the normal model."""
    rp = _load("resolve-paths.py")
    print(json.dumps(_autostart(rp.host_root(args.root)), indent=2))
    return 0


def _entry_gate_ok(key, framework_file, root):
    """Evaluate the selected framework's ENTRY gate — the framework-selection
    precondition stated at the top of its framework file (F1: a tagged release,
    F1-project-introduction.md "GATE (entry)"). Returns (ok, message).

    Frameworks that declare no entry precondition pass. Enforcement is bound to
    the framework file's own text: it fires only while the file still states the
    gate, so this mirrors the spec rather than hardcoding a precondition the
    framework no longer claims. Checked here — before any framework file is read
    into the draft or a workspace is minted — so an unsatisfiable framework fails
    fast instead of forcing a wasted mid-pipeline switch (Story 13.19)."""
    try:
        with open(os.path.join(plugin_root(), framework_file), encoding="utf-8") as f:
            head = f.read(2000)
    except OSError:
        return True, ""
    # F1 is the only framework that currently declares a machine-checkable entry
    # precondition ("GATE (entry) — ... the project has a tagged release ...").
    if key == "f1" and "GATE (entry)" in head and "tagged release" in head:
        try:
            r = subprocess.run(["git", "tag"], cwd=(root or None),
                               capture_output=True, text=True)
            has_tag = r.returncode == 0 and r.stdout.strip() != ""
        except OSError:
            has_tag = False
        if not has_tag:
            return False, (
                'the "introduce the project" article type has an entry '
                "precondition: the project must have a tagged release (or an "
                "equivalent shipped artifact), and this repository has no git "
                "tags — the precondition is unmet before any drafting begins.\n"
                "Choose an article type without a release precondition: "
                '"share engineering lessons", "explain the evaluation '
                'methodology", or "survey a research area".')
    return True, ""


def _run_state(framework, sources, root=None):
    """Build the stage-0 run-state (framework + classified sources), or return
    (None, exit_code) on a framework error — shared by `start` and `stage0`."""
    key = resolve_framework(framework)
    if key is None:
        labels = "; ".join(
            f'"{INTENT_LABELS[k]}" ({k.upper()})' for k in sorted(FRAMEWORKS))
        sys.stderr.write(
            f"error: invalid article type {framework!r}. "
            f"Valid: {labels}. Nothing started.\n")
        return None, 2
    framework_file = os.path.join("skills", "draft-article", "frameworks", FRAMEWORKS[key])
    if not os.path.isfile(os.path.join(plugin_root(), framework_file)):
        sys.stderr.write(f"error: framework asset missing: {framework_file}\n")
        return None, 1
    gate_ok, gate_msg = _entry_gate_ok(key, framework_file, root)
    if not gate_ok:
        sys.stderr.write(f"error: {gate_msg}\nNothing started.\n")
        return None, 2
    return {
        "next_stage": "harvest",
        "framework": key.upper(),
        "framework_file": framework_file,
        "sources_raw": list(sources),
        "sources": [{"value": t, "form": classify(t)} for t in sources],
    }, 0


def cmd_stage0(args):
    """Story 13.13: fold the whole of Stage 0 into ONE invocation instead of
    three — configuration validation (CAP-5), framework check, and workspace
    autostart (Story 13.12). The agent pays one round-trip, not three, so a run
    makes progress per turn instead of exhausting the budget on orchestration.

    Halts (non-zero) with `validate-config.py`'s exact per-key report on a bad
    config (delegated verbatim, so diagnostics never diverge); a bad framework
    halts before any workspace is minted. On success prints a combined JSON:
      {"config_ok": true, "run_state": {…}, "resumed": …, "ws": …, "next_stage": …}
    """
    here = os.path.dirname(os.path.realpath(__file__))
    # 1. Config validation — delegate verbatim (same report, same exit code).
    cmd = [sys.executable, os.path.join(here, "validate-config.py")]
    if args.root:
        cmd += ["--root", args.root]
    rc = subprocess.run(cmd).returncode
    if rc != 0:
        return rc
    # 2. Framework check + entry-gate precondition (before minting a workspace).
    run_state, code = _run_state(args.framework, args.sources, args.root)
    if run_state is None:
        return code
    # 3. Workspace autostart (mint or resume).
    rp = _load("resolve-paths.py")
    out = {"config_ok": True, "run_state": run_state}
    out.update(_autostart(rp.host_root(args.root)))
    print(json.dumps(out, indent=2))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    sp = sub.add_parser("start")
    sp.add_argument("framework")
    sp.add_argument("sources", nargs="*")
    sp.add_argument("--root", help="host-repo root, for the framework entry-gate check "
                                   "(default: cwd; e.g. F1 requires a tagged release)")
    sp = sub.add_parser("consume")
    sp.add_argument("doc", nargs="?", default="-", help="harvest output document, or - for stdin")
    sp = sub.add_parser("checkpoint", help="persist a completed stage's state to <ws>/checkpoint.json (Story 13.5)")
    sp.add_argument("--ws", required=True, help="the run workspace ($WS) to checkpoint into")
    sp.add_argument("state", nargs="?", default="-", help="the stage's output state JSON, or - for stdin")
    sp = sub.add_parser("resume", help="report where to resume a run from its workspace checkpoint (Story 13.5)")
    sp.add_argument("--ws", required=True, help="the run workspace ($WS) to resume")
    sp = sub.add_parser("autostart", help="auto-resume the newest in-progress run, else mint a fresh one (Story 13.12)")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")
    sp = sub.add_parser("stage0", help="fold Stage 0 into one call: config validation + framework + autostart (Story 13.13)")
    sp.add_argument("framework")
    sp.add_argument("sources", nargs="*")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")
    sp = sub.add_parser("interview")
    sp.add_argument("--framework", required=True)
    sp.add_argument("--items", help="candidate interview-item JSON (e.g. policy-seeded questions); "
                                    "schema-validated before triage — invalid items halt the stage")
    sp.add_argument("state", nargs="?", default="-", help="stage-1 pipeline state JSON, or - for stdin")
    sp = sub.add_parser("answer")
    sp.add_argument("--id", help="the question id this answer keys to (single-answer form)")
    sp.add_argument("--disposition",
                    help="approved | modified | replaced | answered | skipped (single-answer form)")
    sp.add_argument("--text", help="the answer text (adopted recommendation, or owner's bullet)")
    sp.add_argument("--pointer", action="append",
                    help="inherited source pointer (approved answers only; repeatable)")
    sp.add_argument("--batch", help="validate a JSON list of answer specs in one pass "
                                    "(FILE or - for stdin); reports every rejection at once")
    sp = sub.add_parser("journal")
    sp.add_argument("--interview", required=True, help="the `interview` output JSON (carries triage), or - for stdin")
    sp.add_argument("--answers", help="recorded answer records (JSON list), or - for stdin")
    sp.add_argument("--policy-note", help="why the run was not policy-seeded, for the consulted: line "
                                          "(e.g. 'policy_source unavailable: <reason>'; default: unset)")
    sp.add_argument("--seed-extra", action="append", default=[], metavar="PTR=LABEL",
                    help="additional policy influence for the consulted: line — "
                    "'file:line@commit=article-type' records a decision (not a "
                    "question) the policy surface shaped (Story 13.37, "
                    "SPEC-policy-editorial-direction CAP-1)")
    sp = sub.add_parser("staging-candidates")
    sp.add_argument("--interview", help="the `interview` output JSON, or - for stdin (interview form)")
    sp.add_argument("--answers", help="recorded answer records (JSON list; interview form)")
    sp.add_argument("--findings", help="arbitrated policy-consistency findings JSON (review form, Story 15.2)")
    sp.add_argument("--source-repo", required=True, help="the host repo's name, for the block frontmatter")
    sp.add_argument("--created", required=True, help="the run date (YYYY-MM-DD)")
    sp.add_argument("--tag", action="append", help="extra frontmatter tag (repeatable; e.g. the track)")
    sp = sub.add_parser("review-consulted")
    sp.add_argument("--pin", help="the run pin, product-lab@<sha> (seeded mode)")
    sp.add_argument("--findings", help="policy findings JSON (entries carry policy.pointer)")
    sp.add_argument("--file", action="append", help="checked whitelist file (repeatable); no-finding files close as (no conflict)")
    sp.add_argument("--policy-note", nargs="?", const="", default=None,
                    help="skipped mode: reason for consulted: none (empty = unset)")
    sp = sub.add_parser("provenance")
    sp.add_argument("--map", default="-", help="the sidecar provenance map, or - for stdin")
    sp.add_argument("--count", action="store_true", help="print per-class tallies as JSON")
    sp = sub.add_parser("quality-gate")
    sp.add_argument("--draft", default="-", help="the filled draft, or - for stdin")
    sp.add_argument("--map", help="the sidecar provenance map (for the stitched-fact-sheet check)")
    sp.add_argument("--judge", help="rubric judge verdicts for dims 1-3: `dimN: pass|fail [locations]` per line")
    sp = sub.add_parser("verify-markers")
    sp.add_argument("draft", nargs="?", default="-", help="draft file, or - for stdin")
    sp.add_argument("--count", action="store_true", help="print the count of well-formed markers")
    sp = sub.add_parser("verify")
    sp.add_argument("draft", nargs="?", default="-", help="filled draft, or - for stdin")
    sp = sub.add_parser("reroute")
    sp.add_argument("--rewrites", type=int, required=True,
                    help="rewrites already applied to this section")
    sp.add_argument("--section", default="?", help="section identifier (for the routed question)")
    sp = sub.add_parser("variants")
    sp.add_argument("draft", nargs="?", default="-", help="verified draft, or - for stdin")
    sp.add_argument("--config-json", help="resolved config as JSON (FILE or - for stdin)")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")
    sp.add_argument("--global-config")
    sp.add_argument("--repo-config")
    sp.add_argument("--out", help="output dir (default: resolved output.drafts)")
    sp.add_argument("--create-out", action="store_true",
                    help="consent to creating a missing output directory OUTSIDE "
                         "the host repo (inside the host it is created automatically)")
    sp.add_argument("--dry-run", action="store_true", help="do not write files; just report")
    sp.add_argument("--ws", help="run workspace for intermediates (profile-resolution log)")
    sp.add_argument("--platforms",
                    help="comma-separated platform ids to emit (the owner's publish "
                         "decision), or `all`; a subset of the configured platforms")
    sp.add_argument("--list-platforms", action="store_true",
                    help="report the configured platforms for this draft and emit "
                         "nothing (feeds the in-conversation emission choice)")

    st = sub.add_parser("variant-staleness")
    st.add_argument("draft", nargs="?", default="-", help="canonical draft, or - for stdin")
    st.add_argument("--variants", nargs="*", help="variant files to check "
                    "(default: scan output.drafts for this draft's slug)")
    st.add_argument("--out", help="output dir holding the variants (default: resolved output.drafts)")
    st.add_argument("--root", help="host-repo root (default: git top-level of cwd)")

    sr = sub.add_parser("site-record")
    sr.add_argument("draft", nargs="?", default="-", help="canonical draft, or - for stdin")
    sr.add_argument("--url", help="the final published URL (the owner confirms it "
                    "post-publish); without it the offer is reported as pending")
    sr.add_argument("--date", help="the real publication date (default: the draft's date)")
    sr.add_argument("--config-json")
    sr.add_argument("--root", help="host-repo root (default: git top-level of cwd)")
    sr.add_argument("--global-config")
    sr.add_argument("--repo-config")
    sr.add_argument("--ws", help="run workspace for the proposal (never the site tree)")
    args = p.parse_args(argv)
    return {
        "start": cmd_start, "consume": cmd_consume, "interview": cmd_interview,
        "checkpoint": cmd_checkpoint, "resume": cmd_resume, "autostart": cmd_autostart,
        "stage0": cmd_stage0,
        "answer": cmd_answer, "journal": cmd_journal, "provenance": cmd_provenance,
        "staging-candidates": cmd_staging_candidates,
        "review-consulted": cmd_review_consulted,
        "quality-gate": cmd_quality_gate,
        "verify-markers": cmd_verify_markers, "verify": cmd_verify, "reroute": cmd_reroute,
        "variants": cmd_variants,
        "variant-staleness": cmd_variant_staleness,
        "site-record": cmd_site_record,
    }[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
