#!/usr/bin/env python3
"""policy_subjects.py — the shared comparable-subjects detector.

The ONLY semantic knowledge the mechanical policy checks carry, extracted from
`draft-pipeline.py` (Story 13.75, SPEC-policy-source-seam CAP-7) so the plan
policy-conformance gate (Story 13.76, SPEC-article-plan CAP-4) validates
against the SAME table and the SAME detection rule — never a second,
drift-prone copy. Imported by `draft-pipeline.py classify-policy` and
`write-article-plan.py conformance`; behavior is byte-identical to the
pre-extraction classifier. Stdlib only.
"""

import re

# The declarative comparable-subjects table — the classifier's ONLY semantic
# knowledge, and its extension point. Classification applies to RATIFIED FACTS
# (recorded decisions about topology, naming, architecture — CAP-7's boundary);
# each row names one subject on which a served policy line and an authoritative
# user-config key are mechanically comparable.
#
# A row's OPTIONAL `excludes` tuple carries its EXCLUDING semantics (Story
# 18.49, #566): the answers the served line rules out without determining one.
# Conflict and constraint are the same subject seen against different config —
# when config asserts the excluded value the two AUTHORITIES disagree and the
# subject is a `conflict`; when it does not, the served line still rules that
# value out as an ANSWER, which is `constrained`. Conflict therefore takes
# precedence, and a row with no `excludes` never constrains.
COMPARABLE_SUBJECTS = (
    {
        "id": "en-topology",
        "label": "the EN publication topology",
        # The 2026-07-18 regression subject: a served records-only line for the
        # owner's Website vs `syndication.policy.en.mode: canonical`.
        "policy_line": re.compile(r"[Ww]ebsite stays independent|reference records.*only"),
        "policy_implies": "records-only",
        "config_key": "syndication.policy.en.mode",
        "conflicting_value": "canonical",
        # The records-only line rules a canonical EN topology OUT as an answer;
        # it does not determine which of the remaining topologies to use, so a
        # question on this subject stays asked with `canonical` shown-excluded.
        "excludes": ("canonical",),
    },
)


def parse_policy_surface(text):
    """Parse the reader's `read` output (pin line + `=== FILE @ sha` sections
    with `N: text` lines) into (pin, [{file, line, sha, text}])."""
    pin = None
    lines = []
    current_file = current_sha = None
    for raw in text.splitlines():
        if raw.startswith("pin: "):
            pin = raw[len("pin: "):].strip()
        elif raw.startswith("=== "):
            head = raw[4:]
            if " @ " in head:
                current_file, current_sha = head.rsplit(" @ ", 1)
                current_file, current_sha = current_file.strip(), current_sha.strip()
        elif raw.startswith("miss: "):
            current_file = current_sha = None
        else:
            m = re.match(r"^(\d+): (.*)$", raw)
            if m and current_file:
                lines.append({"file": current_file, "line": int(m.group(1)),
                              "sha": current_sha, "text": m.group(2)})
    return pin, lines


def config_lookup(cfg, dotted):
    cur = cfg
    for part in dotted.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


def detect_conflicts(surface_lines, cfg, config_version):
    """Conflict detection over the declared comparable subjects: a served
    policy line and an authoritative user-config key that disagree on one
    subject yield ONE conflict record naming both positions with their
    pointers (one per subject, not per matching line)."""
    conflicts = []       # [{subject, policy: {...}, config: {...}}]
    for subject in COMPARABLE_SUBJECTS:
        value = config_lookup(cfg, subject["config_key"])
        if value != subject["conflicting_value"]:
            continue
        for sl in surface_lines:
            if subject["policy_line"].search(sl["text"]):
                conflicts.append({
                    "subject": subject,
                    "policy": {
                        "quote": sl["text"].strip(),
                        "pointer": f"{sl['file']}:{sl['line']}@{sl['sha']}",
                        "authority": "policy",
                    },
                    "config": {
                        "quote": f"{subject['config_key']}: {value}",
                        "pointer": f"{subject['config_key']}@{config_version}",
                        "authority": "config",
                    },
                })
                break  # one reconciliation item per subject, not per matching line
    return conflicts


def detect_constraints(surface_lines, cfg, config_version, subjects=None):
    """Constraint detection over the declared comparable subjects (CAP-7
    `constrained`, Story 18.49/#566): a served policy line that rules some
    answers OUT without determining one yields ONE constraint record per
    subject, carrying the governing line's verbatim quote and pinned pointer so
    the excluded candidate can be SHOWN with its reason.

    Precedence: a subject whose authoritative config asserts the excluded value
    is a CONFLICT, not a constraint — two authorities disagreeing is the
    reconciliation case, and `detect_conflicts` owns it. Such a subject is
    skipped here so exactly one class claims it.

    `config_version` is accepted for signature parity with `detect_conflicts`
    (the constraint's authority is the served line alone, so no config pointer
    is cited); `subjects` overrides the table for fixtures.
    """
    constraints = []     # [{subject, policy: {...}, excludes: (...)}]
    for subject in (COMPARABLE_SUBJECTS if subjects is None else subjects):
        excludes = tuple(subject.get("excludes") or ())
        if not excludes:
            continue
        if config_lookup(cfg, subject["config_key"]) == subject.get("conflicting_value"):
            continue  # conflict wins — one subject, one class
        for sl in surface_lines:
            if subject["policy_line"].search(sl["text"]):
                constraints.append({
                    "subject": subject,
                    "policy": {
                        "quote": sl["text"].strip(),
                        "pointer": f"{sl['file']}:{sl['line']}@{sl['sha']}",
                        "authority": "policy",
                    },
                    "excludes": excludes,
                })
                break  # one constraint per subject, not per matching line
    return constraints


def excluded_by(constraint, text):
    """The excluded value `text` proposes, or None. Mechanical and
    case-insensitive — no semantic parsing: a candidate is excluded only when it
    literally names the ruled-out value.

    The match anchors at a word START and allows a trailing suffix, so an
    inflected proposal ("publish EN canonically") is caught alongside the bare
    config token ("canonical"). It never matches mid-word, so a value is never
    found inside an unrelated term.
    """
    for value in constraint["excludes"]:
        if re.search(rf"\b{re.escape(value)}\w*", str(text), re.IGNORECASE):
            return value
    return None
