#!/usr/bin/env python3
"""validate-review-findings.py — enforce the review finding-class contract
(Story 13.62, SPEC-article-review "Finding class — writing-problem vs
missing-input").

Every review finding carries a class orthogonal to severity:

  writing-problem (default, unmarked): fixable in the draft — carries `Fix:`.
  missing-input   (`[missing-input]` marker): the draft lacks source material
                  prose cannot manufacture — carries `Upstream:` naming one of
                  two remediations (a scoped re-harvest, or one bounded owner
                  question), and is blocker-eligible.

The two shapes are mutually exclusive. The rejections:

  M1  a `[missing-input]` finding carrying a `Fix:` (a prose suggestion) and no
      `Upstream:` — an evidence gap is not fixable in prose.
  M2  a writing-problem finding (no marker) carrying an `Upstream:` — only a
      missing-input finding routes upstream.
  M3  a `[missing-input]` finding whose `Upstream:` is not one of the two
      forms (`re-harvest <target>` | `ask <question>`).

STYLE-CONTRACT CONFORMANCE — ITS OWN CLASS (Story 20.140, #1202; umbrella
#1191). The Reviewer's one style dimension is conformance to the owner's named
style contract, CITING THE CLAUSE. It carries the class `conformance` in the
severity slot — outside blocker/should/nit, and it never blocks — and its
`Contract:` citation replaces the `Why {severity}:` field. The citation is not
a formatting nicety: a preference delivered as a review finding is
indistinguishable to the reader from a contract requirement, and becomes one by
repetition, so a finding that cannot cite a clause IS TASTE AND IS NOT EMITTED.
This validator is what makes that mechanical rather than a matter of reviewer
discipline. The rejections:

  C1  a `[conformance]` finding with no conforming `Contract:` citation —
      `Contract: style contract §<SECTION> — "<verbatim clause quote>"`. The
      contract is named by ROLE, never by file path: it has exactly one reader
      (`style-contract.py`), which is the sole authority on where it lives.
  C2  a `[conformance]` finding citing a section whose carrier forbids it:
      `SYNTAX PROFILE` (no instrument, by ratified decision — a review finding
      would be that instrument arriving through the back door), `LEXICON`
      (already carried mechanically by the coinage lint; the Reviewer must not
      duplicate a mechanical check as a judgment), or `FIGURES` (ratified
      elsewhere). Only REGISTER and STRUCTURAL VOICE are measurable here.
  C3  a `blocker` / `should` / `nit` finding that cites the style contract — a
      conformance miss never enters the blocking vocabulary.

Input: a review findings block (one `- [severity] …` bullet per line) from a
file argument or stdin (`-`). Only `- [` bullet lines are checked; other lines
pass through. Output: silent + exit 0 when every finding conforms; else one
`[line <n>] M<k>|C<k>: <reason>` line per violation on stderr and exit 1.
"""

import argparse
import re
import sys

SEVERITIES = ("blocker", "should", "nit")
# `- [severity] [missing-input]? {location}: {issue}. … (Fix:|Upstream:) ….`
FINDING_RE = re.compile(
    r"^-\s*\[(?P<sev>[a-z]+)\]\s*"
    r"(?P<mi>\[missing-input\]\s*)?"
    r"(?P<rest>.*)$")
# The upstream remediation grammar: exactly one of the two forms.
UPSTREAM_RE = re.compile(r"Upstream:\s*(re-harvest\s+\S.*|ask\s+\S.*?)\s*$",
                         re.IGNORECASE)
HAS_FIX = re.compile(r"(^|\.\s*|\s)Fix:\s*\S", re.IGNORECASE)
HAS_UPSTREAM = re.compile(r"(^|\.\s*|\s)Upstream:\s*\S", re.IGNORECASE)

# --- the conformance class (Story 20.140) -----------------------------------
CONFORMANCE = "conformance"
# `Contract: style contract §REGISTER — "<verbatim clause quote>"`. The dash and
# the quote marks are accepted in their typographic forms too: the contract is
# the citation's PARTS (the named contract, its section, the verbatim clause),
# never a keystroke. The citation names the contract BY ROLE and never by file
# path — the artifact has exactly one reader (`style-contract.py`), which is the
# sole authority on where it lives; a second script naming its path is a second
# contract in waiting, and this validator reads findings, never the artifact.
CITATION_RE = re.compile(
    r"Contract:\s*(?:the\s+)?style[- ]contract\s*(?:v\S+\s*)?§\s*"
    r"(?P<sec>[A-Z][A-Z ]*[A-Z])\s*[—–-]\s*[\"“](?P<quote>[^\"”]+)[\"”]",
    re.IGNORECASE)
# A reference to the contract in ANY finding — how C3 spots a style finding that
# put on a blocking severity.
STYLE_REF_RE = re.compile(r"style[- ]contract|§\s*(?:REGISTER|STRUCTURAL VOICE)",
                          re.IGNORECASE)
MEASURABLE = ("REGISTER", "STRUCTURAL VOICE")
# Why each forbidden section is forbidden, carried at the point of rejection.
FORBIDDEN = {
    "SYNTAX PROFILE":
        "the syntax profile carries NO INSTRUMENT by ratified decision — a "
        "review finding against it is that instrument arriving through the "
        "back door",
    "LEXICON":
        "the lexicon is carried MECHANICALLY by the existing coinage lint; the "
        "Reviewer must not duplicate a mechanical check as a judgment",
    "FIGURES":
        "figures are ratified elsewhere (SPEC-article-visuals) and are never "
        "re-derived as a review finding",
}


def validate(text):
    """Yield (lineno, code, reason) for each violation."""
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line.startswith("- ["):
            continue
        m = FINDING_RE.match(line)
        if not m:
            continue
        is_missing_input = bool(m.group("mi"))
        rest = m.group("rest")
        has_fix = bool(HAS_FIX.search(rest))
        has_upstream = bool(HAS_UPSTREAM.search(rest))
        sev = m.group("sev")

        if sev == CONFORMANCE:
            forbidden = [s for s in FORBIDDEN
                         if re.search(r"§\s*" + s, rest)]
            cite = CITATION_RE.search(rest)
            if forbidden:
                for s in forbidden:
                    yield (lineno, "C2",
                           f"a [conformance] finding cites `§{s}` — {FORBIDDEN[s]}. "
                           "This dimension measures REGISTER and STRUCTURAL "
                           "VOICE only")
            elif not cite or cite.group("sec").strip().upper() not in MEASURABLE:
                yield (lineno, "C1",
                       "a [conformance] finding must cite the clause it "
                       "measures against — `Contract: style contract "
                       "§REGISTER|§STRUCTURAL VOICE — \"<verbatim clause "
                       "quote>\"`. A finding that cannot cite a clause is NOT "
                       "EMITTED, because it is taste: a preference delivered "
                       "as a review finding is indistinguishable from a "
                       "contract requirement and becomes one by repetition")
            continue

        if STYLE_REF_RE.search(rest):
            yield (lineno, "C3",
                   f"a [{sev}] finding cites the style contract — conformance "
                   "is its OWN class outside blocker/should/nit and never "
                   "blocks. Re-tag it [conformance] with its `Contract:` "
                   "citation, or drop it: a conformance miss and a factual "
                   "error are different kinds, not different severities")
            continue

        if is_missing_input:
            if not has_upstream:
                yield (lineno, "M1",
                       "a [missing-input] finding must name an upstream "
                       "remediation (`Upstream: re-harvest <target>` or "
                       "`Upstream: ask <question>`), not a prose Fix: — an "
                       "evidence gap cannot be repaired in prose")
            elif not UPSTREAM_RE.search(rest):
                yield (lineno, "M3",
                       "a [missing-input] finding's Upstream: must be exactly "
                       "one of `re-harvest <target>` or `ask <question>`")
        else:
            if has_upstream:
                yield (lineno, "M2",
                       "a writing-problem finding (no [missing-input] marker) "
                       "carries an Upstream: — only a missing-input finding "
                       "routes upstream; mark it [missing-input] or use Fix:")


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("findings", nargs="?", default="-",
                   help="review findings block, or - for stdin")
    args = p.parse_args(argv)
    text = sys.stdin.read() if args.findings == "-" else open(args.findings, encoding="utf-8").read()
    violations = list(validate(text))
    if not violations:
        return 0
    for lineno, code, reason in violations:
        sys.stderr.write(f"[line {lineno}] {code}: {reason}\n")
    sys.stderr.write(f"\n{len(violations)} finding-class violation(s); "
                     "no finding reaches arbitration until the set conforms.\n")
    return 1


if __name__ == "__main__":
    sys.exit(main())
