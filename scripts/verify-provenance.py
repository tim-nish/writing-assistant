#!/usr/bin/env python3
"""verify-provenance — the independent provenance-map check (Story 11.2).

Validates the sidecar provenance map WITHOUT sharing the drafting context
(NFR13; `docs/harness-architecture.md` D2): the agent that wrote the text never
grades its own claim/narration boundary. This is a standalone script — not a
draft-pipeline subcommand — so it carries none of the drafting state; it reads
only the map, the declared fact-sheet pointer set, and the independent judge's
verdicts.

It splits cleanly into a MECHANICAL layer and a SEMANTIC layer:

  Mechanical (this script decides):
    - every `derived` claim's inherited pointers must RESOLVE to declared
      fact-sheet entries; an unresolvable pointer is a gate failure;
    - a `sourced` claim's pointer must resolve too;
    - `narration` / `verify` carry no pointer;
    - a claim typed `episode` — one about how something CAME TO BE — must
      carry at least one pin resolving to a TIME-AXIS source (Story 20.138,
      #1184 clause (iii)). This is a new PREDICATE on this shipped mechanism,
      not a new mechanism: the refusal is a finding like any other, so it is
      deny-never-warn and the Stage 3→4 gate blocks on it.

  Semantic (an independent cheap-tier judge decides; this script consumes its
  findings — the drafting agent never self-grades):
    - a `narration` sentence that asserts a checkable proposition fails the
      falsifiability test → gate failure;
    - a `derived` claim that adds one of the six forbidden categories
      (causality, significance, evaluation, comparison, intent, scope) →
      gate failure.
  The judge's verdicts arrive via --judge-findings (one `POS: reason` per line);
  --list-narration / --list-derived emit the sentences the judge must grade.

Fail-closed judge attestation (Story 13.67, #364): the verdicts file must open
with a structured attestation the judge echoes from the --list-* hand-off —

    attestation: draft-sha256=<hex64>
    graded: P1.S1,P1.S4,...        (repeatable; lines are unioned)

followed by the failure verdicts (none, when the judge found nothing). The
attestation binds the verdicts to the draft (content hash) and to the expected
worklist (every narration + derived position in the map). A comment-only file,
a graded set that does not cover the worklist, an unknown graded position, or
a draft-hash mismatch is an ATTESTATION FAILURE (exit 3), reported before any
grading result — absence of verdicts is never PASS, and "never judged" is
mechanically distinguishable from "judged clean".

SHARDED judging (Story 20.163, #1248 clause (3)): the judge may be fanned out
across isolated subagents, and each shard returns its OWN attested file.
`--judge-findings` (alias `--verdicts`) is therefore REPEATABLE — every shard
file opens with its own attestation binding the SAME `draft-sha256` and carries
its own `graded:` line, coverage is checked over the UNION of those lines, and
ANY hash disagreement fails the whole gate. A stale shard is "not judged",
never dropped.

CONCATENATION IS REFUSED. Two attestation headers inside ONE file used to parse
without complaint, last-wins — so a concatenation whose final shard was fresh
silently accepted a stale earlier shard, which is exactly the fail-open the
attestation exists to close. A file carrying more than one attestation header
is now an ATTESTATION FAILURE; shards arrive as separate `--verdicts` files.
A single file with exactly one attestation header behaves exactly as before.

Exit 0 with no findings = the map passes. Any finding = a gate failure, printed
as `POS: reason`, and a non-zero exit — the Stage 3→4 gate (Story 11.4) blocks
on it. Exit 2 = malformed map; exit 3 = attestation failure.
"""

import argparse
import hashlib
import importlib.util
import os
import re
import sys


def _load_rws():
    """The declared-source TYPE authority (`resolve-writing-sources.py`): which
    source types carry a time axis, and which type a fact-sheet pointer form
    resolves to. Loading it costs this script no drafting state (NFR13) — it is
    a pure classification table, and importing it is what keeps ONE copy of the
    type→time-axis mapping in the repository."""
    here = os.path.dirname(os.path.realpath(__file__))
    spec = importlib.util.spec_from_file_location(
        "rws", os.path.join(here, "resolve-writing-sources.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


rws = _load_rws()

PROV_CLASSES = ("sourced", "derived", "narration", "verify")
# A claim may declare WHAT KIND OF CLAIM it is, beside its provenance class
# (#1184 clause (iii)). `episode` — how something came to be — is admissible
# only against a time-axis source; `state` — how something currently is — is
# admissible against either class and is the default when nothing is declared.
CLAIM_TYPES = ("episode", "state")
ATTEST_LINE = re.compile(r"^attestation:\s*draft-sha256=(?P<hash>[0-9a-fA-F]{64})\s*$")
GRADED_LINE = re.compile(r"^graded:\s*(?P<positions>\S.*)$")
CARRIED_LINE = re.compile(r"^carried:\s*(?P<positions>\S.*)$")
# A prior hand-off entry: `POS [Lnn]: <payload>` (#738 delta basis).
WORKLIST_ENTRY = re.compile(r"^(?P<pos>\S+) \[L\d+\]: (?P<payload>.*)$")
# `POS ~ "<quoted>": reason` — the judge echoing the sentence it graded.
JUDGE_ECHO = re.compile(r'^(?P<pos>[^~:]+)~\s*"(?P<quote>[^"]*)"\s*:\s*(?P<reason>.*)$')
# Positions may carry a line anchor — `P1.S1[L7]` (#304). This parser stays
# independent of the pipeline's (NFR13: the drafting context never grades its
# own map), so the grammar is mirrored here deliberately, not imported.
# The position is INTENTIONALLY freeform (`[^\s:\[]+`): a bare paragraph-level
# `P<n>` — no `.S<n>` — carrying an interview question-id pointer is a valid
# OWNER-ATTRIBUTED PROSE SPAN (CAP-3, #439; Story 17.2), the paragraph-granularity
# attribution for owner opinion. Do NOT tighten this to require `.S<n>`: that
# would reject a whole class of legitimate sourced attribution. Such a span is a
# `sourced` claim like any other — its question-id pointer must resolve to the
# declared pointer set (mechanical layer below), and it carries no narration/
# derived worklist entry to grade.
# The optional CLAIM TYPE sits between the class and the pointer arrow —
# `P1.S1[L7]: sourced episode <- <sha>`. Optional in the grammar (every map
# authored before #1184 still parses, and every claim it carries is a `state`
# claim, which the rule does not constrain).
PROV_LINE = re.compile(
    r"^(?P<pos>[^\s:\[]+)(?:\[L(?P<anchor>\d+)\])?"
    r":\s*(?P<cls>sourced|derived|narration|verify)"
    r"(?:\s+(?P<ctype>" + "|".join(CLAIM_TYPES) + r"))?"
    r"(?:\s*<-\s*(?P<ptrs>.+?))?\s*$"
)


def parse_map(text):
    """[(pos, cls, [pointers], anchor, claim_type)] — `claim_type` is `state`
    when the entry declares none (#1184: the rule constrains episode claims
    only, so the permissive value is the default)."""
    entries = []
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        m = PROV_LINE.match(line)
        if not m:
            raise ValueError(f"line {lineno}: malformed provenance entry: {raw!r}")
        ptrs = [p.strip() for p in (m.group("ptrs") or "").split(",") if p.strip()]
        anchor = int(m.group("anchor")) if m.group("anchor") else None
        entries.append((m.group("pos"), m.group("cls"), ptrs, anchor,
                        m.group("ctype") or "state"))
    return entries


def segment_draft(draft_text):
    """The DETERMINISTIC segmentation that defines `P{n}.S{m}` positions
    (Story 19.16, #755): the single authority both the map author and the
    judge worklists consume, so nobody re-derives sentence boundaries.

    Skips frontmatter, headings, fenced code, HTML comments, `---` rules, and
    the rendered pointer-block lines; groups the rest into paragraphs
    (blank-line separated), splits each into sentences on `[.!?]` followed by
    whitespace/end, and anchors each sentence at the 1-based physical line
    where it starts. Two runs over the same bytes emit identical output.
    Returns [(pos, anchor, sentence)]."""
    lines = draft_text.splitlines()
    skip = [False] * len(lines)
    in_fm = in_fence = False
    for i, l in enumerate(lines):
        s = l.strip()
        if i == 0 and s == "---":
            in_fm = True
            skip[i] = True
            continue
        if in_fm:
            skip[i] = True
            if s == "---":
                in_fm = False
            continue
        if s.startswith("```"):
            in_fence = not in_fence
            skip[i] = True
            continue
        if (in_fence or l.startswith("#") or s.startswith("<!--")
                or s == "---" or (s.startswith("*") and s.endswith("*"))):
            skip[i] = True
    paras, cur = [], []
    for i, l in enumerate(lines):
        if skip[i] or not l.strip():
            if cur:
                paras.append(cur)
                cur = []
            continue
        cur.append((i + 1, l))
    if cur:
        paras.append(cur)
    out = []
    for pi, para in enumerate(paras, 1):
        text = " ".join(l for _, l in para)
        offs, pos = [], 0
        for ln, l in para:
            offs.append((pos, pos + len(l), ln))
            pos += len(l) + 1
        sents = list(re.finditer(r"[^.!?]*[.!?](?=\s|$)", text)) or [re.match(r".*", text)]
        for si, m in enumerate(sents, 1):
            st = m.start()
            while st < len(text) and text[st] == " ":
                st += 1
            ln = next((l for a, b, l in offs if a <= st <= b), para[0][0])
            out.append((f"P{pi}.S{si}", ln, m.group(0).strip()))
    return out


def anchored_text(anchor, draft_lines):
    """The verbatim draft line an anchor names — what the judge MATCHES against.

    Returning the line (not a re-split sentence) is the point: any derivation
    the judge has to perform is a derivation it can get wrong, and three judges
    already proved they get it wrong differently.
    """
    if anchor is None or draft_lines is None:
        return None
    if not (1 <= anchor <= len(draft_lines)):
        return None
    return draft_lines[anchor - 1].strip()


def _read(path):
    return sys.stdin.read() if path == "-" else open(path, encoding="utf-8").read()


def draft_sha256(draft_text):
    return hashlib.sha256(draft_text.encode("utf-8")).hexdigest()


class ConcatenatedVerdicts(ValueError):
    """More than one attestation header inside ONE verdicts file (Story 20.163).

    Raised rather than resolved: any resolution rule is a fail-open. Last-wins
    (what shipped) accepts a stale earlier shard behind a fresh final one;
    first-wins accepts a fresh later shard behind a stale header. Shards are
    separate files, each attested on its own, or they are not judged.
    """


def parse_attestation(text):
    """Split ONE verdicts file into (draft_hash, graded_set, carried_set,
    verdict_lines).

    Returns (None, set(), set(), lines) when no attestation header is present —
    the caller fails closed on that. `graded:` lines are unioned so the judge
    can echo the narration and derived listings' headers separately. `carried:`
    lines (#738 delta re-grade) name positions whose verdicts carry forward
    from the attested prior cycle — echoed from the hand-off like `graded:`.

    Raises ConcatenatedVerdicts when the text carries a SECOND attestation
    header (Story 20.163): sharded verdicts are separate `--verdicts` files,
    never a concatenation.
    """
    draft_hash, graded, carried, verdicts = None, set(), set(), []
    for raw in text.splitlines():
        ln = raw.strip()
        if not ln or ln.startswith("#"):
            continue
        m = ATTEST_LINE.match(ln)
        if m:
            if draft_hash is not None:
                raise ConcatenatedVerdicts(
                    "verdicts file carries more than one `attestation:` header — "
                    "concatenated shards are REFUSED, not merged: whichever header "
                    "won, a stale shard would ride in on a fresh one's hash. Pass "
                    "each shard as its own --verdicts file")
            draft_hash = m.group("hash").lower()
            continue
        m = GRADED_LINE.match(ln)
        if m:
            graded.update(p.strip() for p in m.group("positions").split(",") if p.strip())
            continue
        m = CARRIED_LINE.match(ln)
        if m:
            carried.update(p.strip() for p in m.group("positions").split(",") if p.strip())
            continue
        verdicts.append(ln)
    return draft_hash, graded, carried, verdicts


def check_attestation(draft_hash, graded, entries, draft_text, carried=frozenset()):
    """The fail-closed attestation checks (Story 13.67). Returns error strings.

    `carried` positions (#738) count toward worklist coverage: a delta cycle
    grades only changed sentences, and the hand-off's `carried:` header —
    echoed by the judge — accounts for the rest.
    """
    errors = []
    if draft_hash is None:
        return ["no judge attestation found (`attestation: draft-sha256=<hex>` header) "
                "— absence of verdicts is never PASS; a comment-only or free-form file "
                "does not demonstrate that a judge ran"]
    worklist = {pos for pos, cls, _, _, _ in entries if cls in ("narration", "derived")}
    missing = sorted(worklist - graded - set(carried))
    if missing:
        errors.append("attestation does not cover the expected worklist — ungraded "
                      f"position(s): {', '.join(missing)} (a partially-graded artifact "
                      "is not judged)")
    unknown = sorted((graded | set(carried)) - {pos for pos, _, _, _, _ in entries})
    if unknown:
        errors.append(f"attestation grades position(s) not in the map: {', '.join(unknown)}")
    if draft_text is None:
        errors.append("attestation carries a draft hash but no --draft was given to "
                      "verify it against — pass --draft (fail closed)")
    elif draft_sha256(draft_text) != draft_hash:
        errors.append("draft-sha256 mismatch: the attestation was made over a different "
                      "draft version — verdicts for a prior draft never validate the "
                      "current one")
    return errors


def parse_shards(paths):
    """Parse N attested verdicts files into one union (Story 20.163, #1248).

    Returns (draft_hash, graded, carried, verdict_lines, errors). `draft_hash`
    is the single hash every shard agreed on, or None when they did not agree —
    in which case `errors` names the disagreement and the caller fails the WHOLE
    gate. Nothing is dropped and nothing is preferred: a stale shard is "not
    judged", so its presence poisons the run rather than being silently ignored.

    With a single path this is exactly the shipped single-file behaviour: the
    union of one set is that set, and a missing header still yields
    `draft_hash is None` for `check_attestation` to report.
    """
    graded, carried, verdicts, errors = set(), set(), [], []
    by_hash = {}
    sharded = len(paths) > 1
    for path in paths:
        try:
            h, g, c, v = parse_attestation(_read(path))
        except ConcatenatedVerdicts as e:
            errors.append(f"{path}: {e}")
            continue
        graded |= g
        carried |= c
        verdicts += v
        if h is not None:
            by_hash.setdefault(h, []).append(path)
        elif sharded:
            errors.append(f"{path}: shard carries no `attestation: draft-sha256=<hex>` "
                          "header — every shard attests on its own, and an unattested "
                          "shard is not judged")
    if len(by_hash) > 1:
        named = "; ".join(f"{h}: {', '.join(ps)}" for h, ps in sorted(by_hash.items()))
        errors.append("shard attestations disagree on the draft they bind — the "
                      f"whole gate fails, no shard is dropped ({named})")
        return None, graded, carried, verdicts, errors
    draft_hash = next(iter(by_hash)) if by_hash else None
    return draft_hash, graded, carried, verdicts, errors


def delta_basis(prior_worklist_text, prior_verdicts_text):
    """The #738 delta re-grade basis: which sentence TEXTS passed the attested
    prior cycle. Returns (passing_texts, prior_hash) or (None, reason) when the
    basis does not resolve — the caller then falls back to a full re-grade with
    a disclosed reason, never silently.

    `prior_verdicts_text` is one file's text, or a LIST of shard texts when the
    prior cycle was judged sharded (Story 20.163): the shards' `graded:` sets
    and failure verdicts are unioned exactly as the consumption side unions
    them, and every shard must attest to the same draft as the prior worklist.
    """
    prior_hash = None
    texts = {}
    for raw in prior_worklist_text.splitlines():
        ln = raw.strip()
        m = ATTEST_LINE.match(ln)
        if m:
            prior_hash = m.group("hash").lower()
            continue
        m = WORKLIST_ENTRY.match(ln)
        if m and not ln.startswith(("graded:", "carried:")):
            payload = m.group("payload")
            # derived/sourced entries print `ptrs | text`; narration prints text.
            text = payload.split(" | ", 1)[1] if " | " in payload else payload
            texts[m.group("pos")] = text.strip()
    if prior_hash is None:
        return None, "prior worklist carries no attestation header"
    shard_texts = ([prior_verdicts_text] if isinstance(prior_verdicts_text, str)
                   else list(prior_verdicts_text))
    graded, verdict_lines = set(), []
    for shard_text in shard_texts:
        try:
            v_hash, g, _carried, v = parse_attestation(shard_text)
        except ConcatenatedVerdicts as e:
            # A concatenated prior-verdicts file is refused here too: the delta
            # basis is only as trustworthy as the attestation it rests on.
            return None, str(e)
        if v_hash is None:
            return None, "prior verdicts carry no attestation header"
        if v_hash != prior_hash:
            return None, ("prior verdicts attestation does not match the prior "
                          "worklist (different draft version)")
        graded |= g
        verdict_lines += v
    failing = set()
    for ln in verdict_lines:
        m = JUDGE_ECHO.match(ln)
        pos = m.group("pos").strip() if m else ln.partition(":")[0].strip()
        failing.add(pos)
    passing = {txt for pos, txt in texts.items()
               if pos in graded and pos not in failing and txt}
    return passing, prior_hash


def _episode_findings(pos, cls, ptrs):
    """The ship-gate refusal for a claim typed `episode` (#1184 clause (iii)).

    DENY, NEVER WARN, and the finding NAMES the claim and the source that
    failed it — a refusal an author cannot act on is a refusal they route
    around. Every pointer is resolved to its declared source TYPE by form
    (`resolve-writing-sources.py` owns that table); an unrecognised form has no
    established time axis and therefore does not admit the claim, which is the
    fail-closed direction.

    The rule constrains episode claims ONLY: a claim about how something
    CURRENTLY IS never reaches here, and is admissible against either class.
    """
    if cls in ("narration", "verify"):
        return [(pos, f"a claim typed `episode` cannot be `{cls}` — {cls} carries "
                      "no pin, and an episode claim is admissible only against a "
                      "time-axis source it can name")]
    if not ptrs:
        return [(pos, "a claim typed `episode` carries no pin — an episode claim "
                      "is admissible only against a time-axis source")]
    if any(rws.pointer_time_axis(p) for p in ptrs):
        return []
    named = "; ".join(
        f"{p} → {rws.pointer_source_type(p) or 'unrecognized pointer form'} "
        f"(time_axis: false)" for p in ptrs)
    return [(pos, "EPISODE CLAIM REFUSED — every pin resolves to a source with no "
                  f"time axis: {named}. A claim about how something CAME TO BE may "
                  "be grounded only in a `commits`, `github-issues` or `tanuki-den` "
                  "source (#1184); docs, specs and code record how things "
                  "currently are. Re-state it as a state claim, or ground it in a "
                  "time-axis source.")]


def _load_set(path):
    if not path:
        return None
    return {ln.strip() for ln in _read(path).splitlines() if ln.strip() and not ln.startswith("#")}


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    p.add_argument("--map", default="-", help="the sidecar provenance map, or - for stdin")
    p.add_argument("--fact-sheet", help="file of valid fact-sheet pointer ids (one per line)")
    p.add_argument("--judge-findings", "--verdicts", dest="judge_findings",
                   action="append", metavar="FILE",
                   help="independent judge's verdicts: `POS: reason` per line. REPEATABLE "
                        "(Story 20.163): a sharded judge returns one attested file per "
                        "shard, each binding the same draft-sha256; coverage is checked "
                        "over the union and any hash disagreement fails the whole gate. "
                        "Concatenating shards into one file is refused")
    p.add_argument("--list-narration", action="store_true", help="list narration positions for the judge")
    p.add_argument("--list-derived", action="store_true", help="list derived positions + pointers for the judge")
    p.add_argument("--list-sourced", action="store_true",
                   help="list sourced positions + pointers for the judge to grade ATTRIBUTION "
                        "entailment (Story 18.97, #672): does the pointer support the claim AS "
                        "STATED, including its actor/scope? A supported-topic-but-contradicted-"
                        "attribution span is a `contradicted-attribution` finding")
    p.add_argument("--draft", help="the draft the map describes; makes the judge hand-off carry each\nposition's anchored line verbatim, and lets an echoed judge quote be checked (#304)")
    p.add_argument("--prior-worklist", dest="prior_worklist",
                   help="the SAME listing class's hand-off from the attested prior cycle "
                        "(#738 delta re-grade): sentences unchanged since it, whose "
                        "positions the prior judge graded clean, are CARRIED instead of "
                        "re-graded; requires --prior-verdicts and --draft")
    p.add_argument("--prior-verdicts", dest="prior_verdicts", action="append", metavar="FILE",
                   help="the judge verdicts returned for --prior-worklist; its attestation "
                        "must match the prior worklist's, else the emission falls back to a "
                        "full re-grade with a disclosed reason. REPEATABLE when the prior "
                        "cycle was judged sharded — the shards' graded sets and verdicts are "
                        "unioned, and every shard must attest to the same draft")
    args = p.parse_args(argv)

    try:
        entries = parse_map(_read(args.map))
    except ValueError as e:
        sys.stderr.write(f"error: {e}\n")
        return 2

    draft_lines = _read(args.draft).splitlines() if args.draft else None

    # The judge hand-off. With --draft each position carries its anchored line
    # verbatim, so the judge MATCHES the sentence instead of re-deriving the
    # P{n}.S{n} numbering from skip rules (#304). Emission is a pure function of
    # (map, draft): every spawn receives byte-identical text, which is what makes
    # three judges agree on what P8.S3 is.
    if args.list_narration or args.list_derived or args.list_sourced:
        cls_wanted = ("narration" if args.list_narration
                      else "derived" if args.list_derived else "sourced")
        listed = [e for e in entries if e[1] == cls_wanted]
        # Attestation header the judge must echo verbatim at the top of its
        # verdicts file (Story 13.67): the draft hash binds the verdicts to
        # this draft version, the graded line to this worklist. Emitted only
        # with --draft — the hash does not exist without the draft.
        # #738 delta re-grade: carry forward positions whose sentence text is
        # unchanged since the attested prior cycle AND passed it. The judge
        # never sees prior verdicts (NFR13) — only a smaller worklist plus the
        # `carried:` header it echoes like `graded:`.
        carried = []
        if args.prior_worklist and args.prior_verdicts and args.draft:
            passing, basis = delta_basis(_read(args.prior_worklist),
                                         [_read(pv) for pv in args.prior_verdicts])
            if passing is None:
                sys.stderr.write(f"delta re-grade unavailable — full re-grade: {basis}\n")
            else:
                keep = []
                for e in listed:
                    text = anchored_text(e[3], draft_lines)
                    (carried if text and text.strip() in passing else keep).append(e)
                listed = keep
                sys.stderr.write(
                    f"delta re-grade: {len(carried)} carried, {len(listed)} "
                    f"re-graded (basis draft-sha256={basis})\n")
        if args.draft:
            print(f"attestation: draft-sha256={draft_sha256(_read(args.draft))}")
            if listed:
                print(f"graded: {','.join(pos for pos, _, _, _, _ in listed)}")
            if carried:
                print(f"carried: {','.join(pos for pos, _, _, _, _ in carried)}")
        # Story 19.16 (#755): the printed text is the FULL RECONSTRUCTED
        # SENTENCE from the one segmentation authority (`segment_draft`), not
        # the hard-wrapped physical line — the judge grades exactly what the
        # tool prints, and boundary reconstruction stops being judge work.
        # Fallback (a bare paragraph-level P<n>, or a position the skeleton
        # does not carry): the anchored physical line, as before.
        seg_by_pos = ({p: s for p, _a, s in segment_draft(_read(args.draft))}
                      if args.draft else {})
        for pos, cls, ptrs, anchor, _ctype in listed:
            text = seg_by_pos.get(pos) or anchored_text(anchor, draft_lines)
            if cls_wanted == "narration":
                print(f"{pos} [L{anchor}]: {text}" if text is not None else pos)
            else:
                head = f"{pos} [L{anchor}]" if text is not None else pos
                print(f"{head}: {', '.join(ptrs)}" + (f" | {text}" if text is not None else ""))
        return 0

    # --- attestation layer (Story 13.67, #364) — before any grading report ---
    # A verdicts file with no structured attestation, incomplete worklist
    # coverage, or the wrong draft hash fails closed here: "never judged" must
    # be mechanically distinguishable from "judged clean".
    verdict_lines = None
    if args.judge_findings:
        draft_text = _read(args.draft) if args.draft else None
        # N shards, one attestation each, checked over the union (Story 20.163).
        # Shard-level failures (a concatenation, a disagreeing hash, an
        # unattested shard) are reported INSTEAD of the coverage/hash checks —
        # once the shard set is untrustworthy, its union means nothing.
        att_hash, graded, carried, verdict_lines, att_errors = parse_shards(args.judge_findings)
        if not att_errors:
            att_errors = check_attestation(att_hash, graded, entries, draft_text, carried)
        if att_errors:
            sys.stderr.write("verify-provenance: ATTESTATION FAILURE (not judged)\n")
            for e in att_errors:
                sys.stderr.write(f"  {e}\n")
            return 3

    valid = _load_set(args.fact_sheet)
    findings = []

    # --- mechanical layer ---
    for pos, cls, ptrs, anchor, ctype in entries:
        if cls in ("narration", "verify") and ptrs:
            findings.append((pos, f"{cls} must carry no pointer"))
        if cls == "sourced" and not ptrs:
            findings.append((pos, "sourced claim carries no pointer"))
        if cls == "derived" and len(ptrs) < 2:
            findings.append((pos, f"derived claim must inherit >=2 pointers (got {len(ptrs)})"))
        if valid is not None and cls in ("sourced", "derived"):
            for ptr in ptrs:
                if ptr not in valid:
                    findings.append((pos, f"pointer {ptr!r} does not resolve to a fact-sheet entry"))
        # --- the time-axis admissibility predicate (#1184 clause (iii)) ---
        # An EPISODE claim — about how something CAME TO BE — may be grounded
        # only in a source written along a time axis. A STATE claim is
        # admissible against either class and is never touched here.
        if ctype == "episode":
            findings += _episode_findings(pos, cls, ptrs)

    # --- semantic layer (independent judge's verdicts) ---
    # Grammar: `POS: reason`, or `POS ~ "<quoted sentence>": reason` when the
    # judge echoes the text it graded. The echo is what makes a MISLOCATED
    # verdict detectable from the record alone (#304): a judge that graded the
    # wrong sentence still returns a confident finding, and previously the only
    # way to notice was a human comparing quote to draft — which needs exactly
    # the drafting context NFR13 denies the judge. With the echo, the mismatch
    # is arithmetic.
    if verdict_lines is not None:
        anchors = {pos: anchor for pos, _, _, anchor, _ in entries}
        known = set(anchors)
        for ln in verdict_lines:
            m = JUDGE_ECHO.match(ln)
            if m:
                pos, quoted, reason = m.group("pos").strip(), m.group("quote"), m.group("reason").strip()
            else:
                pos, _, reason = ln.partition(":")
                pos, quoted, reason = pos.strip(), None, reason.strip()
            if pos not in known:
                findings.append((pos, f"judge graded position {pos!r}, which is not in the map "
                                      "— the verdict cannot be trusted"))
                continue
            if quoted is not None:
                # Story 19.16 (#755): when the segmentation resolves this
                # position, the judge's echo must equal the printed SENTENCE
                # byte-for-byte — the hand-off printed it, so quoting it costs
                # nothing and a paraphrase is a mislocation signal. Positions
                # the skeleton does not carry keep the anchored-line
                # containment check.
                seg_sentence = None
                if draft_lines is not None:
                    if "_seg_cache" not in dir():
                        _seg_cache = {p: s for p, _a, s in
                                      segment_draft("\n".join(draft_lines))}
                    seg_sentence = _seg_cache.get(pos)
                if seg_sentence is not None:
                    if quoted.strip() != seg_sentence:
                        findings.append((pos, f"ANCHOR MISMATCH: judge graded "
                                              f"{quoted.strip()!r} but {pos} is the "
                                              f"sentence {seg_sentence!r} — the verdict "
                                              "is about different text and is discarded"))
                        continue
                    findings.append((pos, reason or "judge flagged a provenance violation"))
                    continue
                actual = anchored_text(anchors[pos], draft_lines)
                if actual is None:
                    findings.append((pos, "judge echoed a sentence but the map gives no "
                                          "resolvable anchor to check it against"))
                    continue
                if quoted.strip() not in actual:
                    findings.append((pos, f"ANCHOR MISMATCH: judge graded {quoted.strip()!r} "
                                          f"but {pos} anchors to {actual!r} — the verdict is "
                                          "about a different sentence and is discarded"))
                    continue
            findings.append((pos, reason or "judge flagged a provenance violation"))

    if not findings:
        print("verify-provenance: PASS (no findings)")
        return 0
    sys.stderr.write("verify-provenance: FAIL\n")
    for pos, reason in findings:
        sys.stderr.write(f"  {pos}: {reason}\n")
    return 1


if __name__ == "__main__":
    sys.exit(main())
