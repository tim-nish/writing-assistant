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
import bisect
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
    "f5": "F5-working-note.md",
}

# The ratified working-note profile (SPEC-article-frameworks, working-note
# ratification 2026-07-16; entry path Story 13.89 / #412) runs SLIM: no
# 5-question interview (consume routes straight to fill) and a lighter quality
# gate (mechanical dimensions only — see cmd_quality_gate --profile).
SLIM_PROFILE_FRAMEWORKS = {"f5"}

# Owner-facing intent labels (SPEC-draft-article-ux CAP-1, Story 13.27). The
# invocation accepts these; F1-F4 stay valid as the internal/expert alias and
# never appear in owner-facing text. Closed mapping — no fuzzy matching: an
# unknown label is rejected, never guessed.
INTENT_LABELS = {
    "f1": "introduce the project",
    "f2": "share engineering lessons",
    "f3": "explain the evaluation methodology",
    "f4": "survey a research area",
    "f5": "write a working note",
}
INTENT_ALIASES = {
    "write-a-working-note": "f5",
    "working-note": "f5",
    "working-notes": "f5",
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


# Nearest-fit hints for unmapped intents (Story 13.81). Resolution stays a
# closed mapping — these NEVER select a framework; they only shape the
# refusal so the writer gets a reason and a direction instead of a bare
# label list. First matching row wins.
NEAREST_FIT_HINTS = [
    (re.compile(r"tutorial|how-?to|walkthrough|step-?by-?step|guide"),
     'a tutorial/how-to framework is deliberately excluded — ratified-banned '
     'by AP-10 (SPEC-article-frameworks), not a gap. Closest fit: "share '
     'engineering lessons" (the lessons behind the how-to), or the '
     'lightweight working-note profile ("write a working note")'),
    (re.compile(r"announc|launch|release|intro"),
     'closest fit: "introduce the project"'),
    (re.compile(r"lesson|postmortem|retro|debug|incident|migrat"),
     'closest fit: "share engineering lessons"'),
    (re.compile(r"bench|eval|measur|test|method"),
     'closest fit: "explain the evaluation methodology"'),
    (re.compile(r"survey|landscape|compar|review|state.of"),
     'closest fit: "survey a research area"'),
]


def nearest_fit(raw):
    """A refusal hint for an unmapped intent: why the set is closed, plus the
    closest sanctioned fit (or the working-note profile as the light fallback)."""
    key = re.sub(r"[^a-z0-9]+", "-", raw.strip().lower()).strip("-")
    for pat, hint in NEAREST_FIT_HINTS:
        if pat.search(key):
            return hint
    return ('closest fit: none of the sanctioned categories maps cleanly — '
            'the lightweight working-note profile ("write a working note") is '
            'the fallback for material outside them')
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
    if rec.get("rationale") in ("policy-seed", "policy-reconciliation"):
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
# The shared revision bound (CAP-7 / #349 / #348): rewrites, quality-gate
# revisions, AND missing-input repair hops all count against these two cycles;
# past it, the unresolved item is a publish blocker, never a third attempt.
TWO_CYCLE_BOUND = 2


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
# A position may carry a LINE ANCHOR — `P1.S1[L7]` (#304). Without it a judge
# must re-derive the P{n}.S{n} numbering from the draft by applying the skip
# rules (frontmatter, headings, blockquotes, mermaid, pointer block); three
# independent judges did that over one draft and each produced a DIFFERENT
# numbering, then returned confident verdicts against sentences that were not
# at the positions they named. The map is machine-generated and the draft is
# fixed at grading time, so the ambiguity is gratuitous: the anchor lets a judge
# MATCH instead of derive. The suffix is optional in the grammar (older maps
# still parse) and required where it matters — see `provenance --draft`.
PROV_LINE = re.compile(
    r"^(?P<pos>[^\s:\[]+)(?:\[L(?P<anchor>\d+)\])?"
    r":\s*(?P<cls>sourced|derived|narration|verify)"
    r"(?:\s*<-\s*(?P<ptrs>.+?))?\s*$"
)


def parse_provenance_map(text):
    """Parse the sidecar map text into [(pos, cls, [pointers], anchor)], raising
    ValueError on a malformed line, a class name outside the closed set, or a
    duplicate position key (#308). Duplicates fail closed here — before any
    normalization and before any judge is invoked — because a map that cannot
    be read unambiguously has not been read: last-write-wins silently drops a
    classification, and counting both inflates the class totals dimension 4
    reads. The diagnostic names every duplicated key with all of its input
    line numbers, so a scripted edit that collided several paragraphs is fixed
    in one pass, not one collision per run."""
    entries = []
    seen = {}  # pos -> [line numbers]
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = PROV_LINE.match(line)
        if not m:
            raise ValueError(f"line {lineno}: malformed provenance entry: {raw!r}")
        ptrs = [p.strip() for p in (m.group("ptrs") or "").split(",") if p.strip()]
        seen.setdefault(m.group("pos"), []).append(lineno)
        anchor = int(m.group("anchor")) if m.group("anchor") else None
        entries.append((m.group("pos"), m.group("cls"), ptrs, anchor))
    dupes = {pos: lns for pos, lns in seen.items() if len(lns) > 1}
    if dupes:
        detail = "; ".join(
            f"{pos} (lines {', '.join(map(str, lns))})" for pos, lns in dupes.items())
        raise ValueError(f"duplicate position key(s): {detail}")
    return entries


def _provenance_problems(entries, draft_lines=None):
    """The structural per-class and line-anchor checks over parsed map entries
    — the ONE validation path shared by the `provenance` command and by
    `review-reentry` (Story 13.70), so a map review re-persists under can never
    be held to a different standard than the map stage 3 shipped. Returns
    (tally, problems); anchor checks run only when `draft_lines` is given."""
    tally = {c: 0 for c in PROV_CLASSES}
    problems = []
    for pos, cls, ptrs, anchor in entries:
        tally[cls] += 1
        if cls == "sourced" and len(ptrs) < 1:
            problems.append(f"{pos}: sourced claim carries no pointer")
        elif cls == "derived" and len(ptrs) < 2:
            problems.append(f"{pos}: derived claim must inherit >=2 pointers (got {len(ptrs)})")
        elif cls in ("narration", "verify") and ptrs:
            problems.append(f"{pos}: {cls} must carry no pointer (got {len(ptrs)})")
        if draft_lines is not None:
            if anchor is None:
                problems.append(f"{pos}: no line anchor — a judge cannot locate this "
                                "sentence without re-deriving the numbering (write "
                                f"`{pos}[L<line>]`)")
            elif not (1 <= anchor <= len(draft_lines)):
                problems.append(f"{pos}: anchor L{anchor} is outside the draft "
                                f"(1..{len(draft_lines)})")
            elif not draft_lines[anchor - 1].strip():
                problems.append(f"{pos}: anchor L{anchor} points at a blank line")
    return tally, problems


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

    With --draft, every position must also carry a LINE ANCHOR (`P1.S1[L7]`)
    that resolves to a real, non-blank line of that draft (#304). The anchor is
    what lets an isolated judge match a sentence instead of re-deriving the
    numbering; a map handed to a judge without one is not gradeable, so this is
    a structural failure like any other, not an advisory.
    """
    text = sys.stdin.read() if args.map == "-" else open(args.map, encoding="utf-8").read()
    try:
        entries = parse_provenance_map(text)
    except ValueError as e:
        sys.stderr.write(f"error: {e}\n")
        return 1

    draft_lines = None
    if getattr(args, "draft", None):
        draft_lines = _read_text(args.draft).splitlines()

    tally, problems = _provenance_problems(entries, draft_lines)

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


# --- Dimension 3: explanation calibration (#305) ------------------------------
# A CLOSED scan over repo-internal vocabulary against the rubric's written
# introduction contract — not open-ended judgment. An unpinned LLM judgment
# reported one item at a time cannot converge inside the D5 bound of 2 cycles:
# four cycles over one draft named twelve terms and never passed, because each
# pass re-litigated what "introduced" means (expanding `de-dup` to
# `de-duplication check` even manufactured the next violation). A mechanical
# scan is exhaustive AND deterministic by construction, satisfying both halves
# of the defect at once.
#
# The gated inventory is a versioned plugin asset, not a constant in this file:
# dimension 3 is only as exhaustive as the inventory, so the inventory is the
# CONTRACT (`internal-vocabulary.json`) and `check-internal-vocabulary.sh`
# fails when a derivable family — framework IDs, pipeline stage names, markers —
# drifts out of it. A hardcoded tuple could go stale silently and the gate would
# keep reporting `dim3: pass`; that is the failure mode this indirection exists
# to remove. Missing or malformed asset = named error, never a silent empty scan.
VOCAB_ASSET = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                           "skills", "draft-article", "internal-vocabulary.json")


def _load_internal_vocabulary(path=None):
    """Return (terms, patterns) from the registered inventory, longest-first.

    Longest-first matters for contract rule 6: `de-duplication check` must match
    before `de-dup` so an expansion is never scored as a fresh, unintroduced
    term. Raises SystemExit with a named diagnostic when the asset is missing or
    malformed — an unreadable inventory means dim3 has not scanned, and a gate
    that cannot read its inventory must not report a verdict on it.
    """
    p = path or VOCAB_ASSET
    try:
        with open(p, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, json.JSONDecodeError) as e:
        raise SystemExit(
            f"error: internal-vocabulary inventory unreadable at {p}: {e} — dim3 "
            "cannot scan without its registered inventory (#305)")
    terms = data.get("terms")
    patterns = data.get("patterns")
    if not isinstance(terms, list) or not isinstance(patterns, list) or not terms:
        raise SystemExit(
            f"error: internal-vocabulary inventory at {p} is malformed — expected "
            "non-empty `terms` and a `patterns` list (#305)")
    return tuple(sorted(terms, key=len, reverse=True)), tuple(patterns)
# An inline appositive gloss AT the point of use: `term (gloss)`, `term, gloss,`
# or `term — gloss`. Sufficient by contract — the reader never meets the term
# unexplained (this is the call the cycle-4 judge disputed; the rule settles it).
_APPOSITIVE = r"\s*(\([^)]{8,}\)|,\s[^,.]{8,},|\s[—–-]\s[^.]{8,})"
# A defining sentence: the term with a definitional verb, anywhere before first use.
_DEFINING = re.compile(r"\b(is|are|means|refers to|denotes|stands for|=)\b", re.I)


def _dim3_scan_units(draft_text):
    """Yield (text, kind, line_of) for every scannable BLOCK of the draft body.

    Blocks, not physical lines: prose wraps, so a term and the gloss that
    introduces it routinely straddle a line break (`Stage 3 — the` / `framework
    -fill step`). A line-based scan would call that gloss absent and manufacture
    exactly the false violation this dimension exists to stop. Each paragraph is
    joined into one text; `line_of(pos)` maps a match offset back to the
    physical line, so verdicts still name a real location.

    kind: 'prose' (a load-bearing context) or 'heading' (NEUTRAL by contract —
    neither an introduction nor a use). Frontmatter is skipped; mermaid fence
    bodies are prose because a diagram LABEL is a load-bearing use requiring a
    prior prose introduction; other code fences are skipped as verbatim text.
    """
    lines = draft_text.splitlines()
    i, in_front, fence = 0, False, None
    if lines and lines[0].strip() == "---":
        in_front, i = True, 1

    def flush(buf):
        """Join a paragraph's lines, keeping an offset->lineno index."""
        text, index, pos = "", [], 0
        for lineno, s in buf:
            if text:
                text += " "
                pos += 1
            index.append((pos, lineno))
            text += s
            pos += len(s)
        starts = [p for p, _ in index]

        def line_of(match_pos):
            k = bisect.bisect_right(starts, match_pos) - 1
            return index[max(k, 0)][1]
        return text, "prose", line_of

    buf = []
    for lineno, raw in enumerate(lines[i:], start=i + 1):
        s = raw.strip()
        if in_front:
            if s == "---":
                in_front = False
            continue
        if s.startswith("```"):
            lang = s[3:].strip().lower()
            fence = None if fence else (lang or "plain")
            continue
        if fence and fence != "mermaid":
            continue
        if not s:                                   # blank line ends a paragraph
            if buf:
                yield flush(buf)
                buf = []
            continue
        if s.startswith("#"):
            if buf:
                yield flush(buf)
                buf = []
            yield s, "heading", (lambda _p, _l=lineno: _l)
            continue
        buf.append((lineno, s))
    if buf:
        yield flush(buf)


def _dimension3(draft_text, allowlist=()):
    """Return the COMPLETE list of dim3 violations as (term, line) — every
    uncalibrated term in one pass, so a single revision can clear the dimension.

    A term is introduced (contract, `quality-rubric.md`) by: a preceding gloss
    or defining sentence; an inline appositive at first load-bearing use; an
    abbreviation expanded-with-gloss. A heading occurrence is neutral; a
    diagram label is a use; an expansion of an already-introduced base term is
    never re-promoted to unintroduced.
    """
    vocab_terms, vocab_res = _load_internal_vocabulary()
    known = {t.lower() for t in allowlist}
    units = list(_dim3_scan_units(draft_text))
    patterns = [(t, re.compile(re.escape(t), re.I)) for t in vocab_terms
                if t.lower() not in known]
    patterns += [(p, re.compile(p)) for p in vocab_res
                 if p.lower() not in known]

    # Pass 1 — locate each term's first load-bearing use and decide whether it
    # is introduced at or before that point. Two passes are required: the
    # vocabulary is scanned longest-first (so an expansion never matches as its
    # own shorter base), which means a base term's introduction is not yet known
    # when its expansion is examined.
    findings, introduced = {}, []
    for label, rx in patterns:
        for text, kind, line_of in units:
            m = rx.search(text)
            if not m:
                continue
            if kind == "heading":
                continue                      # neutral: triggers nothing
            surface, lineno = m.group(0), line_of(m.start())
            if re.compile(rx.pattern + _APPOSITIVE, re.I).search(text) \
                    or _DEFINING.search(text):
                findings[label] = (True, lineno, surface)
                introduced.extend((surface, label))
            else:
                findings[label] = (False, lineno, surface)
            break                              # first load-bearing use decides

    # Pass 2 — rule 6: an expansion of an already-introduced base term is never
    # re-promoted to unintroduced (`de-dup` -> `de-duplication check`, the case
    # where fixing one dim3 finding manufactured the next).
    violations = [
        (surface, lineno)
        for label, (ok, lineno, surface) in findings.items()
        if not ok and not any(b.lower() != surface.lower()
                              and b.lower() in surface.lower() for b in introduced)
    ]
    return sorted(violations, key=lambda v: (v[1], v[0]))


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
        classes = [c for _, c, _, _ in prov_entries]
        total = len(classes)
        sourced = classes.count("sourced")
        tissue = classes.count("derived") + classes.count("narration")
        if tissue == 0 and sourced > 0:
            fails.append("stitched fact sheet: all sourced claims, no derived/narration tissue")
        elif total and sourced / total > QG_STITCH_SOURCED_FRACTION and tissue == 0:
            fails.append(f"stitched fact sheet: {sourced}/{total} sourced, no connective tissue")
    return fails


def _loc_set(s):
    """Normalize a locations string (judge `[locations]` or --prior-locations)
    into a comparable set: split on `;`/`[`/`]`, drop brackets, lowercase,
    strip. Used by the second-cycle delta re-check to test whether a cycle-2
    dim1/dim2 failure overlaps cycle-1's failing locations (#349)."""
    if not s:
        return set()
    if isinstance(s, (list, tuple)):
        s = ";".join(s)
    parts = re.split(r"[;\[\]]", str(s))
    return {p.strip().lower() for p in parts if p.strip()}


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
    draft = sys.stdin.read() if args.draft == "-" else open(args.draft, encoding="utf-8").read()
    prov_entries = []
    if args.map:
        try:
            prov_entries = parse_provenance_map(_read_text(args.map))
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
        bad, verdict_re = [], re.compile(r"^(dim[123])\s*:\s*(pass|fail)\b(.*)$", re.IGNORECASE)
        for lineno, ln in enumerate(_read_text(args.judge).splitlines(), 1):
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
        prior = _loc_set(getattr(args, "prior_locations", None))
        if prior:
            for dim in ("dim1", "dim2"):
                v, loc = results[dim]
                if v != "fail":
                    continue
                this_locs = _loc_set(loc)
                if this_locs and not (this_locs & prior):
                    # a fresh interpretive finding at a location cycle 1 never
                    # flagged — not actionable on the delta re-check
                    results[dim] = ("pass", "")
                    delta_suppressed.append({"dimension": dim, "locations": loc})

    # Dimension 3: mechanical, exhaustive, deterministic (#305).
    known = []
    for a in (getattr(args, "audience_known", None) or []):
        known.extend(t.strip() for t in a.split(",") if t.strip())
    d3 = _dimension3(draft, known)
    results["dim3"] = ("pass", "") if not d3 else (
        "fail", "; ".join(f"{t} (line {n})" for t, n in d3))
    # Which inventory produced that verdict is part of the verdict: a dim3 pass
    # means "nothing in the registered inventory was uncalibrated", never
    # "nothing was uncalibrated". Stamping it keeps the scope of the claim
    # visible to whoever reads the gate output (#305).
    try:
        with open(VOCAB_ASSET, encoding="utf-8") as fh:
            _v = json.load(fh)
        vocab_stamp = {"vocabulary_version": _v.get("vocabulary_version"),
                       "registered_terms": len(_v.get("terms", [])),
                       "registered_patterns": len(_v.get("patterns", []))}
    except (OSError, json.JSONDecodeError):
        vocab_stamp = None

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

    failing = [d for d, (v, _) in results.items() if v == "fail"]
    out = {"gate": "quality", "pass": not failing,
           "dimensions": {d: {"verdict": v, "locations": loc} for d, (v, loc) in results.items()},
           "failing_dimensions": failing}
    if vocab_stamp:
        out["dim3_inventory"] = vocab_stamp
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


def cmd_repair_hop(args):
    """Missing-input repair hop (Story 13.63, SPEC-article-draft-pipeline
    missing-input repair route). A review or quality-gate finding classified
    `missing-input` routes back ONE bounded hop to a scoped re-harvest or a
    single bounded owner-elicitation question, then re-enters the pipeline.

    Input is the finding's `Upstream:` remediation, exactly one of:
      re-harvest <scoped target>   -> re-enter harvest, narrowed to <target>
      ask <one bounded question>   -> re-enter the interview with one question

    This is the ONLY backward edge to harvest/interview beyond the rewrite
    route. It counts against the SAME two-cycle bound as rewrites and gate
    revisions (Story 13.64): `--cycle` is the number of cycles already spent on
    this draft. When the cap is reached, no third hop is taken — the
    unrepaired missing-input finding becomes a PUBLISH BLOCKER instead, exactly
    as an unresolved rubric/config blocker forces "not publishable".
    """
    if args.cycle < 0:
        sys.stderr.write("error: --cycle must be >= 0\n")
        return 2
    remediation = args.upstream.strip()
    # Cap: the hop shares the two-cycle bound. At the cap, no third hop —
    # surface the unrepaired gap as a publish blocker (Story 13.64).
    if args.cycle >= TWO_CYCLE_BOUND:
        out = {
            "stage": "repair-hop",
            "action": "publish-blocker",
            "publishable": False,
            "cycle": args.cycle,
            "cap": TWO_CYCLE_BOUND,
            "blocker": f"unrepaired missing-input finding ({remediation})",
            "reason": (f"missing-input gap still unrepaired after "
                       f"{TWO_CYCLE_BOUND} cycles — the shared bound forbids a "
                       "third hop; route to the completion summary's "
                       "publish-blocker bucket (CAP-6), never a further hop"),
        }
        print(json.dumps(out, indent=2))
        return 0
    m = re.match(r"^(?:Upstream:\s*)?re-harvest\s+(?P<target>\S.*)$",
                 remediation, re.IGNORECASE)
    m = re.match(r"^(?:Upstream:\s*)?re-harvest\s+(?P<target>\S.*)$",
                 remediation, re.IGNORECASE)
    if m:
        target = m.group("target").strip()
        out = {
            "stage": "repair-hop",
            "action": "re-harvest",
            "scope": target,
            "next_stage": "harvest",
            "cycle": args.cycle + 1,
            "cap": TWO_CYCLE_BOUND,
            "note": ("re-harvest the scoped target only (declared-scope boundary "
                     "and pin rules unchanged); new facts are pinned like any "
                     "Stage-1 fact, and a policy line never becomes a SOURCE"),
        }
        print(json.dumps(out, indent=2))
        return 0
    m = re.match(r"^(?:Upstream:\s*)?ask\s+(?P<q>\S.*)$",
                 remediation, re.IGNORECASE)
    if m:
        question = m.group("q").strip().rstrip(".")
        out = {
            "stage": "repair-hop",
            "action": "elicit",
            "next_stage": "interview",
            "cycle": args.cycle + 1,
            "cap": TWO_CYCLE_BOUND,
            "question": {
                "id": "repair-hop",
                "text": f"{question}?" if not question.endswith("?") else question,
                "from_repair_hop": True,
            },
            "note": ("exactly one owner-facing question under the proposal "
                     "contract; the answer is recorded as owner judgment "
                     "(interview provenance), never a SOURCE"),
        }
        print(json.dumps(out, indent=2))
        return 0
    sys.stderr.write(
        "error: a missing-input Upstream: remediation must be exactly one of "
        "`re-harvest <target>` or `ask <question>` (Story 13.63); got "
        f"{remediation!r}\n")
    return 2


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
    """realpath of the git toplevel of cwd, or None.

    The None return is INTENTIONAL and deliberately unlike the mirrored
    resolvers' exit-2 contract (#309, reconciled 2026-07-17). It has exactly one
    caller: the `--create-out` guard, which asks "is this output directory
    inside the host repo?" to decide whether writing there needs explicit
    consent. Outside a git repo the honest answer is "not inside the host", and
    the guard then demands consent — the safe branch. Exiting 2 there would
    abort a legitimate run over a question the guard is allowed to answer
    conservatively. It is NOT a host-root resolver and must not be used as one:
    resolution goes through resolve-paths.host_root, which fails closed.
    """
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


def _strip_emission_trailer(text):
    """Strip the persisted canonical's emission trailer (Story 13.68) before
    hashing or projecting, normalizing exactly the way `complete` normalizes
    before it hashes — so a variant emitted from the persisted canonical
    records the SAME canonical_sha256 the trailer itself carries (one hash
    convention, not two). A trailer-less draft passes through byte-identical.
    """
    if _EMISSION_TRAILER_RE.search(text):
        return _EMISSION_TRAILER_RE.sub("", text).rstrip("\n") + "\n"
    return text


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
        drafts_dir = _resolve_drafts_dir(args.root)
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
            drafts_dir = os.path.realpath(_resolve_drafts_dir(args.root))
            src = None if args.draft == "-" else os.path.realpath(args.draft)
            if src is None or not src.startswith(drafts_dir + os.sep):
                try:
                    slug_hint = _read_frontmatter(text)[0].get("slug") or "<slug>"
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
    text = _strip_emission_trailer(text)

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
    out = _staleness_report(text, paths=list(args.variants) if args.variants else None,
                            out_dir=args.out, root=args.root)
    print(json.dumps(out, indent=2))
    return 0


def _staleness_report(text, paths=None, out_dir=None, root=None):
    """The staleness comparison itself — canonical content hash vs each
    variant's recorded emission hash — shared by the `variant-staleness`
    command and by `review-reentry` (Story 13.70), so review's stale marking
    can never drift from the standalone check. Returns the report dict."""
    # The persisted canonical carries its own emission trailer (Story 13.68);
    # hash the trailer-stripped content — the one shared hash convention.
    text = _strip_emission_trailer(text)
    canonical_sha = hashlib.sha256(text.encode("utf-8")).hexdigest()

    if paths is None:
        out_dir = out_dir if out_dir else _resolve_drafts_dir(root)
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
    return out


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


# --- CAP-7 policy-result classification (Story 13.75, #365) -------------------
#
# The interview rationales that count as POLICY-PRIORITY for selection: the
# #302 reserved slot, the presentation lead, and the staging-candidate emitter
# all key on membership here, so a reconciliation item ranks at least as high
# as a policy-seeded tension item everywhere a tension item ranks.
POLICY_PRIORITY_RATIONALES = ("policy-seed", "policy-reconciliation")

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
_policy_subjects = _load("policy_subjects.py")
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

      determined / constrained — structurally present in the output but
        EMPTY-BY-DEFAULT: they activate as comparable subjects gain
        determining/excluding semantics in the table (the extension point).
        The shipped EN-topology detector emits `conflict`.
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

    rf = _load("render-frontmatter.py")
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
        items = _load_json_state(args.items, "candidate policy items")
        if isinstance(items, dict) and "items" in items:
            items = items["items"]
        if not isinstance(items, list):
            sys.stderr.write("error: --items must be a JSON array of interview items\n")
            return 2
    if args.facts:
        # Reserved: repo-state positions join as the subject table gains
        # repo-comparable rows; loading validates the input exists and parses.
        _load_json_state(args.facts, "harvest state")

    # 1. Conflict detection over the declared comparable subjects (shared
    # detector — the conformance gate runs the same one).
    conflicts = _policy_subjects.detect_conflicts(surface_lines, cfg, config_version)

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
        reconciliation_items.append({
            "id": rid, "gap_type": "reconciliation",
            "positions": [c["policy"], c["config"]],
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

    # 2. Classify every candidate item.
    classified = []
    open_items = []
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
        classified.append({"id": item.get("id"), "class": "open", "item": item})
        open_items.append(item)

    out = {
        "stage": "classify-policy",
        "pin": pin,
        "config_version": config_version,
        "classified": classified,
        "reconciliation_items": reconciliation_items,
        "determined": [],
        "constrained": [],
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
        data = _load_json_state(args.classification, "classify-policy output")
        rec_items = data.get("reconciliation_items", []) \
            if isinstance(data, dict) else []
        answers = {}
        if args.answers:
            parsed = _load_json_state(args.answers, "answers batch")
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
        wap = _load("write-article-plan.py")
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

    Selection reserves ONE of the <=5 slots for the highest-priority
    policy-seeded tension item whenever one survives validation (#302): it
    displaces the lowest-priority survivor, never extends the cap. Without the
    reservation, a repo with >=5 confirmed NEEDS-OWNER gaps silently degrades
    to a generic interview no matter what the policy probe found.
    """
    framework = args.framework.upper()
    if framework.lower() in SLIM_PROFILE_FRAMEWORKS:
        sys.stderr.write(
            "error: the working-note profile (F5) runs slim — it has no "
            "interview stage by ratified contract (SPEC-article-frameworks, "
            "working-note ratification: no 5-question interview). `consume "
            "--framework working-note` routes straight to fill.\n")
        return 2
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
        if item.get("gap_type") == "reconciliation":
            # A CAP-7 conflict-classified subject (Story 13.75): the explicit
            # reconciliation question, carrying every disagreeing position.
            # Ranks with the policy-seeded tension items everywhere they rank
            # (reserved slot, presentation lead, staging-candidate emitter).
            rec.update(rationale="policy-reconciliation",
                       positions=item["positions"])
        elif item.get("seed"):
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
                   else 1 if r["rationale"] in POLICY_PRIORITY_RATIONALES else 2)
    # ONE SLOT IS RESERVED for the highest-priority policy-seeded tension item
    # whenever one exists (#302; SPEC-article-draft-pipeline CAP-2 amended
    # 2026-07-17). Priority order alone starves seeds on any repo whose harvest
    # yields >= QUESTION_BUDGET NEEDS-OWNER gaps — i.e. exactly the fact-rich
    # repos the seam was built for — and the starvation is silent: the editorial
    # anchor (13.38) resolves to a routine slot answer with policy_seeded false,
    # and the staging-candidate emitter (seam CAP-4) writes an empty file. The
    # cap itself is untouched: the reserved item DISPLACES the lowest-priority
    # survivor, it never extends the budget.
    if len(survivors) > QUESTION_BUDGET:
        seeds = [r for r in survivors
                 if r.get("rationale") in POLICY_PRIORITY_RATIONALES]
        if seeds and QUESTION_BUDGET >= 1:
            keep = {id(seeds[0])}          # the reservation
            for r in survivors:            # fill the rest in priority order
                if len(keep) >= QUESTION_BUDGET:
                    break
                keep.add(id(r))
            survivors = [r for r in survivors if id(r) in keep]
        else:
            survivors = survivors[:QUESTION_BUDGET]

    # Presentation reorder (Story 13.30, CAP-4): selection above is untouched;
    # the asked set is SHOWN claim/angle → audience → significance → color.
    # Python's sort is stable, so ties keep the selection order within a slot.
    presented = sorted(survivors, key=presentation_slot)

    questions = [{"id": r["id"], "text": r["text"], "topic": r["topic"],
                  "from_gap": r["outcome"] == "recommended", "outcome": r["outcome"],
                  "rationale": r["rationale"],
                  **({"grounding": r["grounding"]} if "grounding" in r else {}),
                  **({"seed": r["seed"]} if "seed" in r else {}),
                  **({"positions": r["positions"]} if "positions" in r else {})}
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
    "ratified": "interview",   # a recalled policy default the owner accepted as-is
    "skipped": None,
}

# Dispositions that record accepting a policy-recalled recommended default
# (Story 13.60, SPEC-policy-editorial-direction CAP-6). Unlike `approved`
# (which inherits the recommendation's fact-sheet pointers as `sourced`), a
# ratified default is OWNER JUDGMENT: it never inherits the policy pointer as a
# SOURCE — the seed pointer stays in the `seed<-`/`consulted:` audit records.
DEFAULT_DISPOSITIONS = {"ratified", "modified", "replaced"}


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
    else:  # modified / replaced / answered / ratified
        if not text:
            return None, f"a {disposition} answer must carry the owner's text (pass --text)"
        if pointers:
            # `ratified` is the recall-then-ratify accept path (Story 13.60): a
            # policy default the owner took as-is is owner judgment, so — like
            # modified/replaced — it inherits NO policy pointer as a SOURCE. The
            # recalled pointer lives only in the seed/consulted audit records.
            owner_judgment = ("a ratified default is owner judgment; the recalled "
                              "policy pointer stays in the seed/consulted audit and "
                              "never becomes a SOURCE"
                              if disposition == "ratified"
                              else f"a {disposition} answer is owner judgment "
                                   "(interview-sourced)")
            return None, f"{owner_judgment}; it carries no source pointers"

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
            if "positions" in t:
                entry["positions"] = [{"authority": p["authority"],
                                       "pointer": p["pointer"]}
                                      for p in t["positions"]]
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
        if "positions" in t:
            # Reconciliation ask (Story 13.75, CAP-7 conflict class): every
            # disagreeing position rides into the journal, parallel to seed<-,
            # so the reconciliation is attributable from run state.
            entry["positions"] = [{"authority": p["authority"],
                                   "pointer": p["pointer"]}
                                  for p in t["positions"]]
        entries.append(entry)

    # The /ask-style consulted: line the run artifact must end with (CAP-5):
    # pin + seed -> question map when the run was policy-seeded, else an
    # explicit `none` naming why (unset vs unavailable, from --policy-note).
    seeds = [(t["seed"]["pointer"], t["id"]) for t in triage
             if t.get("seed") and t["id"] in asked_ids]
    # Reconciliation asks: their policy-authority positions are served lines
    # too, so they join the same audited pointer → question mapping (the
    # config-authority side carries a configVersion, not the run's pin — it
    # stays in the journal entry's positions, never the consulted: line).
    for t in triage:
        if t.get("positions") and t["id"] in asked_ids:
            for pos in t["positions"]:
                if pos.get("authority") == "policy" and "@" in str(pos.get("pointer", "")):
                    seeds.append((pos["pointer"], t["id"]))
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
        if q.get("rationale") not in ("policy-seed", "policy-reconciliation"):
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
        if q.get("rationale") == "policy-reconciliation":
            # A config↔policy reconciliation decision (Story 13.75, CAP-7):
            # the owner just arbitrated between a served ratified line and an
            # authoritative config key. Framed as exactly that — analogous to
            # the #306 stale-seed framing — with every position it decided
            # between, so the hub receives a proposed policy change carrying
            # both sides, never a "resolution" missing its context. The answer
            # is NEVER treated as current policy by this run's later stages
            # (that plan-side gate is Story 13.76's).
            positions = "; ".join(
                f"{p.get('authority', '?')}: \"{p.get('quote', '')}\" — "
                f"{p.get('pointer', '?')}" for p in q.get("positions", []))
            tags = ["config-policy-reconciliation"] + (args.tag or [])
            blocks.append("\n".join([
                "<!-- staging-candidate -->",
                "---",
                f"slug: {args.created}-{args.source_repo}-{gist}-{qid}",
                f"created: {args.created}",
                f"source_repo: {args.source_repo}",
                "perishable: true",
                f"tags: [{', '.join(tags)}]",
                "---",
                f"Q: Config↔policy reconciliation decision — {q['text']} "
                f"(positions: {positions})",
                f"Decision: {text}",
            ]))
            continue
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
    # Slim-profile routing (Story 13.89 / #412): the working-note profile has
    # no interview stage by ratified contract — consume routes straight to
    # fill. NEEDS-OWNER entries are still carried in the state (they surface
    # as [VERIFY]/blocker material at fill), just never as interview questions.
    if args.framework:
        key = resolve_framework(args.framework)
        if key is None:
            sys.stderr.write(
                f"error: invalid article type {args.framework!r} for --framework "
                "(same closed set as `start`).\n")
            return 2
        if key in SLIM_PROFILE_FRAMEWORKS:
            state["next_stage"] = "fill"
            state["profile"] = "slim"
    print(json.dumps(state, indent=2))
    return 0


def cmd_start(args):
    _rp = _load("resolve-paths.py")
    state, code = _run_state(args.framework, args.sources, _rp.host_root(args.root))
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


def cmd_progress(args):
    """Record SUB-stage progress inside a long stage (Story 13.83, #388): after
    each completed unit of work — a pinned-source batch in harvest, a filled
    section in stage 3 — upsert it into `<ws>/checkpoint.json` under
    `progress.<stage>.done`, so a mid-stage casualty resumes from the last
    persisted boundary instead of replaying the whole stage. The upsert MERGES
    into the existing checkpoint (run_state and any stage state are preserved)
    and is idempotent per item. Record a unit only AFTER its artifacts are
    durably written — the recording is the boundary, so a half-written unit
    must never be marked done. A stage's normal completion checkpoint then
    overwrites the file, clearing its sub-stage progress."""
    if not os.path.isdir(args.ws):
        sys.stderr.write(f"error: run workspace does not exist: {args.ws}\n")
        return 1
    path = _checkpoint_path(args.ws)
    state = {}
    if os.path.isfile(path):
        try:
            with open(path, encoding="utf-8") as f:
                state = json.load(f)
        except (OSError, json.JSONDecodeError) as e:
            sys.stderr.write(f"error: existing checkpoint unreadable: {e}\n")
            return 1
    current = state.get("next_stage")
    if current == DONE_STAGE:
        sys.stderr.write(
            "error: run is complete (next_stage: done) — sub-stage progress "
            "cannot reopen it\n")
        return 1
    if current is not None and current != args.stage:
        sys.stderr.write(
            f"error: run is at next_stage {current!r}, not {args.stage!r} — "
            "sub-stage progress is recorded only for the stage in progress "
            "(a completed stage's checkpoint already points past it)\n")
        return 1
    state.setdefault("next_stage", args.stage)
    done = state.setdefault("progress", {}).setdefault(args.stage, {}).setdefault("done", [])
    added = [d for d in args.done if d not in done]
    done.extend(added)
    if args.stop_note:
        # Orderly budget stop (Story 13.85, #388): the stage persisted at this
        # boundary and exits clean. The note is the CAP-6 partial-progress
        # record — the resumed invocation (and its completion summary) relays
        # it. Cleared like the rest of sub-stage state by the stage's normal
        # completion checkpoint.
        state["budget_stop"] = {"stage": args.stage, "note": args.stop_note}
    else:
        # A recording without a stop-note means the run is working again —
        # a stale stop note from the previous invocation no longer describes
        # the checkpoint and is dropped.
        state.pop("budget_stop", None)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2)
    os.replace(tmp, path)
    out = {"stage": args.stage, "done": done, "added": added}
    if args.stop_note:
        out["budget_stop"] = state["budget_stop"]
    print(json.dumps(out))
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
            if os.path.islink(os.path.join(base, run_id)):
                continue  # the `latest` shorthand (F40) is not a resumable run
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
            # `cwd=root` — never `root or None` (#309). Falling back to None ran
            # `git tag` against the RAW PROCESS CWD while workspace and config
            # resolution used the resolved toplevel, so invoked from a
            # subdirectory (or with cwd outside the repo) the gate could check a
            # different directory than the run was keyed to. Callers resolve the
            # root before calling; one root per run, no side channel.
            r = subprocess.run(["git", "tag"], cwd=root,
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
    # `root` MUST already be resolved (resolve-paths host_root) — the entry gate
    # below runs git against it, and a raw --root string or None would reopen
    # the side channel #309 closed. Callers resolve once, then pass it down.
    """Build the stage-0 run-state (framework + classified sources), or return
    (None, exit_code) on a framework error — shared by `start` and `stage0`."""
    key = resolve_framework(framework)
    if key is None:
        labels = "; ".join(
            f'"{INTENT_LABELS[k]}" ({k.upper()})' for k in sorted(FRAMEWORKS))
        sys.stderr.write(
            f"error: invalid article type {framework!r} — this intent maps to "
            "no framework. The category set is ratified and closed "
            "(SPEC-article-frameworks: the four categories plus the "
            f"working-note profile — all five below). Valid: {labels}.\n"
            f"{nearest_fit(framework)}.\n"
            "Nothing started.\n")
        return None, 2
    framework_file = os.path.join("skills", "draft-article", "frameworks", FRAMEWORKS[key])
    if not os.path.isfile(os.path.join(plugin_root(), framework_file)):
        sys.stderr.write(f"error: framework asset missing: {framework_file}\n")
        return None, 1
    gate_ok, gate_msg = _entry_gate_ok(key, framework_file, root)
    if not gate_ok:
        sys.stderr.write(f"error: {gate_msg}\nNothing started.\n")
        return None, 2
    state = {
        "next_stage": "harvest",
        "framework": key.upper(),
        "framework_file": framework_file,
        "sources_raw": list(sources),
        "sources": [{"value": t, "form": classify(t)} for t in sources],
    }
    if key in SLIM_PROFILE_FRAMEWORKS:
        state["profile"] = "slim"
    return state, 0


# --- Completion gate: durable dual-product persistence (Story 13.68) ---------
# GitHub #361: a run could report "complete and verified" while the canonical
# draft existed only as a workspace copy. The 2026-07-18 SPEC amendment
# (SPEC-article-draft-pipeline; SPEC-platform-variants CAP-1) declares the
# run's products — drafts/{slug}.md AND plans/{slug}.md — and makes their
# persistence a hard completion gate: both persisted before the run may report
# completion; a failed write of either is a hard error. `complete` is the ONLY
# sanctioned way to finish a draft run — the SKILL calls it instead of
# hand-writing the final `next_stage: done` checkpoint.

# The emission trailer the canonical carries — the SAME trailer the variants
# stage appends to every emitted variant (one hash convention, not two): the
# hash is sha256 over the draft text WITHOUT the trailer, so a variant emitted
# from the trailer-stripped canonical records the same canonical_sha256.
_EMISSION_TRAILER_RE = re.compile(
    r"\n*<!-- writing-assistant: canonical-sha256=[0-9a-f]{64} -->\s*$")


class _CanonicalWriteError(Exception):
    """A canonical-draft persistence failure: `.path` is the destination the
    write was for, `.reason` names what went wrong."""
    def __init__(self, path, reason):
        super().__init__(reason)
        self.path = path
        self.reason = reason


def _persist_canonical(text, slug, root):
    """Persist `text` as the canonical draft at `<output.drafts>/<slug>.md`,
    stamped with the emission trailer — THE one canonical write path (Story
    13.68), reused verbatim by review's post-arbitration re-entry (Story 13.70)
    so a reviewed canonical can never be persisted under a different trailer or
    hash convention than the completion gate's. Strips any existing trailer
    BEFORE hashing so the hash is always over the draft content alone (a re-run
    over the persisted canonical verifies to the same hash instead of hashing
    its own trailer). Atomic (temp + os.replace). Returns
    (canonical_path, canonical_sha); raises _CanonicalWriteError on failure
    (an undeclared output.drafts still exits via _resolve_drafts_dir's own
    named SystemExit)."""
    out_dir = _resolve_drafts_dir(root)   # undeclared → named SystemExit
    canonical_path = os.path.abspath(os.path.join(out_dir, f"{slug}.md"))
    if not os.path.isdir(out_dir):
        raise _CanonicalWriteError(
            canonical_path,
            f"the resolved output.drafts directory does not exist: {out_dir}")
    body = _EMISSION_TRAILER_RE.sub("", text).rstrip("\n") + "\n"
    canonical_sha = hashlib.sha256(body.encode("utf-8")).hexdigest()
    content = body + \
        f"\n<!-- writing-assistant: canonical-sha256={canonical_sha} -->\n"
    try:
        tmp = canonical_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write(content)
        os.replace(tmp, canonical_path)
    except OSError as e:
        raise _CanonicalWriteError(canonical_path, f"write failed: {e}")
    return canonical_path, canonical_sha


def cmd_complete(args):
    """Finish a draft run through the dual-product completion gate (Story
    13.68). The declared products are two — the canonical draft at
    `<output.drafts>/<slug>.md` and the article plan at `plans/<slug>.md` —
    and BOTH must be durably persisted before completion may be reported:

      1. persist the workspace draft as the canonical, with the emission
         trailer `<!-- writing-assistant: canonical-sha256=<hex> -->` whose
         hash is sha256 over the draft content WITHOUT the trailer (the
         variants stage's convention, reused — one hash convention, not two);
      2. verify the plan exists at its resolved destination (write-article-
         plan.py `dest`); the schema-less user-scoped fallback COUNTS — the
         fallback changes where the plan lives, never whether it was written;
      3. only after both products verify, write the final `next_stage: done`
         checkpoint to the workspace (--ws).

    Any failure is a hard error naming the failed product and path, exits
    non-zero, and writes NO checkpoint — the run never reports complete over a
    workspace-only canonical, and partial success (canonical yes, plan no)
    still hard-errors. Idempotent: re-running over already-persisted products
    re-verifies (same hash, byte-identical canonical) and succeeds. The gate
    applies whenever `complete` runs, so a resumed pre-contract run is never
    grandfathered.
    """
    def product_error(product, path, reason):
        sys.stderr.write(
            f"error: completion gate: {product} not persisted — {reason} "
            f"(path: {path}). The run may not report completion, and the "
            "checkpoint does not record `next_stage: done`.\n")
        return 1

    # Product 1 — the canonical draft at <output.drafts>/<slug>.md.
    try:
        text = _read_text(args.draft)
    except OSError as e:
        return product_error("canonical draft (drafts/{slug}.md)", args.draft,
                             f"cannot read the workspace draft: {e}")
    try:
        canonical_path, canonical_sha = _persist_canonical(
            text, args.slug, args.root)
    except _CanonicalWriteError as e:
        return product_error("canonical draft (drafts/{slug}.md)",
                             e.path, e.reason)

    # Product 2 — the article plan at its resolved destination (SPEC-article-
    # plan). Resolution is delegated to the plan writer's own `dest` so the
    # two can never disagree; conforming articles repo and user-scoped
    # fallback are BOTH a successful plan write.
    here = os.path.dirname(os.path.realpath(__file__))
    cmd = [sys.executable, os.path.join(here, "write-article-plan.py"),
           "dest", "--slug", args.slug]
    if args.root:
        cmd += ["--root", args.root]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        return product_error(
            "article plan (plans/{slug}.md)", "(unresolved)",
            r.stderr.strip() or "could not resolve the plan destination")
    dest = json.loads(r.stdout)
    plan_path = os.path.abspath(dest["path"])
    if not os.path.isfile(plan_path):
        return product_error(
            "article plan (plans/{slug}.md)", plan_path,
            "no plan exists at the resolved destination — write it first "
            "(write-article-plan.py write --slug " + args.slug + ")")

    # Both products verified — NOW (and only now) the run may be marked done.
    checkpoint_path = None
    if args.ws:
        if not os.path.isdir(args.ws):
            sys.stderr.write(f"error: run workspace does not exist: {args.ws}\n")
            return 1
        checkpoint_path = _checkpoint_path(args.ws)
        tmp = checkpoint_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"stage": "complete", "next_stage": DONE_STAGE}, f,
                      indent=2)
        os.replace(tmp, checkpoint_path)

    # Both persisted paths, absolute and copy-pasteable — the completion
    # summary relays them under informational notes.
    out = {
        "stage": "complete",
        "next_stage": DONE_STAGE,
        "slug": args.slug,
        "products": {
            "canonical": {"path": canonical_path,
                          "canonical_sha256": canonical_sha},
            "plan": {"path": plan_path,
                     "conforming": dest.get("conforming"),
                     "fallback": dest.get("fallback")},
        },
        "checkpoint": checkpoint_path,
    }
    print(json.dumps(out, indent=2))
    return 0


# --- Review post-arbitration re-entry (Story 13.70) --------------------------
# GitHub #371, umbrella #362: a 2026-07-18 review run ended an arbitration
# round that applied edits by hand-writing the done/reviewed checkpoint — over
# a provenance map with 5 anchors dangling on blank lines, with review-authored
# sentences never classified, and with a variant auto re-emitted. The SPEC
# amendments (SPEC-article-review "Post-arbitration re-entry";
# SPEC-platform-variants CAP-3: review never re-emits) make the ordered
# sequence mechanical: persist → revalidate → report scoped checks → mark
# variants stale → STOP. `review-reentry` IS that sequence, and it is the only
# writer of the review done/reviewed checkpoint for a round with applied edits:
# a done/reviewed checkpoint over an INVALID map is impossible because the
# command that validates the map is the command that writes the checkpoint.

def cmd_review_reentry(args):
    """Post-arbitration re-entry into the gate regime (Story 13.70). Invoked by
    the review SKILL after an arbitration round that applied >=1 accepted
    finding, with the edited draft and the provenance map rebuilt against it.
    The ordered sequence, stopping at the first failure:

      (a) persist the reviewed canonical to `<output.drafts>/<slug>.md` via
          the SAME write path as the draft flow's `complete` gate
          (`_persist_canonical` — one write path, one trailer convention);
      (b) structurally validate the rebuilt map against the edited draft,
          anchors required (the `provenance --map --draft` checks, reused);
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

    An invalid map is a refusal: non-zero, named error, NO checkpoint — the
    dangling-anchor-under-done/reviewed failure (#362) cannot recur. With
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

    # (a) Persist the reviewed canonical — the completion gate's write path.
    try:
        text = _read_text(args.draft)
    except OSError as e:
        sys.stderr.write(
            f"error: review-reentry: cannot read the edited draft: {e}\n")
        return 1
    try:
        canonical_path, canonical_sha = _persist_canonical(
            text, args.slug, args.root)
    except _CanonicalWriteError as e:
        sys.stderr.write(
            "error: review-reentry: reviewed canonical not persisted — "
            f"{e.reason} (path: {e.path})\n")
        return 1

    # (b) Structurally validate the rebuilt map against the edited draft —
    # anchors required, exactly the `provenance --map --draft` standard.
    try:
        map_text = _read_text(args.map)
    except OSError as e:
        sys.stderr.write(
            f"error: review-reentry: cannot read the rebuilt map: {e}\n")
        return 1
    draft_lines = _strip_emission_trailer(text).splitlines()
    try:
        entries = parse_provenance_map(map_text)
        tally, problems = _provenance_problems(entries, draft_lines)
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
                      "draft (`quality-gate --draft --map`)",
        })

    # (d) Mark existing variants stale — the staleness comparison, reused,
    # over the just-persisted canonical (its trailer-stripped hash).
    out_dir = os.path.dirname(canonical_path)
    variant_paths = [
        os.path.join(out_dir, f) for f in sorted(os.listdir(out_dir))
        if f.startswith(f"{args.slug}.") and f.endswith(".md")
        and f != f"{args.slug}.md"]
    staleness = _staleness_report(
        open(canonical_path, encoding="utf-8").read(), paths=variant_paths)
    stale_variants = [v for v in staleness["variants"]
                      if v["status"] != "fresh"]

    # (e) STOP — nothing is emitted. Write the done/reviewed checkpoint (this
    # command is its only sanctioned writer for a round with applied edits).
    checkpoint_path = _checkpoint_path(args.ws)
    tmp = checkpoint_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"stage": "review", "next_stage": DONE_STAGE,
                   "reviewed": True}, f, indent=2)
    os.replace(tmp, checkpoint_path)

    out = {
        "stage": "review-reentry",
        "next_stage": DONE_STAGE,
        "slug": args.slug,
        "applied": args.applied,
        "canonical": {"path": canonical_path,
                      "canonical_sha256": canonical_sha},
        "map_validation": {"ok": True, "entries": len(entries),
                           "tally": tally},
        "required_checks": required_checks,
        "stale_variants": stale_variants,
        # Review never emits or re-emits a variant (CAP-3) — re-emission is a
        # fresh explicit publish decision through the standalone variants flow.
        "emitted_variants": [],
        "re_emission": f"variants --slug {args.slug} "
                       "(owner publish decision; skills/draft-article/variants.md)",
        "checkpoint": checkpoint_path,
    }
    print(json.dumps(out, indent=2))
    return 0


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
    # ONE resolution for the whole of stage 0 (#309): the entry gate, the
    # target line, and the workspace all key to this same value. Resolving
    # twice would be two chances to disagree.
    rp = _load("resolve-paths.py")
    root = rp.host_root(args.root)
    # 2. Framework check + entry-gate precondition (before minting a workspace).
    run_state, code = _run_state(args.framework, args.sources, root)
    if run_state is None:
        return code
    # 3. Workspace autostart (mint or resume).
    # The resolved target rides in stage 0's output so the run's first
    # owner-visible line can name the repository it is about to operate on —
    # before scope is read, a workspace is minted, or a token is spent (#309).
    out = {"config_ok": True, "target": root, "run_state": run_state}
    out.update(_autostart(root))
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
    sp.add_argument("--framework", default=None,
                    help="the run's article type (same closed set as `start`); a "
                         "slim-profile framework (working-note) routes consume's "
                         "next_stage to fill — no interview stage (Story 13.89)")
    sp = sub.add_parser("checkpoint", help="persist a completed stage's state to <ws>/checkpoint.json (Story 13.5)")
    sp.add_argument("--ws", required=True, help="the run workspace ($WS) to checkpoint into")
    sp.add_argument("state", nargs="?", default="-", help="the stage's output state JSON, or - for stdin")
    sp = sub.add_parser("resume", help="report where to resume a run from its workspace checkpoint (Story 13.5)")
    sp.add_argument("--ws", required=True, help="the run workspace ($WS) to resume")
    sp = sub.add_parser("progress", help="record sub-stage progress (a completed unit inside a long stage) "
                                         "into the workspace checkpoint (Story 13.83)")
    sp.add_argument("--ws", required=True, help="the run workspace ($WS)")
    sp.add_argument("--stage", required=True, help="the stage in progress (e.g. harvest, fill)")
    sp.add_argument("--done", required=True, nargs="+",
                    help="completed unit id(s) — e.g. source names or section slugs; "
                         "idempotent, batchable in one call")
    sp.add_argument("--stop-note", metavar="TEXT",
                    help="record an orderly budget stop at this boundary (Story 13.85): "
                         "the partial-progress note the resumed run relays — pass it on "
                         "the final recording before a clean exit")
    sp = sub.add_parser("complete", help="finish the run through the dual-product completion gate (Story 13.68)")
    sp.add_argument("--draft", required=True, help="the workspace draft to persist as the canonical, or - for stdin")
    sp.add_argument("--slug", required=True, help="the article slug — names both products (<slug>.md)")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")
    sp.add_argument("--ws", help="run workspace; the final `next_stage: done` checkpoint is written here "
                                 "only after BOTH products verify")
    sp = sub.add_parser("review-reentry",
                        help="post-arbitration re-entry: persist the reviewed canonical, revalidate "
                             "the rebuilt map, report scoped checks, mark variants stale, STOP (Story 13.70)")
    sp.add_argument("--draft", required=True, help="the edited (reviewed) draft to persist as the canonical")
    sp.add_argument("--map", required=True, help="the provenance map rebuilt against the edited draft")
    sp.add_argument("--slug", required=True, help="the article slug — names the canonical and its variants")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")
    sp.add_argument("--ws", required=True, help="run workspace; the done/reviewed checkpoint is written "
                                                "here only after the rebuilt map validates")
    sp.add_argument("--applied", type=int, default=1,
                    help="accepted findings applied this round (default 1); 0 = strict no-op — "
                         "nothing persisted, nothing marked stale, no checkpoint")
    sp.add_argument("--rubric-applied", action="store_true",
                    help="a rubric-mapped finding was applied — the required-checks worklist adds "
                         "the quality gate's mechanical dimensions")
    sp = sub.add_parser("autostart", help="auto-resume the newest in-progress run, else mint a fresh one (Story 13.12)")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")
    sp = sub.add_parser("stage0", help="fold Stage 0 into one call: config validation + framework + autostart (Story 13.13)")
    sp.add_argument("framework")
    sp.add_argument("sources", nargs="*")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")
    sp = sub.add_parser("classify-policy",
                        help="CAP-7 policy-result classification: a mechanical "
                             "pre-step between the policy read and `interview` "
                             "(Story 13.75) — emits reconciliation items for "
                             "config↔policy conflicts, supersedes re-typed "
                             "conflict candidates, passes everything else "
                             "through open")
    sp.add_argument("--surface", required=True,
                    help="the policy reader's `read` output (pin line + "
                         "line-numbered files)")
    sp.add_argument("--items", help="candidate policy items JSON "
                                    "(seam-formats.md §2), or - for stdin")
    sp.add_argument("--facts", help="harvest-state JSON (reserved: repo-state "
                                    "positions as subjects gain repo comparability)")
    sp.add_argument("--config-json", help="resolved config as JSON (FILE or - for stdin)")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd)")
    sp.add_argument("--global-config")
    sp.add_argument("--repo-config")
    sp.add_argument("--config-version",
                    help="the configVersion cited on config-authority positions "
                         "(default: sha256 prefix of the resolved config JSON)")
    sp = sub.add_parser("policy-block-check",
                        help="Stage 2→3 precondition (Story 13.77): draft "
                             "generation blocks on an unresolved "
                             "config↔policy conflict or a stale plan — "
                             "publish-blocker payload + block checkpoint; "
                             "conformant/open (and generic mode) proceed")
    sp.add_argument("--classification",
                    help="the `classify-policy` output JSON (FILE or -); an "
                         "unanswered reconciliation item blocks")
    sp.add_argument("--answers",
                    help="recorded answer records (JSON list) — an answered "
                         "reconciliation (incl. a reversal routed to staging) "
                         "unblocks; a skip does not")
    sp.add_argument("--plan",
                    help="an existing article plan (the resumed-run half): "
                         "its recorded policy_conformance blocks on "
                         "conflict/stale")
    sp.add_argument("--surface",
                    help="fresh policy surface (the reader's `read` output) — "
                         "with --plan, recompute conformance at the current "
                         "pin (a re-consult clears a recorded stale)")
    sp.add_argument("--config-json", help="resolved config as JSON "
                                          "(FILE or - for stdin)")
    sp.add_argument("--root", help="host-repo root (default: git top-level of cwd)")
    sp.add_argument("--config-version",
                    help="the cited configVersion for the recompute")
    sp.add_argument("--staging",
                    help="the run's staging-candidates.md — a covered "
                         "reversal is conformant as a proposed policy change")
    sp = sub.add_parser("interview")
    sp.add_argument("--framework", required=True)
    sp.add_argument("--items", help="candidate interview-item JSON (e.g. policy-seeded questions); "
                                    "schema-validated before triage — invalid items halt the stage")
    sp.add_argument("state", nargs="?", default="-", help="stage-1 pipeline state JSON, or - for stdin")
    sp = sub.add_parser("answer")
    sp.add_argument("--id", help="the question id this answer keys to (single-answer form)")
    sp.add_argument("--disposition",
                    help="approved | modified | replaced | answered | ratified | skipped "
                         "(single-answer form; `ratified` = a recalled policy default "
                         "accepted as-is, recorded as owner judgment)")
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
    sp.add_argument("--draft", help="the draft the map describes; enables anchor validation "
                                    "(every position must carry `[L<line>]` resolving to a "
                                    "real non-blank line — #304)")
    sp = sub.add_parser("quality-gate")
    sp.add_argument("--draft", default="-", help="the filled draft, or - for stdin")
    sp.add_argument("--map", help="the sidecar provenance map (for the stitched-fact-sheet check)")
    sp.add_argument("--judge", help="rubric judge verdicts for dims 1-2: `dimN: pass|fail [locations]` "
                                    "per line, dim1 and dim2 each present; any other format exits 2 "
                                    "(judge verdicts unparseable), never a per-dimension fail. A "
                                    "`dim3:` line is accepted but advisory — dim3 is scanned")
    sp.add_argument("--audience-known", action="append", metavar="TERMS",
                    help="comma-separated repo-internal terms the ratified audience already "
                         "knows; excluded from the dim3 scan (repeatable). Audience judgment "
                         "enters once, as owner-ratified data — never re-judged per pass")
    sp.add_argument("--profile", choices=("full", "slim"), default="full",
                    help="gate profile: `full` (default) requires the dim1-2 rubric judge; "
                         "`slim` (working-note, Story 13.89) waives dims 1-2 by ratified "
                         "contract — mechanical dims 3-4 and audience still run")
    sp.add_argument("--cycle", type=int, default=1,
                    help="revision cycle (1 = first gate; 2 = the second/delta re-check, "
                         "#349). On cycle 2 the dim1-2 judge is scoped to cycle-1's failing "
                         "locations and may not raise a new interpretive finding")
    sp.add_argument("--prior-locations", metavar="LOCS",
                    help="cycle-1's failing dim1/dim2 locations (`;`-separated); on cycle 2, a "
                         "dim1/dim2 fail outside these is suppressed as interpretive drift")
    sp = sub.add_parser("verify-markers")
    sp.add_argument("draft", nargs="?", default="-", help="draft file, or - for stdin")
    sp.add_argument("--count", action="store_true", help="print the count of well-formed markers")
    sp = sub.add_parser("verify")
    sp.add_argument("draft", nargs="?", default="-", help="filled draft, or - for stdin")
    sp = sub.add_parser("reroute")
    sp.add_argument("--rewrites", type=int, required=True,
                    help="rewrites already applied to this section")
    sp.add_argument("--section", default="?", help="section identifier (for the routed question)")
    sp = sub.add_parser("repair-hop")
    sp.add_argument("--upstream", required=True,
                    help="a missing-input finding's Upstream: remediation "
                         "(`re-harvest <target>` or `ask <question>`)")
    sp.add_argument("--cycle", type=int, default=0,
                    help="cycles already spent on this draft (rewrites + gate "
                         "revisions + prior hops); at the two-cycle cap the hop "
                         "becomes a publish blocker (Story 13.64)")
    sp = sub.add_parser("variants")
    sp.add_argument("draft", nargs="?", default="-",
                    help="draft path, or - for stdin; must be the persisted "
                         "canonical inside the resolved output.drafts unless "
                         "--allow-external-draft is passed (Story 13.69)")
    sp.add_argument("--slug",
                    help="the sanctioned post-review form (Story 13.69): load "
                         "the persisted canonical <output.drafts>/<slug>.md "
                         "written by the draft flow's `complete` gate")
    sp.add_argument("--allow-external-draft", action="store_true",
                    help="TEST-ONLY escape for check harnesses: accept a "
                         "positional draft outside the resolved output.drafts "
                         "(production invocations use --slug)")
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
        "progress": cmd_progress,
        "stage0": cmd_stage0, "complete": cmd_complete,
        "classify-policy": cmd_classify_policy,
        "policy-block-check": cmd_policy_block_check,
        "review-reentry": cmd_review_reentry,
        "answer": cmd_answer, "journal": cmd_journal, "provenance": cmd_provenance,
        "staging-candidates": cmd_staging_candidates,
        "review-consulted": cmd_review_consulted,
        "quality-gate": cmd_quality_gate,
        "verify-markers": cmd_verify_markers, "verify": cmd_verify, "reroute": cmd_reroute,
        "repair-hop": cmd_repair_hop,
        "variants": cmd_variants,
        "variant-staleness": cmd_variant_staleness,
        "site-record": cmd_site_record,
    }[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
