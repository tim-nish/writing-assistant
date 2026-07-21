#!/usr/bin/env python3
"""Validate a harvest fact sheet: every entry is `CLAIM / SOURCE / KIND` with a
resolvable, commit-pinned, declared-repo source (Story 3.2).

Contract enforced per entry (a `- ` bullet line):

  - CLAIM / SOURCE / KIND

  * KIND  ∈ {result, decision, number, quote, event}  (closed set)
  * SOURCE is one of:
      path:line@sha   a file pointer PINNED to a commit sha, so it stays
                      resolvable after edits shift line numbers
      path:l1-l2@sha  a line-range pointer, accepted for the SPAN-eligible kinds
                      (`quote` + the four narrative kinds, #438) whose text
                      spans consecutive physical lines (#119)
      sha             a commit sha (7-40 hex)
      https://…       a URL (external, declared-source citation)
      den:<id>@<run>  a Tanuki Den finding, pinned to the run that judged it
                      (Story 13.51) — a declared `tanuki-den` source's pointer
                      form. The Den ledger is not a git tree, so this pins to a
                      run id rather than a commit; like a URL, the FORM is the
                      contract here and resolution belongs to the Den reader.
    A bare `path:line` with no `@sha` is rejected — pointers must pin. A line
    range on any KIND except `quote` is rejected: single-line-only for facts,
    with the REJECT naming the fix (split the range into per-line pointers).
  * A file pointer must resolve INSIDE a declared source repo (Story 3.1 scope);
    the sha must exist there, the path must exist at that sha, and the line(s)
    must be in range. A `quote` entry's CLAIM must match the source line(s)
    verbatim (the joined physical lines, for a multi-line span).

An entry that fails any check is REJECTED (it belongs on the needs-owner list —
Story 3.3 — not the fact sheet). Exit status is non-zero if any entry is
rejected, so "no entry without a resolvable pointer" is a hard gate.

Usage: validate-fact-sheet.py [FACTSHEET|-] [--root HOSTROOT] [--rejected]
"""

import argparse
import importlib.util
import os
import re
import subprocess
import sys

KINDS = {"result", "decision", "number", "quote", "event",
         "chronology", "motivation", "cost", "reversal"}
# The closed set is nine (amended 2026-07-20, #438): five atomic kinds plus four
# NARRATIVE kinds (chronology | motivation | cost | reversal), which admit
# pointer-backed narrative material. The set is widened by this decided amount,
# never opened. This set and `skills/harvest/SKILL.md §3` are the two enforcement
# copies of the closed set — a change to one without the other is a defect.
# SPAN-eligible kinds may use a multi-line `path:l1-l2@sha` range: `quote` (a
# wrapped verbatim quote) plus the four narrative kinds (a rationale paragraph, a
# chronology block); every other KIND is single-line-pin only.
SPAN_ELIGIBLE = {"quote", "chronology", "motivation", "cost", "reversal"}
SHA_RE = re.compile(r"^[0-9a-f]{7,40}$")
FILEPIN_RE = re.compile(r"^(?P<path>.+):(?P<line>\d+)@(?P<sha>[0-9a-f]{7,40})$")
# A line-range pointer `path:line1-line2@sha` — accepted for the SPAN_ELIGIBLE
# kinds (`quote` + the four narrative kinds, #438) whose material genuinely
# spans consecutive physical lines (#119).
FILEPINRANGE_RE = re.compile(
    r"^(?P<path>.+):(?P<l1>\d+)-(?P<l2>\d+)@(?P<sha>[0-9a-f]{7,40})$")
URL_RE = re.compile(r"^https?://\S+$")
# `den:<ledger-id>@<run>` — a Tanuki Den finding (Story 13.51). A new PINNED
# pointer type: the Den ledger is not a git-pinned tree, so the pin is the run
# that judged the finding, not a commit. An unpinned `den:<id>` is rejected —
# the pin is what a later audit resolves to the exact finding.
DEN_RE = re.compile(r"^den:(?P<ledger>[A-Za-z0-9._-]+)@(?P<run>[A-Za-z0-9._-]+)$")

# --- Coverage manifest (#514) ------------------------------------------------
# The fact sheet opens with a machine-checkable coverage manifest so a silent
# source-coverage collapse is impossible to ship: it discloses the pin, how many
# declared files the scope resolver matched, the per-file entry counts of the
# files READ, and an explicit SKIPPED list (or `skipped: none`). The accounting
# is closed — read files + skipped files must equal the matched count, so a file
# that was neither read nor disclosed as skipped is a rejection, not a silent
# omission. The section uses `key: value` lines (never `- ` bullets), so entry
# parsing never mistakes it for a `CLAIM / SOURCE / KIND` entry. See
# `skills/harvest/SKILL.md` (output contract) and pipeline-stages.md
# (§"Harvest coverage disclosure").
COVERAGE_HEADING_RE = re.compile(r"^#+\s*Coverage\b", re.I)
COV_PIN_RE = re.compile(r"^pin:\s*(?P<pin>\S+)\s*$")
COV_MATCHED_RE = re.compile(r"^matched:\s*(?P<n>\d+)\s*$")
COV_READ_RE = re.compile(r"^read:\s*(?P<file>.+?)\s*\((?P<n>\d+)\)\s*$")
COV_SKIPPED_NONE_RE = re.compile(r"^skipped:\s*none\s*$", re.I)
COV_SKIPPED_RE = re.compile(r"^skipped:\s*(?P<file>.+?)\s*\((?P<reason>.+)\)\s*$")


def _coverage_section(text):
    """Return the lines of the `## Coverage` section (heading excluded), or None
    if the fact sheet carries no coverage manifest. The section runs from its
    heading to the next markdown heading (or EOF)."""
    lines = text.split("\n")
    start = None
    for i, ln in enumerate(lines):
        if COVERAGE_HEADING_RE.match(ln):
            start = i
            break
    if start is None:
        return None
    body = []
    for ln in lines[start + 1:]:
        # The manifest ends at the next heading or the first fact-sheet entry
        # (`- ` bullet) — the manifest itself never uses bullets, so entries and
        # the NEEDS-OWNER list are never swallowed into the section.
        if ln.startswith("#") or ln.startswith("- "):
            break
        body.append(ln)
    return body


def validate_coverage(text):
    """Validate the coverage manifest (#514) if present. Returns None when the
    manifest is well-formed (or absent — absence is handled by the caller under
    --require-coverage), else a single rejection reason string.

    A well-formed manifest has exactly one `pin:` and one `matched: <int>`, a
    `read: <file> (<count>)` line per file read, and either `skipped: none` or a
    `skipped: <file> (<reason>)` line per skipped file — with the closed
    accounting `#read + #skipped == matched` so every matched file is disclosed
    as read or skipped, never silently dropped."""
    body = _coverage_section(text)
    if body is None:
        return None
    pins, matched = [], []
    reads, skips = [], []
    skipped_none = False
    for ln in body:
        s = ln.strip()
        if s == "":
            continue
        m = COV_PIN_RE.match(s)
        if m:
            pins.append(m["pin"]); continue
        m = COV_MATCHED_RE.match(s)
        if m:
            matched.append(int(m["n"])); continue
        m = COV_READ_RE.match(s)
        if m:
            reads.append((m["file"], int(m["n"]))); continue
        if COV_SKIPPED_NONE_RE.match(s):
            skipped_none = True; continue
        m = COV_SKIPPED_RE.match(s)
        if m:
            skips.append((m["file"], m["reason"])); continue
        return (f"coverage manifest: unrecognized line {s!r} — allowed lines are "
                "`pin: <ref>`, `matched: <int>`, `read: <file> (<count>)`, and "
                "`skipped: <file> (<reason>)` or `skipped: none`")
    if len(pins) != 1:
        return f"coverage manifest: expected exactly one `pin:` line, found {len(pins)}"
    if len(matched) != 1:
        return f"coverage manifest: expected exactly one `matched: <int>` line, found {len(matched)}"
    if skipped_none and skips:
        return ("coverage manifest: `skipped: none` cannot coexist with a "
                "`skipped: <file>` line — list every skipped file or state none")
    if not skipped_none and not skips and not reads:
        return "coverage manifest: no `read:` or `skipped:` lines — disclose what was covered"
    accounted = len(reads) + len(skips)
    if accounted != matched[0]:
        return (f"coverage manifest: accounting does not close — {len(reads)} read + "
                f"{len(skips)} skipped = {accounted}, but matched: {matched[0]} "
                "(every matched file must be disclosed as read or skipped)")
    return None


def source_form_ok(source, kind):
    """Grammar-only check (no repo resolution): is `source` a syntactically valid
    SOURCE pointer FORM for `kind`? This is the single SOURCE grammar shared by
    the validator and the pipeline's `consume` step, so the two cannot diverge
    (Story 13.8). A multi-line range `path:l1-l2@sha` is valid ONLY for the
    SPAN_ELIGIBLE kinds (`quote` plus the four narrative kinds, #438); every
    other KIND is single-line. Resolution (sha exists, line in range, verbatim
    match) is a separate, deeper check the validator does and consume
    deliberately does not (it never re-reads sources)."""
    if URL_RE.match(source) or SHA_RE.match(source) or FILEPIN_RE.match(source):
        return True
    if DEN_RE.match(source):
        return True
    if kind in SPAN_ELIGIBLE and FILEPINRANGE_RE.match(source):
        return True
    return False


def _norm_ws(s):
    """Collapse every run of whitespace (spaces, tabs, newlines) to a single
    space and strip the ends — the shared normalization for quote matching."""
    return re.sub(r"\s+", " ", s).strip()


def _quote_matches(claim, src_text):
    """Whitespace-normalized verbatim test (amended #154): the CLAIM's quoted text
    must be a CONTIGUOUS span of the source text once both sides collapse runs of
    whitespace/newlines to a single space. This lets a real sentence that wraps
    across physical lines (or carries doubled spaces) be quoted by its true
    boundary without exact-whitespace fiddling. `src_text` is the source line(s),
    each physical line stripped and joined by a single space. The no-extra-text
    guarantee still holds: the CLAIM must be a SUB-span of the source (a
    label/prefix/suffix like "Decision from batch 16:" is not verbatim, #137) —
    `quoted in src_text` (claim ⊆ source) matches, `src_text in quoted` (claim
    adds text) does not."""
    quoted = claim.strip()
    inner = re.match(r'^["“](.*)["”]$', quoted)
    if inner:
        quoted = inner.group(1)
    return _norm_ws(quoted) in _norm_ws(src_text)


def _load_rws():
    here = os.path.dirname(os.path.realpath(__file__))
    spec = importlib.util.spec_from_file_location(
        "rws", os.path.join(here, "resolve-writing-sources.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


rws = _load_rws()


def _git(repo, *args):
    return subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)


def declared_repo_for(abspath, sources):
    for s in sources:
        if rws._contains(s["path"], abspath):
            return s["path"]
    return None


# An article plan (SPEC-article-plan) is the machine-checkable no-facts marker:
# a plan may shape questions and recommendations but can never ground a claim.
# `kind: article-plan` in the file's frontmatter is that marker (Story 13.56).
_PLAN_REJECT = ("SOURCE points into an article plan (kind: article-plan) — an "
                "article plan is never evidence; re-ground the claim on current "
                "evidence (a fresh pin or an interview disposition), never a bare "
                "plan reference (SPEC-article-plan; Story 13.56)")


def _is_article_plan(lines):
    """True iff `lines` open with a frontmatter block declaring
    `kind: article-plan` — the no-facts marker a SOURCE may never cite."""
    if not lines or lines[0].strip() != "---":
        return False
    for ln in lines[1:]:
        if ln.strip() == "---":
            return False
        m = re.match(r"^kind\s*:\s*(.+?)\s*$", ln)
        if m and m.group(1).strip().strip('"').strip("'") == "article-plan":
            return True
    return False


def _resolve_lines(path, sha, host, sources):
    """Resolve a pinned file pointer to its source lines at the commit.

    Returns (lines, rel, None) on success, (None, None, reason) on rejection,
    or (None, rel, None) for the not-a-git-repo structural pass."""
    abspath = os.path.realpath(os.path.join(host, path))
    repo = declared_repo_for(abspath, sources)
    if repo is None:
        return None, None, f"source path is outside the declared repos: {path}"
    rel = os.path.relpath(abspath, repo)
    if _git(repo, "rev-parse", "--git-dir").returncode != 0:
        # not a git repo: structural pass — but still refuse a plan file we can
        # read on disk (the marker fence must not depend on git resolution).
        try:
            with open(abspath, encoding="utf-8") as fh:
                if _is_article_plan(fh.read().split("\n")):
                    return None, None, _PLAN_REJECT
        except OSError:
            pass
        return None, rel, None           # not a git repo: structural pass (pin present)
    if _git(repo, "cat-file", "-e", f"{sha}^{{commit}}").returncode != 0:
        return None, None, f"commit {sha} not found in {os.path.basename(repo)}"
    show = _git(repo, "show", f"{sha}:{rel}")
    if show.returncode != 0:
        return None, None, f"path {rel} does not exist at commit {sha}"
    if _is_article_plan(show.stdout.split("\n")):
        return None, None, _PLAN_REJECT
    return show.stdout.split("\n"), rel, None


# The policy surface is never harvest evidence (SPEC-policy-source-seam: policy
# seeds questions and recommended defaults, never facts; Story 13.61). The
# path-identity fence this validator used to hold (reject a SOURCE resolving
# inside `policy_source.path`) retired with the key (Story 13.73, #366): the
# consumer holds no hub path, so the invariant is now STRUCTURAL — policy
# content arrives only through the gateway seam reader, whose cites are
# hub-relative `file:line@<hub-sha>` pointers that cannot resolve in the
# declared host scope; there is no hub checkout identity left to leak.


def validate_source(source, kind, claim, host, sources):
    """Return None if the source is valid, else a rejection reason."""
    if URL_RE.match(source):
        return None                      # external citation; form is the contract
    if DEN_RE.match(source):
        # A Den finding (Story 13.51): pinned to the run that judged it. The
        # ledger is not a git tree — the form is the contract, exactly as for a
        # URL; the bounded Den reader owns resolution, and this validator never
        # reaches into Tanuki's state to check it.
        return None
    if re.match(r"^den:", source):
        return ("den pointer is not pinned to a run (use den:<ledger-id>@<run>; "
                "ledger-id and run are [A-Za-z0-9._-])")
    if SHA_RE.match(source):             # bare commit sha — must exist in a declared repo
        for s in sources:
            if os.path.isdir(os.path.join(s["path"], ".git")) or _git(s["path"], "rev-parse", "--git-dir").returncode == 0:
                if _git(s["path"], "cat-file", "-e", f"{source}^{{commit}}").returncode == 0:
                    return None
        return f"commit {source} not found in any declared repo"

    # Line-range pointer `path:line1-line2@sha` — the SPAN_ELIGIBLE kinds
    # (`quote` + the four narrative kinds, #438) may span consecutive physical
    # lines; every other KIND is single-line (#119).
    rng = FILEPINRANGE_RE.match(source)
    if rng:
        l1, l2, sha, path = int(rng["l1"]), int(rng["l2"]), rng["sha"], rng["path"]
        if kind not in SPAN_ELIGIBLE:
            return (f"SOURCE must be a single line for KIND '{kind}'; a line range is "
                    f"only allowed for the span-eligible kinds (quote + the four "
                    f"narrative kinds, #438) — split {l1}-{l2} into per-line pointers")
        if l2 < l1:
            return f"span range {l1}-{l2} is backwards (line1 must be <= line2)"
        if l1 == l2:
            return (f"span range {l1}-{l2} spans a single line; use a single-line "
                    f"pointer path:{l1}@{sha}")
        lines, rel, reason = _resolve_lines(path, sha, host, sources)
        if reason:
            return reason
        if lines is None:
            return None                  # not a git repo: structural pass
        if l2 > len(lines):
            return f"line {l2} out of range at {rel}@{sha} ({len(lines)} lines)"
        # Verbatim matching is quote-specific: a `quote` CLAIM *is* the source
        # text, so it must match; a narrative-kind span merely POINTS at the
        # material (the CLAIM is the harvester's summary), so it is not
        # verbatim-checked (#438) — the span only has to resolve.
        if kind == "quote":
            span = " ".join(lines[i].strip() for i in range(l1 - 1, l2))
            if not _quote_matches(claim, span):
                return ("quote CLAIM must be the verbatim source text only — no label, "
                        "attribution, or prefix, and no paraphrase; it did not match the "
                        "spanned source lines (also check the span boundary l1-l2)"
                        f" — source {l1}-{l2}: {span!r}")
        return None

    m = FILEPIN_RE.match(source)
    if not m:
        if re.match(r"^.+:\d+-\d+$", source):
            return ("file pointer is not pinned to a commit (use path:line1-line2@sha; "
                    "a line range is valid only for a multi-line 'quote')")
        if re.match(r"^.+:\d+$", source):
            return "file pointer is not pinned to a commit (use path:line@sha)"
        return f"unrecognized SOURCE form: {source!r}"
    path, line, sha = m["path"], int(m["line"]), m["sha"]
    lines, rel, reason = _resolve_lines(path, sha, host, sources)
    if reason:
        return reason
    if lines is None:
        return None                      # not a git repo: structural pass
    if line < 1 or line > len(lines):
        return f"line {line} out of range at {rel}@{sha} ({len(lines)} lines)"
    if kind == "quote":
        src = lines[line - 1].strip()
        if not _quote_matches(claim, src):
            return ("quote CLAIM must be the verbatim source text only — no label, "
                    "attribution, or prefix (e.g. drop a leading 'Decision from batch 16:') "
                    "and no paraphrase; it did not match the source line"
                    f" — source {line}: {src!r}")
    return None


def validate_entry(raw, host, sources):
    parts = [p.strip() for p in raw.rsplit(" / ", 2)]
    if len(parts) != 3 or any(p == "" for p in parts):
        return raw, "malformed: expected `CLAIM / SOURCE / KIND` with all fields non-empty"
    claim, source, kind = parts
    if kind not in KINDS:
        return raw, f"invalid KIND {kind!r} (must be one of {sorted(KINDS)})"
    reason = validate_source(source, kind, claim, host, sources)
    return raw, reason


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("factsheet", nargs="?", default="-", help="fact-sheet file, or - for stdin")
    p.add_argument("--root", help="host-repo root (default: git top-level of cwd; errors outside a git repo)")
    p.add_argument("--rejected", action="store_true", help="print only rejected entries (for the needs-owner list)")
    p.add_argument("--require-coverage", action="store_true",
                   help="require a well-formed `## Coverage` manifest header (#514) — "
                        "the pipeline/harvest invocation passes this so a sheet with no "
                        "coverage disclosure is rejected")
    args = p.parse_args(argv)

    host = rws.host_root(args.root)
    # Validating against a host with no writing-sources.yaml would reject every
    # file pointer as "outside the declared repos" — a misleading mass-REJECT
    # when the real problem is a wrong root. Fail loudly instead. Resolution is
    # machine-global-first with legacy in-repo fallback (O1, #211).
    ws_path, ws_kind = rws.sources_path(host, notice=True)
    if ws_kind == "none":
        print(f"error: no {rws.SOURCES_FILE} for host {host} — create it at "
              f"{ws_path} (see config/writing-sources.example.yaml), or check --root",
              file=sys.stderr)
        return 2
    try:
        sources = rws.get_sources(rws.read_lines(host), host)
    except rws.MalformedSources as e:
        # #221: a malformed include: must fail loudly here too — validating
        # pointers against a silently-widened scope would accept entries the
        # owner never declared readable.
        print(f"error: {ws_path}: {e}", file=sys.stderr)
        return 2
    text = sys.stdin.read() if args.factsheet == "-" else open(args.factsheet, encoding="utf-8").read()

    # Coverage manifest (#514): a well-formed manifest is validated whenever it is
    # present; under --require-coverage its absence is itself a rejection, so a
    # sheet that discloses nothing about read-vs-skipped sources fails the gate.
    cov_reason = validate_coverage(text)
    cov_present = _coverage_section(text) is not None
    if cov_reason is not None:
        print(f"REJECT  coverage manifest\n        -> {cov_reason}")
        return 1
    if args.require_coverage and not cov_present:
        print("REJECT  coverage manifest\n        -> missing `## Coverage` manifest "
              "header (#514): disclose pin, matched count, per-file read counts, and "
              "skipped files (or `skipped: none`)")
        return 1

    # Only the fact-sheet section: stop at the NEEDS-OWNER list (Story 3.3),
    # whose entries use a different `CANDIDATE / REASON / TOPIC` schema.
    fs_lines = []
    for ln in text.split("\n"):
        if re.match(r"^#+\s*NEEDS-OWNER\b", ln):
            break
        fs_lines.append(ln)
    entries = [ln[2:] for ln in fs_lines if ln.startswith("- ")]
    rejected = 0
    for raw, reason in (validate_entry(e, host, sources) for e in entries):
        if reason is None:
            if not args.rejected:
                print(f"VALID   {raw}")
        else:
            rejected += 1
            print(f"REJECT  {raw}\n        -> {reason}")
    if not args.rejected:
        print(f"\n{len(entries)} entries, {rejected} rejected.")
    return 1 if rejected else 0


if __name__ == "__main__":
    sys.exit(main())
