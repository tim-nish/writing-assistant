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

Input: a review findings block (one `- [severity] …` bullet per line) from a
file argument or stdin (`-`). Only `- [` bullet lines are checked; other lines
pass through. Output: silent + exit 0 when every finding conforms; else one
`[<n>] M<k>: <reason>` line per violation on stderr and exit 1.
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
