#!/usr/bin/env python3
"""validate-interview-items.py — schema-enforce Stage-2 interview items
(Story 14.3, SPEC-policy-source-seam CAP-3; formats in seam-formats.md §2).

Every Stage-2 candidate question — policy-seeded or generic — is one item:

    {"id": "q3", "gap_type": "contradiction",
     "seed": {"quote": "...", "pointer": "LESSONS.md:41@<sha>"} | null,
     "question": "...", "owner_answer": ""}

`gap_type` is a CLOSED vocabulary: the existing NEEDS-OWNER taxonomy
(audience, motivation, surprise, tradeoff, significance, warning, opinion,
retrospective — the question-bank topics) plus exactly four TENSION types
(contradiction, ambiguity, missing-rationale, reversal-candidate). Tension
types are the only types a policy seed may generate — the schema is where the
guarantee lives, so validation runs BEFORE triage and a bad item can never
reach the owner.

Rejection classes (each has a fixture under fixtures/interview-items/):

  R1  `owner_answer` non-empty at generation — the tool cannot pre-decide;
      the schema has nowhere to put a decision.
  R2  a tension-typed item with `seed: null` — traceability is a validation
      rule, not a convention — OR a policy seed on a non-tension type
      (tension types are the only types a seed may generate).
  R3  a seed whose pointer is missing, unpinned, or outside the structural
      whitelist: `GLOSSARY.md | LESSONS.md | topics/<basename>.md`
      `:line[-line]@sha` (7-40 hex; the same FILEPIN grammar as fact sheets).
      A seed with an empty quote is the same failure — nothing auditable.
  R4  a seeded question that merely RESTATES its seed — confirmation is not a
      gap type. Mechanical rule (documented, not vibes): strip a leading
      confirmation stem ("do you", "is it", "would you agree", …) and
      stopwords; if >= 80% of the question's remaining content words appear
      in the seed quote, the question adds no tension and is rejected.
  R5  `gap_type` outside the closed vocabulary.

Input: a JSON array of items (or {"items": [...]}) from a file argument or
stdin (`-`). Output: silent + exit 0 when every item passes; else one
`[<item id>] R<n>: <reason>` line per rejection on stderr and exit 1.
"""

import argparse
import json
import re
import sys

NEEDS_OWNER_TAXONOMY = {
    "audience", "motivation", "surprise", "tradeoff", "significance",
    "warning", "opinion", "retrospective",
}
TENSION_TYPES = {"contradiction", "ambiguity", "missing-rationale", "reversal-candidate"}
GAP_TYPES = NEEDS_OWNER_TAXONOMY | TENSION_TYPES

# The structural read whitelist, as a pointer grammar: only files the bounded
# reader (read-policy-source.py) can have read are quotable, and every pointer
# must be commit-pinned (validate-fact-sheet.py's FILEPIN convention).
POINTER_RE = re.compile(
    r"^(GLOSSARY\.md|LESSONS\.md|topics/[^/\s]+\.md):\d+(-\d+)?@[0-9a-f]{7,40}$")

# R4: a confirmation-shaped question opens with one of these stems and then
# contributes (almost) no content word beyond its seed quote.
CONFIRMATION_STEMS = (
    "do you", "did you", "is it", "is this", "are you", "would you agree",
    "can you confirm", "do you confirm", "is that", "does this",
)
STOPWORDS = {
    "a", "an", "the", "of", "in", "on", "to", "for", "and", "or", "is", "are",
    "was", "were", "it", "this", "that", "you", "your", "we", "our", "do",
    "does", "did", "with", "as", "at", "by", "be", "not", "no", "still",
    "true", "agree", "confirm", "why", "what", "how", "when", "which", "who",
}
RESTATEMENT_THRESHOLD = 0.8


def _words(text):
    return [w for w in re.findall(r"[a-z0-9][a-z0-9'-]*", text.lower())
            if w not in STOPWORDS]


def is_restatement(question, quote):
    """True when the question merely restates the quote (mechanical R4 rule):
    >= 80% of its content words (stems and stopwords stripped) already appear
    in the seed quote. A question with no content words of its own is a
    restatement by definition."""
    q = question.strip().lower()
    for stem in CONFIRMATION_STEMS:
        if q.startswith(stem):
            q = q[len(stem):]
            break
    qw = _words(q)
    if not qw:
        return True
    quote_words = set(_words(quote))
    hit = sum(1 for w in qw if w in quote_words)
    return hit / len(qw) >= RESTATEMENT_THRESHOLD


def validate_items(items):
    """Return a list of (item_id, code, message) rejections; empty = valid."""
    rejections = []
    if not isinstance(items, list):
        return [("(input)", "R5", "input is not a JSON array of interview items")]
    for idx, item in enumerate(items):
        iid = item.get("id") if isinstance(item, dict) else None
        iid = iid or f"(item {idx})"

        def rej(code, msg):
            rejections.append((iid, code, msg))

        if not isinstance(item, dict):
            rej("R5", "item is not an object")
            continue
        missing = [k for k in ("id", "gap_type", "question", "owner_answer")
                   if k not in item]
        if "seed" not in item:
            missing.append("seed")
        if missing:
            rej("R5", f"missing required field(s): {', '.join(missing)}")
            continue

        gap_type = item["gap_type"]
        seed = item["seed"]

        if item["owner_answer"] != "":
            rej("R1", "owner_answer is pre-filled; it must be structurally "
                      "empty at generation — the tool cannot pre-decide")
        if gap_type not in GAP_TYPES:
            rej("R5", f"unknown gap_type {gap_type!r}; the vocabulary is closed "
                      f"(NEEDS-OWNER taxonomy + {', '.join(sorted(TENSION_TYPES))})")
        elif gap_type in TENSION_TYPES and seed is None:
            rej("R2", f"tension type {gap_type!r} requires a seed "
                      "(quote + pinned pointer); traceability is a rule, not a convention")
        elif gap_type not in TENSION_TYPES and seed is not None:
            rej("R2", f"a policy seed may only generate tension types, not {gap_type!r}")

        if seed is not None:
            if not isinstance(seed, dict) or not seed.get("quote", "").strip():
                rej("R3", "seed has no quote — nothing auditable")
            pointer = (seed or {}).get("pointer", "") if isinstance(seed, dict) else ""
            if not POINTER_RE.match(pointer or ""):
                rej("R3", f"seed pointer {pointer!r} is missing, unpinned, or outside "
                          "the whitelist (GLOSSARY.md | LESSONS.md | topics/<basename>.md"
                          ":line[-line]@sha)")
            elif isinstance(seed, dict) and seed.get("quote", "").strip() \
                    and not str(item["question"]).strip():
                rej("R4", "empty question")
            elif isinstance(seed, dict) and seed.get("quote", "").strip() \
                    and is_restatement(str(item["question"]), seed["quote"]):
                rej("R4", "question merely restates its seed — confirmation is "
                          "not a gap type; ask the tension, not the quote")
        if not str(item["question"]).strip() and not any(
                r[0] == iid and r[1] == "R4" for r in rejections):
            rej("R5", "question is empty")
    return rejections


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("items", help="path to the items JSON, or - for stdin")
    args = p.parse_args(argv)
    raw = sys.stdin.read() if args.items == "-" else open(args.items, encoding="utf-8").read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        sys.stderr.write(f"error: items input is not valid JSON: {e}\n")
        return 2
    if isinstance(data, dict) and "items" in data:
        data = data["items"]
    rejections = validate_items(data)
    if not rejections:
        return 0
    for iid, code, msg in rejections:
        sys.stderr.write(f"[{iid}] {code}: {msg}\n")
    sys.stderr.write(f"\n{len(rejections)} rejection(s); no item reaches the owner "
                     "until the set validates.\n")
    return 1


if __name__ == "__main__":
    sys.exit(main())
