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
import json
import re
import sys

EN_WPM = 200
JA_CPM = 500

# Reading-time bands as the owner's DEPTH-CHOICE unit (Story 18.27, CAP-8 clause
# #506). The bands are the unit in which the owner may *express* a depth choice;
# each maps to a depth *directive* (a level), NEVER a reading-time target the
# pipeline optimizes toward. Base minutes per level; the deep bands grow with the
# selected-element count (a bigger piece suggests a longer deep-dive), but the
# recorded value is always the level, not the number.
_BAND_BASE = (("note", 3), ("standard", 7), ("deep-dive", 15))
# When a chosen band and the actual estimate diverge by more than this, surface
# an informational FYI (CAP-6) — never a split or a trim.
_FYI_MIN_ABS = 3


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


def bands(elements=0):
    """The suggested reading-time bands for the depth question, derived from the
    selected-element count. Each band records the depth DIRECTIVE (a level) it
    expresses — not a reading-time target. A `custom` value is always offered."""
    out = []
    for level, base in _BAND_BASE:
        minutes = base
        if elements and level in ("standard", "deep-dive"):
            # scale the deeper bands with the piece's size; the note stays tight
            per = 2 if level == "standard" else 4
            minutes = max(base, per * elements)
        out.append({
            "level": level, "minutes": minutes,
            "label": f"~{minutes} min {level}",
            # the pick is recorded AS the depth directive (mapped to a level),
            # NEVER a reading-time target.
            "depth_directive": {"level": level},
        })
    return {
        "bands": out,
        "custom": True,
        "note": ("pick a band or type a custom value; the pick is recorded AS "
                 "the depth directive (a level), NOT a reading-time target the "
                 "pipeline ever optimizes toward — the estimate stays "
                 "informational and nothing auto-splits or auto-trims."),
    }


def _strip_frontmatter(text):
    return re.sub(r"\A---\n.*?\n---\n", "", text, count=1, flags=re.DOTALL)


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--language", choices=["en", "ja"], default="en")
    p.add_argument("--bands", action="store_true",
                   help="print the suggested reading-time depth bands (CAP-8 "
                        "clause, #506) as JSON, instead of estimating a file; "
                        "each band maps to a depth directive, not a target")
    p.add_argument("--elements", type=int, default=0,
                   help="selected-element count the bands are derived from "
                        "(a bigger piece suggests a longer deep-dive band)")
    p.add_argument("--band-minutes", type=int, default=None,
                   help="the chosen band's minutes: when the estimate diverges "
                        "from it by a large margin, an informational FYI is "
                        "appended — never a split or trim")
    p.add_argument("file", nargs="?")
    args = p.parse_args(argv)

    # Bands mode: the depth question's suggested options — no file needed.
    if args.bands:
        print(json.dumps(bands(args.elements), indent=2))
        return 0

    if not args.file:
        p.error("a file is required unless --bands is given")

    with open(args.file, encoding="utf-8") as fh:
        text = _strip_frontmatter(fh.read())
    minutes, _ = estimate(text, args.language)
    print(f"~{minutes} min read")
    # Informational FYI only (CAP-6): a large miss between the chosen band and
    # the estimate is surfaced for the owner to decide — the pipeline never
    # auto-splits or auto-trims to hit the number.
    if args.band_minutes is not None:
        gap = minutes - args.band_minutes
        if abs(gap) > max(_FYI_MIN_ABS, args.band_minutes // 2):
            direction = "under" if gap < 0 else "over"
            print(f"FYI: the estimate (~{minutes} min) runs well {direction} the "
                  f"chosen ~{args.band_minutes} min band — informational only; "
                  "depth is your editorial call, and nothing is auto-adjusted.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
