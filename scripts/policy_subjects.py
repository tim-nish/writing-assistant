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
# user-config key are mechanically comparable. The spec's `determined` and
# `constrained` classes activate as comparable subjects gain determining/
# excluding semantics; the shipped EN-topology detector emits `conflict`.
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
