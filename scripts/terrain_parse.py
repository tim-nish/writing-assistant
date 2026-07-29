#!/usr/bin/env python3
"""terrain_parse — served-artifact parsing (Story 20.41, #904).

Extracted from `terrain_map.py` per the packaging invariant's scripts-family
clause (`specs/spec-writing-assistant/SPEC.md`, amended 2026-07-29, #900), one
seam along from `terrain_seam`: that module owns the served ENVELOPE, this one
decodes the lines inside it.

**This module is shrinking by design.** Every parser here decodes text the hub
could serve as fields instead, and the ratified direction is to serve structure
so there is nothing to parse. Where a manifest field replaces one of these — as
the element manifest already replaced the by-topic axis's raw thread read
(#886) — the parser RETIRES rather than being carried along. A parser added
here without that trajectory in mind is going the wrong way.

Every marker below was verified against the served surface rather than
inferred from spec prose; a consumer quotes a ratified field and never
paraphrases one into existence.
"""

import os
import re

# One tier-1 Gloss overview line (`gloss/INDEX.md`): `- **<slug>** — <headline>
# (<tags>)[ · journeys/<tag>]`. The headline is the FIRST SENTENCE of the
# lesson's ratified `gloss:` rendering, verbatim (hub `specs/gloss.md` —
# consumers quote the ratified field, never re-express it). The optional
# trailing marker is the hub's per-lesson Journey discovery (`specs/gloss.md`
# §5.1, product-lab#106): the address of the journey shard holding this
# lesson's arc. Verified against the hub's generated index rather than
# inferred.
GLOSS_LINE = re.compile(
    r"^-\s+\*\*(.+?)\*\*\s+—\s+(.*?)"
    r"(?:\s+\(([^()]*)\))?"
    r"(?:\s+·\s+(journeys/[\w-]+))?$"
)

# What a topic line looks like on the served surface: `- <date> — <text>`,
# verified against product-lab@<private-pin> rather than inferred.
ELEMENT_LINE = re.compile(r"^-\s+(\d{4}-\d{2}-\d{2})\s+—\s+(.*)$")

# The heading whose lines are rejections rather than decisions. Membership of
# this SECTION is the marker — not the word "declined", which appears inline in
# ordinary decision lines ("... declined as a conformance copy ...") and would
# misclassify most of a topic file as reversals.
DECLINED_HEADING = "declined"

# The other native reversal record: a struck-through clause inside a dated line
# marks the superseded position (topics/articles.md:17@<private-pin> is one).
STRUCK = "~~"

ELEMENT_SUMMARY_CHARS = 200

# A topic decision line's trailing provenance pointer and a decisions-shard
# entry heading carry the same key: `q_a/<batch> D<n>` (Story 20.22, #851;
# shard shape read from the served surface, not inferred). Rally suffixes and
# the heading's `· <date>` tail are outside the captured key on both sides.
DECISION_POINTER = re.compile(r"\(q_a/([^\s)]+)\s+D(\d+)[^)]*\)\s*$")
# The batch date inside a record's own slug — served, never re-parsed prose.
RECORD_BATCH_DATE = re.compile(r"^q_a/(\d{4}-\d{2}-\d{2})")
DECISION_SHARD_HEAD = re.compile(r"^##\s*\(q_a/([^\s)]+)\s+D(\d+)[^)]*\)\s*$")

# The batch date inside a record's own slug — served, never re-parsed prose.
RECORD_BATCH_DATE = re.compile(r"^q_a/(\d{4}-\d{2}-\d{2})")
DECISION_SHARD_HEAD = re.compile(r"^##\s*\(q_a/([^\s)]+)\s+D(\d+)[^)]*\)\s*$")

DECISION_SHARD_HEAD = re.compile(r"^##\s*\(q_a/([^\s)]+)\s+D(\d+)[^)]*\)\s*$")

def _lesson_seed(text, cite):
    """One LESSONS.md index line as a lesson seed: `(id, title, cite)`.

    The index-line shape is the hub's own (`- [Title](lessons/<id>.md) — hook`),
    and only that shape is understood: the link target's stem is the seed's
    identifier, the link text its title. A line without a link keeps its text
    as the title and slugifies it for an identifier. Nothing here follows the
    link — lesson BODIES are out of the seam's reach (OQ3), and the hook text
    beyond the title is not projected as prose.
    """
    s = text.strip()
    if not s.startswith("- "):
        return None                      # a heading, a blank, a prose line
    s = s[2:].strip()
    ident, title = None, s
    if s.startswith("["):
        close = s.find("](")
        if close != -1:
            end = s.find(")", close)
            if end != -1:
                title = s[1:close].strip()
                target = s[close + 2:end].strip()
                ident = os.path.splitext(os.path.basename(target))[0] or None
    if ident is None:
        head = title.split("—")[0].split(" - ")[0].strip()
        ident = "".join(c if c.isalnum() else "-" for c in head.lower())
        ident = "-".join(p for p in ident.split("-") if p)
    if not ident:
        return None
    return ident, (title or ident), cite

def parse_decision_shard(stdout_text):
    """Entries of one served `decisions/<topic>` shard, keyed by provenance
    pointer (`q_a/<batch> D<n>`).

    The shard is the reader's `gloss --tag decisions/<topic>` output: `=== path
    @ sha` then `N: text` lines, entry headings `## (q_a/<batch> D<n> ·
    <date>)`, entry bodies the ratified plain-register rendering, whole. The
    rendering is quoted verbatim downstream — a consumer never re-expresses it.
    Measured at the pin this join was built against: shard entries carry NO
    per-entry tags, so `tags` is empty until the hub serves them — which is
    why a joined decision Strand still lands in the untagged-disclosure line
    rather than under an axis member.
    """
    entries, key, headline_no, body = {}, None, None, []
    path = sha = None

    def flush():
        if key and body:
            entries[key] = {
                "gloss": " ".join(" ".join(body).split()),
                "cite": f"{path}:{headline_no}@{sha}",
                "tags": [],
            }

    for line in stdout_text.splitlines():
        if line.startswith("miss: "):
            return {}
        if line.startswith("=== "):
            head = line[4:]
            p, _sep, c = head.rpartition(" @ ")
            path, sha = p.strip(), c.strip()
            continue
        number, _sep, text = line.partition(": ")
        if not number.strip().isdigit():
            continue
        t = text.strip()
        m = DECISION_SHARD_HEAD.match(t)
        if m:
            flush()
            key = f"q_a/{m.group(1)} D{m.group(2)}"
            headline_no, body = number.strip(), []
            continue
        if key and t and not t.startswith("#") and t != "---":
            body.append(t)
    flush()
    return entries


# A journey shard's entries are headed by the lesson slug whose arc they
# carry (`## <slug>`), which is the join key back to the lesson element. Shape
# read from the served surface, not inferred from the spec prose.
JOURNEY_SHARD_HEAD = re.compile(r"^##\s+([a-z0-9][a-z0-9-]*)\s*$")

def parse_journey_shard(stdout_text):
    """Entries of one served `journeys/<tag>` shard, keyed by lesson slug.

    Same reader shape as the decisions shard: `=== path @ sha` then `N: text`
    lines, entry headings `## <lesson-slug>`, entry bodies the ratified
    `journey_gloss:` rendering, whole. The rendering is quoted verbatim
    downstream — a consumer never re-expresses it and never synthesises an arc
    from a lesson headline.
    """
    entries, slug, headline_no, body = {}, None, None, []
    path = sha = None

    def flush():
        if slug and body:
            entries[slug] = {
                "gloss": " ".join(" ".join(body).split()),
                "cite": f"{path}:{headline_no}@{sha}",
            }

    for line in stdout_text.splitlines():
        if line.startswith("miss: "):
            return {}
        if line.startswith("=== "):
            head = line[4:]
            p, _sep, c = head.rpartition(" @ ")
            path, sha = p.strip(), c.strip()
            continue
        number, _sep, text = line.partition(": ")
        if not number.strip().isdigit():
            continue
        t = text.strip()
        m = JOURNEY_SHARD_HEAD.match(t)
        if m:
            flush()
            slug, headline_no, body = m.group(1), number.strip(), []
            continue
        if slug and t and not t.startswith("#") and t != "---":
            body.append(t)
    flush()
    return entries

def _element_summary(text):
    """One line of a topic decision, as a person reads it.

    The served text is markdown with emphasis and a trailing `(q_a/... D1)`
    provenance pointer. The pointer is the hub's own bookkeeping, not the
    decision, so it is dropped from the summary — the cite carries provenance.
    """
    body = re.sub(r"\s*\(q_a/[^)]*\)\s*$", "", str(text).strip())
    body = body.replace(STRUCK, "").replace("**", "").replace("`", "")
    body = " ".join(body.split())
    if len(body) > ELEMENT_SUMMARY_CHARS:
        body = body[:ELEMENT_SUMMARY_CHARS - 1].rstrip() + "…"
    return body

def parse_topic_elements(topic, served, commit, served_path=None):
    """The typed elements in one served topic file — FALLBACK ONLY since Story
    20.35 (#886); the axis now comes from the manifest, and this path runs when
    records cannot be acquired.

    `served` is the seam's `N: text` lines, in order. Two kinds are recognised,
    both markers verified against the served surface rather than inferred:
    `reversal` — a dated line under `## Declined`, or one carrying a
    struck-through clause; `decision` — any other dated line.

    Section membership is what types a Declined line — NOT the word "declined",
    which appears inline in many ordinary decision lines and would otherwise
    type most of a topic file as a reversal.
    """
    elements, heading = [], ""
    for number, text in served:
        stripped = text.strip()
        if stripped.startswith("## "):
            heading = stripped[3:].strip().lower()
            continue
        m = ELEMENT_LINE.match(stripped)
        if not m:
            continue
        date, body = m.group(1), m.group(2)
        declined = heading.startswith(DECLINED_HEADING)
        kind = "reversal" if (declined or STRUCK in body) else "decision"
        # The cite names the path the seam ACTUALLY SERVED, never one
        # recomposed from the topic key (CAP-4 as amended 2026-07-29, #873).
        # Recomposing it is what made an archive-for-live substitution
        # unobservable: the screen displayed archived decisions as the live
        # record and nothing anywhere reported it.
        cite = f"{served_path or f'topics/{topic}.md'}:{number}@{commit}"
        # The line's trailing provenance pointer, captured BEFORE the summary
        # strips it (Story 20.22, #851): it is the JOIN KEY into the served
        # `decisions/<topic>` shard, whose entries are headed by the same
        # `(q_a/<batch> D<n> · <date>)` pointer. A line with no D-numbered
        # pointer has no served rendering to join and stays pointerless.
        pm = DECISION_POINTER.search(body)
        pointer = f"q_a/{pm.group(1)} D{pm.group(2)}" if pm else None
        elements.append({
            "kind": kind,
            "decision_pointer": pointer,
            "summary": _element_summary(body),
            "topic": topic,
            # The situation it was recorded in: when, and exactly where.
            "date": date,
            "situation": cite,
            "evidence": [cite],
            # Marked, never hidden — the same rule lesson seeds follow. There
            # is no join to compute it against yet: `consumed_index` is keyed
            # by lesson id (`write-article-plan.py consult`), and the articles
            # repo declares no element-citation key. Disclosed rather than
            # guessed, and it widens exactly when that key appears.
            "consumed": False,
            "consumption_join": ("none — the articles repo declares no "
                                 "element-citation key"),
        })
    return elements
