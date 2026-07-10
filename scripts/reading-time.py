#!/usr/bin/env python3
"""reading-time.py — estimate an article body's reading time (Story 7.5, CAP-6).

The informational-bucket reading-time item for runs that produce or review an
article body:

  * EN: words / ~200 wpm
  * JA: characters (whitespace-stripped) / ~500 cpm

Prints `~N min read` (minimum 1 for any non-empty body). A standalone harvest run
has no article body and does not call this. Stdlib-only.
"""

import argparse
import re
import sys

EN_WPM = 200
JA_CPM = 500


def estimate(text, language):
    """Return (minutes, unit_count) for the given body text."""
    if language == "ja":
        unit = len(re.sub(r"\s+", "", text))
        raw = unit / JA_CPM
    else:
        unit = len(text.split())
        raw = unit / EN_WPM
    minutes = max(1, round(raw)) if unit > 0 else 0
    return minutes, unit


def _strip_frontmatter(text):
    return re.sub(r"\A---\n.*?\n---\n", "", text, count=1, flags=re.DOTALL)


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--language", choices=["en", "ja"], default="en")
    p.add_argument("file")
    args = p.parse_args(argv)

    with open(args.file, encoding="utf-8") as fh:
        text = _strip_frontmatter(fh.read())
    minutes, _ = estimate(text, args.language)
    print(f"~{minutes} min read")
    return 0


if __name__ == "__main__":
    sys.exit(main())
