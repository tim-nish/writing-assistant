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
      The optional `seed.companion` — the same-surface line that resolves an
      apparent conflict, carried so a tension raised anyway is raised WITH its
      resolver (#299) — is held to the identical quote+pointer rule: a
      companion that is not auditable is worse than no companion, because it
      is shown to the owner as the reason the question is narrow.
  R4  a seeded question that merely RESTATES its seed — confirmation is not a
      gap type. Mechanical rule (documented, not vibes): strip a leading
      confirmation stem ("do you", "is it", "would you agree", …) and
      stopwords; if >= 80% of the question's remaining content words appear
      in the seed quote, the question adds no tension and is rejected.
  R5  `gap_type` outside the closed vocabulary.

Reconciliation items (Story 13.75, SPEC-policy-source-seam CAP-7 `conflict`
class; seam-formats.md §2 "Reconciliation item"): a config↔policy(↔repo)
disagreement is a `gap_type: "reconciliation"` item that carries a `positions`
array INSTEAD of a seed — every disagreeing position, each
`{quote, pointer, authority}` with `authority` ∈ {policy, config, repo}. The
pointer grammar is per-authority:

  policy  the existing FILEPIN whitelist grammar
          (`GLOSSARY.md|LESSONS.md|topics/<name>.md:line[-line]@sha`);
  config  an authoritative user-config key path + configVersion
          (`syndication.policy.en.mode@<version>`);
  repo    the harvest pointer convention (`path:line[-line]@sha`).

`owner_answer` stays structurally empty (R1 applies unchanged). Additional
rejection classes:

  R8  a `reconciliation` item with <2 positions, or any position missing its
      quote/pointer/authority, or an invalid authority — a conflict needs both
      sides, auditable.
  R9  mutually exclusive shapes — a `reconciliation` item carrying a `seed`,
      or any other gap type carrying `positions`: the reconciliation gate
      cannot be bypassed by re-typing a conflict. (The classifier's own output
      validation enforces the other half — a conflict subject never passes
      through as an ordinary item; `draft-pipeline.py classify-policy`.)

Recommended-default items (Story 13.59, SPEC-policy-editorial-direction CAP-6)
carry an optional `recommended_default` — a policy-recalled position offered as
a proposed default the owner ratifies (approve/modify/replace/skip), for an
*editorial-judgment* gap only. It is a distinct shape from a tension seed and
keeps `owner_answer` structurally empty at generation (R1 still applies). Its
own rejection classes, distinct from R1/R5:

  R6  a `recommended_default` on an INELIGIBLE gap type — a default is offered
      only for the editorial-judgment classes (opinion, significance, surprise,
      tradeoff, warning, audience); every other NEEDS-OWNER class (motivation,
      retrospective, and by construction the factual/numerical/repository-state/
      verification gaps that never become editorial-judgment items) is
      ineligible and its default is rejected.
  R7  a `recommended_default` on a TENSION-typed item — tension questions are
      owner-only by nature (NFR15) and never carry a default.
  R3  also covers a `recommended_default` that is not auditable: a missing
      proposed-answer text, an empty recalled quote, or a pointer that is
      unpinned or outside the structural whitelist — the recalled position must
      resolve at its pin exactly like a seed (invariant 3, audited). In the
      multi-candidate form it applies per candidate.
  R10 a `recommended_default.candidates` list (Story 13.92, #423) that is not
      1-3 entries. The multi-candidate form carries 1-3 machine-proposed
      answers ORDERED by recontextualizing power (most-reframing first), each
      auditable like a single default (R3, per candidate); the owner ratifies
      exactly one (approve/modify/replace/skip) and the machine is never final
      (R1 unchanged). A `recommended_default` with no `candidates` key is the
      single-position N=1 case — byte-identical to before.

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
# The conflict-classified question shape (Story 13.75, CAP-7): carries a
# `positions` array instead of a seed — see the module docstring.
RECONCILIATION_TYPE = "reconciliation"
GAP_TYPES = NEEDS_OWNER_TAXONOMY | TENSION_TYPES | {RECONCILIATION_TYPE}

# The editorial-judgment classes eligible for a policy-recalled recommended
# default (SPEC-policy-editorial-direction CAP-6, Story 13.59). A subset of the
# NEEDS-OWNER taxonomy: `motivation` and `retrospective` are deliberately out,
# and every tension type is out (owner-only, NFR15).
ELIGIBLE_DEFAULT_TYPES = {
    "opinion", "significance", "surprise", "tradeoff", "warning", "audience",
}

# The structural read whitelist, as a pointer grammar: only files the bounded
# reader (read-policy-source.py) can have read are quotable, and every pointer
# must be commit-pinned (validate-fact-sheet.py's FILEPIN convention).
POINTER_RE = re.compile(
    r"^(GLOSSARY\.md|LESSONS\.md|topics/[^/\s]+\.md):\d+(-\d+)?@[0-9a-f]{7,40}$")

# Reconciliation-position pointer grammars, one per authority (Story 13.75,
# seam-formats.md §2): `policy` reuses the FILEPIN whitelist grammar above;
# `config` cites a user-config key path at its configVersion; `repo` uses the
# harvest pointer convention (any repo path, commit-pinned).
CONFIG_POINTER_RE = re.compile(r"^[A-Za-z0-9_.-]+@[A-Za-z0-9._-]+$")
REPO_POINTER_RE = re.compile(r"^[^\s@]+:\d+(-\d+)?@[0-9a-f]{7,40}$")
POSITION_POINTER_RES = {
    "policy": POINTER_RE,
    "config": CONFIG_POINTER_RE,
    "repo": REPO_POINTER_RE,
}

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
        # Mutually exclusive shapes (R9): a reconciliation item carries
        # `positions`, every other item carries `seed` (possibly null).
        if item.get("gap_type") == RECONCILIATION_TYPE:
            if "positions" not in item:
                missing.append("positions")
        elif "seed" not in item:
            missing.append("seed")
        if missing:
            rej("R5", f"missing required field(s): {', '.join(missing)}")
            continue

        gap_type = item["gap_type"]
        seed = item.get("seed")

        if item["owner_answer"] != "":
            rej("R1", "owner_answer is pre-filled; it must be structurally "
                      "empty at generation — the tool cannot pre-decide")
        if gap_type not in GAP_TYPES:
            rej("R5", f"unknown gap_type {gap_type!r}; the vocabulary is closed "
                      f"(NEEDS-OWNER taxonomy + {', '.join(sorted(TENSION_TYPES))} "
                      f"+ {RECONCILIATION_TYPE})")
        elif gap_type == RECONCILIATION_TYPE:
            if seed is not None:
                rej("R9", "a reconciliation item must not carry a seed — the "
                          "shapes are mutually exclusive (positions carry every "
                          "disagreeing side; a seed would re-type the conflict)")
                seed = None  # positions are the item's evidence; validate them below
        elif gap_type in TENSION_TYPES and seed is None:
            rej("R2", f"tension type {gap_type!r} requires a seed "
                      "(quote + pinned pointer); traceability is a rule, not a convention")
        elif gap_type not in TENSION_TYPES and seed is not None:
            rej("R2", f"a policy seed may only generate tension types, not {gap_type!r}")

        # R9's other face: only a reconciliation item may carry positions — a
        # conflict presented as any other item type bypasses the reconciliation
        # gate by re-typing (seam-formats.md §2).
        if gap_type != RECONCILIATION_TYPE and item.get("positions") is not None:
            rej("R9", f"gap type {gap_type!r} must not carry a positions array — "
                      "a conflict-classified subject is presented only as a "
                      "reconciliation item, never re-typed")
        if gap_type == RECONCILIATION_TYPE:
            positions = item.get("positions")
            if not isinstance(positions, list) or len(positions) < 2:
                rej("R8", "a reconciliation item needs >=2 positions — a "
                          "conflict has at least two disagreeing sides")
            else:
                for i, pos in enumerate(positions):
                    if not isinstance(pos, dict):
                        rej("R8", f"positions[{i}] is not an object")
                        continue
                    authority = pos.get("authority")
                    if authority not in POSITION_POINTER_RES:
                        rej("R8", f"positions[{i}] authority {authority!r} is invalid "
                                  "(valid: policy, config, repo)")
                        continue
                    if not str(pos.get("quote", "")).strip():
                        rej("R8", f"positions[{i}] ({authority}) has no quote — "
                                  "nothing auditable")
                    pointer = str(pos.get("pointer", "") or "")
                    if not POSITION_POINTER_RES[authority].match(pointer):
                        rej("R8", f"positions[{i}] ({authority}) pointer {pointer!r} "
                                  "is missing or malformed for its authority "
                                  "(policy: whitelist FILEPIN; config: "
                                  "<key-path>@configVersion; repo: path:line@sha)")

        if seed is not None:
            if not isinstance(seed, dict) or not seed.get("quote", "").strip():
                rej("R3", "seed has no quote — nothing auditable")
            pointer = (seed or {}).get("pointer", "") if isinstance(seed, dict) else ""
            if not POINTER_RE.match(pointer or ""):
                rej("R3", f"seed pointer {pointer!r} is missing, unpinned, or outside "
                          "the whitelist (GLOSSARY.md | LESSONS.md | topics/<basename>.md"
                          ":line[-line]@sha)")
            # The optional resolving line (#299) is auditable on the same terms
            # as the seed itself: it is shown to the owner as the reason the
            # question is narrow, so an unpinned or quote-less companion is a
            # rejection, not a nicety.
            if isinstance(seed, dict) and seed.get("companion") is not None:
                comp = seed["companion"]
                if not isinstance(comp, dict) or not str(comp.get("quote", "")).strip():
                    rej("R3", "seed.companion has no quote — a resolving line shown to "
                              "the owner must be quotable")
                elif not POINTER_RE.match(str(comp.get("pointer", "")) or ""):
                    rej("R3", f"seed.companion pointer {comp.get('pointer')!r} is missing, "
                              "unpinned, or outside the whitelist — the resolving line "
                              "must be auditable at the pin, like the seed")
            elif isinstance(seed, dict) and seed.get("quote", "").strip() \
                    and not str(item["question"]).strip():
                rej("R4", "empty question")
            elif isinstance(seed, dict) and seed.get("quote", "").strip() \
                    and is_restatement(str(item["question"]), seed["quote"]):
                rej("R4", "question merely restates its seed — confirmation is "
                          "not a gap type; ask the tension, not the quote")
        # Recommended default (Story 13.59) — an optional, policy-recalled
        # proposed answer for an editorial-judgment gap. Absent by default, so
        # every existing item shape is byte-identical to before.
        rd = item.get("recommended_default")
        if rd is not None:
            # Eligibility (R6/R7) is a property of the item's gap type — it
            # applies whether the default is a single position or a candidate
            # list, and is checked once.
            if gap_type in TENSION_TYPES:
                rej("R7", f"a recommended default on tension type {gap_type!r} is "
                          "rejected — tension questions are owner-only (NFR15) and "
                          "never carry a default")
            elif gap_type not in ELIGIBLE_DEFAULT_TYPES:
                rej("R6", f"a recommended default on gap type {gap_type!r} is "
                          "rejected — only editorial-judgment classes are eligible "
                          f"({', '.join(sorted(ELIGIBLE_DEFAULT_TYPES))})")

            # Auditability holds regardless of eligibility (invariant 3): a
            # proposed position must carry a proposed answer, a quote, and a
            # pinned whitelist pointer, or it is not offerable.
            def _audit_position(pos, label):
                if not isinstance(pos, dict) or not str(pos.get("default", "")).strip():
                    rej("R3", f"{label} has no proposed answer text — "
                              "nothing for the owner to ratify")
                    return
                if not str(pos.get("quote", "")).strip():
                    rej("R3", f"{label} has no recalled quote — the "
                              "proposed default is not auditable")
                if not POINTER_RE.match(str(pos.get("pointer", "")) or ""):
                    rej("R3", f"{label} pointer {pos.get('pointer')!r} is "
                              "missing, unpinned, or outside the whitelist — a "
                              "recalled position must resolve at its pin like a seed")

            # Two shapes (Story 13.92, #423): a single recalled position (N=1,
            # the original form) OR a `candidates` list of 1-3 positions ordered
            # by recontextualizing power. Order is the caller's semantic
            # judgment; the schema enforces count (1-3) and per-candidate
            # auditability only, and the owner still ratifies exactly one.
            candidates = rd.get("candidates") if isinstance(rd, dict) else None
            if candidates is not None:
                if not isinstance(candidates, list) or not (1 <= len(candidates) <= 3):
                    rej("R10", "recommended_default.candidates must carry 1-3 entries "
                               "— 1-3 machine-proposed answers ordered by "
                               "recontextualizing power (most-reframing first)")
                else:
                    for i, cand in enumerate(candidates):
                        _audit_position(cand, f"candidates[{i}]")
            else:
                _audit_position(rd, "recommended_default")

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
